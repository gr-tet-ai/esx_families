
-- ============================================================
-- v0.7.0b-kill-engine — War Kill Engine V2
-- ============================================================
local KillEngine = {
    recent  = {},   -- dedup: { ["killer:victim:sec"] = true }
    rejects = {},   -- ring buffer آخر 20 reject مع السبب
    accepts = {},   -- ring buffer آخر 10 kill مقبول
    maxLog  = 20,
}

local function _ringPush(buf, entry)
    table.insert(buf, 1, entry)
    while #buf > KillEngine.maxLog do table.remove(buf) end
end

local function KE_reject(killerCid, victimCid, reason)
    _ringPush(KillEngine.rejects, {
        t = os.date('%H:%M:%S'), killer = tostring(killerCid),
        victim = tostring(victimCid), reason = reason,
    })
    print(('[KillEngine][REJECT] killer=%s victim=%s reason=%s'):format(killerCid, victimCid, reason))
end

local function KE_accept(killerCid, victimCid, gid, pts)
    _ringPush(KillEngine.accepts, {
        t = os.date('%H:%M:%S'), killer = tostring(killerCid),
        victim = tostring(victimCid), gang = tostring(gid), pts = pts,
    })
    print(('[KillEngine][ACCEPT] killer=%s victim=%s gang=%s pts=%s'):format(killerCid, victimCid, gid, pts))
end

local function KE_dedupKey(killerSrc, victimSrc)
    return tostring(killerSrc)..':'..tostring(victimSrc)..':'..tostring(os.time())
end

local function KE_isDup(key)
    if KillEngine.recent[key] then return true end
    KillEngine.recent[key] = true
    -- تنظيف بعد 3 ثواني
    SetTimeout(3000, function() KillEngine.recent[key] = nil end)
    return false
end
-- ============================================================

-- ============================================================
-- qbx_families - War System (Server) v0.3.0
-- Score+Timer | Snapshot | War Council | Test Mode | Coward Status
-- مُحسَّن: thread واحد فقط أثناء حرب نشطة، throttling للأحداث،
-- batch writes للـ scores، lazy participant loading
-- ============================================================

ActiveWars      = {}   -- [warId] = { id, attacker_gang_id, defender_gang_id, zone_id, status, starts_at, ends_at, scores={[gid]=int}, kills={[gid]=int}, deaths={[gid]=int}, presence_minutes={[gid]=int}, participants={[cid]=gid}, vault_snapshot, loot_percent, is_test_mode, last_kill_event={[cid]=ms}, pending_score_writes={[gid]=true} }
ZoneActiveWar   = {}   -- [zone_id] = warId
GangActiveWar   = {}   -- [gang_id] = warId  (سواء مهاجم أو مدافع — عصابة في حرب وحدة فقط)
LastKillEventAt = {}   -- [src] = ms (throttling)

-- ============================================================
-- Helpers
-- ============================================================
local function now() return os.time() end

---@param gangId number
---@return number count
local function countOnlineGangMembers(gangId)
    local c = 0
    for cid, m in pairs(MembersCache) do
        if m.gang_id == gangId then
            local src = ESXBridge.GetPlayerByCitizenId(cid)
            if src and src.PlayerData then c = c + 1 end
        end
    end
    return c
end

---يقفل كل نقاط البيع داخل الزون (war_disabled = 1)
local function lockTradePointsInZone(zoneId)
    for _, p in pairs(TradePointsCache) do
        if p.zone_id == zoneId then
            p.war_disabled = 1
            MySQL.update('UPDATE family_trade_points SET war_disabled = 1 WHERE id = ?', { p.id })
        end
    end
end

local function unlockTradePointsInZone(zoneId)
    for _, p in pairs(TradePointsCache) do
        if p.zone_id == zoneId then
            p.war_disabled = 0
            MySQL.update('UPDATE family_trade_points SET war_disabled = 0 WHERE id = ?', { p.id })
        end
    end
end

local function broadcastWarUpdate(war)
    TriggerClientEvent('qbx_families:client:warUpdate', -1, {
        id = war.id,
        attacker = war.attacker_gang_id,
        defender = war.defender_gang_id,
        zone = war.zone_id,
        status = war.status,
        starts_at = war.starts_at,
        ends_at = war.ends_at,
        scores = war.scores,
    })
    -- v0.6.0: لو الحرب active لأول مرة ولم نُرسل blip بعد
    if war.status == 'active' and not war._blip_sent then
        war._blip_sent = true
        local zone = ZonesCache[war.zone_id]
        if zone then
            TriggerClientEvent('esx_families:client:warStarted', -1, war.id, {
                center_x = zone.center_x, center_y = zone.center_y,
                center_z = zone.center_z, radius = zone.radius,
                name = zone.name,
            })
        end
    end
end

local function broadcastWarEnded(war, winnerId, reason)
    TriggerClientEvent('qbx_families:client:warEnded', -1, {
        id = war.id, winner = winnerId, reason = reason, zone = war.zone_id,
    })
    -- v0.6.0: تقرير نهائي + إخفاء blip
    if BuildWarReport then BuildWarReport(war, winnerId) end
end

-- ============================================================
-- إصدار الحرب (declare)
-- ============================================================
---@param src number
---@param zoneId number
---@return boolean ok, string msg
function DeclareWar(src, zoneId)
    local cid = GetCitizenId(src); if not cid then return false, 'لا يوجد لاعب' end
    local attackerGangId = GetPlayerGang(cid)
    if not attackerGangId then return false, 'لست عضواً في عصابة' end

    -- يجب أن يكون قائد العصابة (Boss فقط — رتبة 1)
    local rank = GetPlayerRank(cid)
    local gang = GangsCache[attackerGangId]
    local isLeader = (gang and gang.leader_citizenid == cid) or (rank and rank.rank_order == 1 and rank.tier == 1)
    if not isLeader then return false, 'القائد فقط يقدر يعلن الحرب' end

    local zone = ZonesCache[zoneId]
    if not zone then return false, 'الزون غير موجود' end
    if zone.gang_id == attackerGangId then return false, 'لا تقدر تهاجم زونك' end

    local defenderGangId = zone.gang_id
    local defenderGang = GangsCache[defenderGangId]
    if not defenderGang then return false, 'العصابة المدافعة غير موجودة' end

    -- الزون مقفل في حرب نشطة؟
    if ZoneActiveWar[zoneId] then return false, 'هذا الزون في حرب نشطة بالفعل' end

    -- العصابة المهاجمة عندها حرب نشطة؟
    if GangActiveWar[attackerGangId] then return false, 'عصابتك في حرب نشطة بالفعل' end
    if GangActiveWar[defenderGangId] then return false, 'العصابة المدافعة في حرب نشطة' end

    -- Coward status?
    if gang.coward_until and gang.coward_until ~= '' then
        local cw = MySQL.scalar.await('SELECT UNIX_TIMESTAMP(coward_until) FROM family_gangs WHERE id = ?', { attackerGangId })
        if cw and cw > now() then
            return false, ('عصابتك في حالة Coward حتى %s'):format(os.date('%Y-%m-%d %H:%M', cw))
        end
    end

    local cfg = GetWarConfig()

    -- حد أدنى للأعضاء أونلاين
    if cfg.min_members > 0 then
        if countOnlineGangMembers(attackerGangId) < cfg.min_members then
            return false, ('تحتاج %d أعضاء أونلاين'):format(cfg.min_members)
        end
        if countOnlineGangMembers(defenderGangId) < cfg.min_members then
            return false, ('العصابة المدافعة تحتاج %d أعضاء أونلاين'):format(cfg.min_members)
        end
    end

    -- Cooldown آخر حرب (zone+gang pair)
    if cfg.cooldown_hours > 0 then
        local lastEnd = MySQL.scalar.await([[
            SELECT UNIX_TIMESTAMP(ends_at) FROM family_wars
            WHERE zone_id = ? AND attacker_gang_id = ? AND status IN ('ended','forfeited','surrendered')
            ORDER BY id DESC LIMIT 1
        ]], { zoneId, attackerGangId })
        if lastEnd and (now() - lastEnd) < (cfg.cooldown_hours * 3600) then
            local rem = cfg.cooldown_hours * 3600 - (now() - lastEnd)
            return false, ('Cooldown: انتظر %d ساعة'):format(math.ceil(rem / 3600))
        end
    end

    -- خصم تكلفة الحرب من خزنة المهاجم
    local atkVault = VaultsCache[attackerGangId]
    if not atkVault then return false, 'لا توجد خزنة لعصابتك' end
    if cfg.cost > 0 and (atkVault.money or 0) < cfg.cost then
        return false, ('تحتاج %s في خزنتك'):format(Shared.FormatMoney(cfg.cost))
    end

    -- ابدأ الإجراءات الذرية
    local startsAt = now() + (cfg.prep_minutes * 60)
    local endsAt   = startsAt + (cfg.duration_minutes * 60)

    local warId = MySQL.insert.await([[
        INSERT INTO family_wars
        (attacker_gang_id, defender_gang_id, zone_id, status,
         starts_at, ends_at, cost_paid, loot_percent, is_test_mode)
        VALUES (?, ?, ?, 'preparing', FROM_UNIXTIME(?), FROM_UNIXTIME(?), ?, ?, ?)
    ]], { attackerGangId, defenderGangId, zoneId, startsAt, endsAt, cfg.cost, cfg.loot_percent,
          cfg.is_test_mode and 1 or 0 })

    if not warId then return false, 'فشل إنشاء الحرب' end

    -- خصم التكلفة (atomic — مباشر مو batch)
    if cfg.cost > 0 then
        atkVault.money = atkVault.money - cfg.cost
        MySQL.update.await('UPDATE family_vaults SET money = ? WHERE id = ?', { atkVault.money, atkVault.id })
        LogVaultAction(atkVault.id, cid, 'war_cost', nil, cfg.cost, ('war #'..warId))
    end

    -- snapshot خزنة المدافع + قفل الخزنتين
    SnapshotVault(defenderGangId)
    LockVault(attackerGangId)
    LockVault(defenderGangId)

    -- snapshot الأعضاء (لمنع gang-switching exploit)
    local atkMembers, defMembers = {}, {}
    for c, m in pairs(MembersCache) do
        if m.gang_id == attackerGangId then atkMembers[#atkMembers+1] = c
        elseif m.gang_id == defenderGangId then defMembers[#defMembers+1] = c end
    end
    -- إدراج بـ batch (single transaction)
    if #atkMembers + #defMembers > 0 then
        local placeholders, values = {}, {}
        for _, c in ipairs(atkMembers) do
            placeholders[#placeholders+1] = '(?,?,?)'
            values[#values+1] = warId; values[#values+1] = c; values[#values+1] = attackerGangId
        end
        for _, c in ipairs(defMembers) do
            placeholders[#placeholders+1] = '(?,?,?)'
            values[#values+1] = warId; values[#values+1] = c; values[#values+1] = defenderGangId
        end
        MySQL.query.await(
            'INSERT INTO family_war_participants (war_id, citizenid, gang_id) VALUES '..table.concat(placeholders, ','),
            values
        )
    end

    -- init scores rows
    MySQL.query.await(
        'INSERT INTO family_war_scores (war_id, gang_id) VALUES (?,?), (?,?)',
        { warId, attackerGangId, warId, defenderGangId }
    )

    -- قفل نقاط البيع داخل الزون
    lockTradePointsInZone(zoneId)

    -- بناء الكاش
    local war = {
        id = warId, attacker_gang_id = attackerGangId, defender_gang_id = defenderGangId,
        zone_id = zoneId, status = 'preparing', starts_at = startsAt, ends_at = endsAt,
        cost_paid = cfg.cost, loot_percent = cfg.loot_percent, is_test_mode = cfg.is_test_mode,
        scores = { [attackerGangId] = 0, [defenderGangId] = 0 },
        kills  = { [attackerGangId] = 0, [defenderGangId] = 0 },
        deaths = { [attackerGangId] = 0, [defenderGangId] = 0 },
        presence_minutes = { [attackerGangId] = 0, [defenderGangId] = 0 },
        participants = {},
        pending_score_writes = {},
    }
    for _, c in ipairs(atkMembers) do war.participants[c] = attackerGangId end
    for _, c in ipairs(defMembers) do war.participants[c] = defenderGangId end

    ActiveWars[warId] = war
    ZoneActiveWar[zoneId] = warId
    GangActiveWar[attackerGangId] = warId
    GangActiveWar[defenderGangId] = warId

    LogWarEvent(warId, 'declared', cid, attackerGangId, nil, defenderGangId, 0,
        { zone = zone.name, cost = cfg.cost, prep = cfg.prep_minutes })

    -- إشعارات
    TriggerClientEvent('ox_lib:notify', -1, {
        type = 'warning',
        title = '⚔️ إعلان حرب',
        description = ('%s تعلن الحرب على %s — زون %s | تبدأ بعد %d دقيقة'):format(
            gang.label, defenderGang.label, zone.name, cfg.prep_minutes),
        duration = 12000,
    })

    broadcastWarUpdate(war)
    if _G.PushWarHudNow then _G.PushWarHudNow(war) end -- v0.7.11 instant push
    EnsureWarTickThread()
    return true, ('تم إعلان الحرب — تبدأ بعد %d دقيقة'):format(cfg.prep_minutes)
end

-- ============================================================
-- Forfeit (إذا المهاجم ما حضر بعد بدء الحرب)
-- ============================================================
local function forfeitWar(war)
    war.status = 'forfeited'
    MySQL.update('UPDATE family_wars SET status = ?, winner_gang_id = ?, end_reason = ? WHERE id = ?',
        { 'forfeited', war.defender_gang_id, 'attacker_no_show', war.id })

    -- استرجاع التكلفة؟ لا — تذهب للمدافع
    local atkVault = VaultsCache[war.attacker_gang_id]
    local defVault = VaultsCache[war.defender_gang_id]
    if atkVault and defVault and war.cost_paid > 0 then
        -- التكلفة كانت بالفعل خُصمت → نرسلها للمدافع
        defVault.money = (defVault.money or 0) + war.cost_paid
        MySQL.update.await('UPDATE family_vaults SET money = ? WHERE id = ?', { defVault.money, defVault.id })
        LogVaultAction(defVault.id, nil, 'war_forfeit_gain', nil, war.cost_paid, ('war #'..war.id))
    end

    -- Coward status للمهاجم
    local days = GetAdminConfigNumber('coward_duration_days', 7)
    MySQL.update('UPDATE family_gangs SET coward_until = DATE_ADD(NOW(), INTERVAL ? DAY) WHERE id = ?',
        { days, war.attacker_gang_id })

    EndWar(war.id, war.defender_gang_id, 'attacker_no_show')
end

-- ============================================================
-- Surrender
-- ============================================================
function SurrenderWar(src, warId)
    local war = ActiveWars[warId]
    if not war then return false, 'الحرب غير موجودة' end
    local cid = GetCitizenId(src)
    local myGang = GetPlayerGang(cid)
    local gang = GangsCache[myGang]
    if not gang or gang.leader_citizenid ~= cid then return false, 'القائد فقط' end
    if myGang ~= war.attacker_gang_id and myGang ~= war.defender_gang_id then return false, 'لست في الحرب' end
    if war.status ~= 'active' and war.status ~= 'overtime' and war.status ~= 'preparing' then
        return false, 'لا يمكن الاستسلام الآن'
    end

    local winner = (myGang == war.attacker_gang_id) and war.defender_gang_id or war.attacker_gang_id

    -- لووت 50% (أعلى من العادي)
    local cfg = GetWarConfig()
    local lootPct = cfg.surrender_loot_percent or 50
    local loserVault = VaultsCache[myGang]
    if loserVault then
        local snap = loserVault.war_snapshot or loserVault.money
        local lootAmount = math.floor(snap * lootPct / 100)
        TransferVaultMoney(myGang, winner, lootAmount)
    end

    war.status = 'surrendered'
    EndWar(warId, winner, 'surrendered')
    return true, 'تم الاستسلام'
end

-- ============================================================
-- إنهاء الحرب
-- ============================================================
function EndWar(warId, winnerId, reason)
    local war = ActiveWars[warId]
    if not war then
        -- نظف من DB فقط
        MySQL.update('UPDATE family_wars SET status = ?, winner_gang_id = ?, end_reason = ? WHERE id = ?',
            { reason or 'ended', winnerId, reason, warId })
        return
    end

    -- flush pending scores
    FlushWarScores(war)

    -- نقل اللووت لو ما تنقل أصلاً (winner determined by score for normal end)
    if reason == 'time_up' or reason == 'score_max' then
        local loser = (winnerId == war.attacker_gang_id) and war.defender_gang_id or war.attacker_gang_id
        local loserVault = VaultsCache[loser]
        if loserVault then
            local snap = loserVault.war_snapshot or loserVault.money or 0
            local lootAmount = math.floor(snap * (war.loot_percent or 30) / 100)
            if lootAmount > 0 then
                TransferVaultMoney(loser, winnerId, lootAmount)
            end
        end
    end

    -- نقل ملكية الزون لو المهاجم فاز
    if winnerId == war.attacker_gang_id then
        local zone = ZonesCache[war.zone_id]
        if zone then
            zone.gang_id = winnerId
            MySQL.update('UPDATE family_zones SET gang_id = ? WHERE id = ?', { winnerId, war.zone_id })
            -- نقل ملكية نقاط البيع المرتبطة
            for _, p in pairs(TradePointsCache) do
                if p.zone_id == war.zone_id then
                    p.created_by_gang_id = winnerId
                    MySQL.update('UPDATE family_trade_points SET created_by_gang_id = ? WHERE id = ?',
                        { winnerId, p.id })
                end
            end
        end
    end

    -- فك القفل
    UnlockVault(war.attacker_gang_id)
    UnlockVault(war.defender_gang_id)
    ClearVaultSnapshot(war.defender_gang_id)
    ClearVaultSnapshot(war.attacker_gang_id)
    unlockTradePointsInZone(war.zone_id)

    -- Update DB
    local duration = math.floor((now() - (war.starts_at or now())) / 60)
    MySQL.update('UPDATE family_wars SET status = ?, winner_gang_id = ?, end_reason = ? WHERE id = ?',
        { war.status ~= 'preparing' and war.status or 'ended', winnerId, reason, warId })

    -- History row (للقائمة الخفيفة)
    local atkLabel = (GangsCache[war.attacker_gang_id] or {}).label or '?'
    local defLabel = (GangsCache[war.defender_gang_id] or {}).label or '?'
    local zoneName = (ZonesCache[war.zone_id] or {}).name or '?'
    local winnerLabel = (GangsCache[winnerId] or {}).label or '?'
    MySQL.insert([[
        INSERT INTO family_war_history
        (war_id, attacker_label, defender_label, zone_name, winner_label, end_reason,
         attacker_score, defender_score, total_kills, loot_amount, duration_minutes)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)
    ]], {
        warId, atkLabel, defLabel, zoneName, winnerLabel, reason,
        war.scores[war.attacker_gang_id] or 0,
        war.scores[war.defender_gang_id] or 0,
        (war.kills[war.attacker_gang_id] or 0) + (war.kills[war.defender_gang_id] or 0),
        0, duration,
    })

    -- Sync zones
    SyncZonesToAll()
    SyncTradePointsToAll()

    -- إشعار عام
    TriggerClientEvent('ox_lib:notify', -1, {
        type = 'success',
        title = '🏆 انتهت الحرب',
        description = ('الفائز: %s — السبب: %s'):format(winnerLabel, reason),
        duration = 10000,
    })

    broadcastWarEnded(war, winnerId, reason)

    -- نظف الكاش
    ZoneActiveWar[war.zone_id] = nil
    GangActiveWar[war.attacker_gang_id] = nil
    GangActiveWar[war.defender_gang_id] = nil
    ActiveWars[warId] = nil
end

-- ============================================================
-- Score Events (kill / boss kill / death / presence)
-- ============================================================
function FlushWarScores(war)
    if not war then return end
    for gid in pairs(war.pending_score_writes or {}) do
        MySQL.update('UPDATE family_war_scores SET score = ?, kills = ?, deaths = ?, presence_minutes = ? WHERE war_id = ? AND gang_id = ?',
            { war.scores[gid] or 0, war.kills[gid] or 0, war.deaths[gid] or 0,
              war.presence_minutes[gid] or 0, war.id, gid })
    end
    war.pending_score_writes = {}
end

function LogWarEvent(warId, eventType, cid, gid, targetCid, targetGid, scoreDelta, metadata)
    MySQL.insert(
        'INSERT INTO family_war_events (war_id, event_type, citizenid, gang_id, target_citizenid, target_gang_id, score_delta, metadata) VALUES (?,?,?,?,?,?,?,?)',
        { warId, eventType, cid, gid, targetCid, targetGid, scoreDelta or 0,
          metadata and json.encode(metadata) or nil }
    )
end

-- v0.7.0a-dynamic-participants
-- يحدد لو cid مشارك في حرب — مع fallback ديناميكي على gang الحالي
local function getWarFor(cid)
    for warId, war in pairs(ActiveWars) do
        if war.status == 'active' or war.status == 'overtime' then
            local gid = war.participants[cid]
            if gid then return war, gid end
            -- Fallback: لو مو في snapshot، نفحص gang الحالي
            local curGang = GetPlayerGang(cid)
            if curGang and (curGang == war.attacker_gang_id or curGang == war.defender_gang_id) then
                war.participants[cid] = curGang  -- نضيفه ديناميكي
                if Config.Debug and Config.Debug.warKills then
                    print(('[wars][dyn-add] cid=%s gang=%s warId=%s'):format(cid, curGang, warId))
                end
                return war, curGang
            end
        end
    end
end


-- Player kill event (client/baseevents -> server)
-- v0.7.4: Central scorer. لا يعتمد على CurrentZone في الكلاينت ولا على snapshot المشاركين فقط.
local WAR_KILL_DEBUG = true

local function warKillLog(msg)
    if WAR_KILL_DEBUG then
        print(('^3[esx_families:war-kill]^7 %s'):format(msg))
    end
end

local function zoneCenter(zone)
    if not zone then return nil end
    local x = zone.center_x or zone.x or zone.coords_x
    local y = zone.center_y or zone.y or zone.coords_y
    local z = zone.center_z or zone.z or zone.coords_z or 0.0
    if not x or not y then return nil end
    return tonumber(x), tonumber(y), tonumber(z)
end

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function dist2d(c, x, y)
    if not c or not x or not y then return 999999.0 end
    local dx, dy = (c.x - x), (c.y - y)
    return math.sqrt((dx * dx) + (dy * dy))
end

local function resolveWarSide(war, cid)
    if not war or not cid then return nil end
    war.participants = war.participants or {}
    local cached = war.participants[cid]
    if cached then return cached end

    -- أهم إصلاح: لو snapshot المشاركين ناقص، نحل الطرف من عضوية اللاعب الحالية.
    local gid = GetPlayerGang(cid)
    if gid == war.attacker_gang_id or gid == war.defender_gang_id then
        war.participants[cid] = gid
        warKillLog(('added missing participant cid=%s gang=%s war=%s'):format(cid, gid, war.id))
        return gid
    end
    return nil
end

local function activateWarIfReady(war)
    if not war then return false end
    if war.status == 'active' or war.status == 'overtime' then return true end
    if war.status == 'preparing' and (war.starts_at or 0) <= now() then
        war.status = 'active'
        MySQL.update('UPDATE family_wars SET status = ? WHERE id = ?', { 'active', war.id })
        warKillLog(('auto-activated war=%s from kill path'):format(war.id))
        broadcastWarUpdate(war)
        if _G.PushWarHudNow then _G.PushWarHudNow(war) end -- v0.7.11 instant push
        return true
    end
    return false
end

local function getWarForKill(killerCid, victimCid)
    for _, war in pairs(ActiveWars) do
        if activateWarIfReady(war) then
            local killerGid = resolveWarSide(war, killerCid)
            local victimGid = resolveWarSide(war, victimCid)
            if killerGid and victimGid and killerGid ~= victimGid then
                return war, killerGid, victimGid
            end
        end
    end
    return nil
end

local function insideWarZone(war, killerSrc, victimSrc)
    local zone = ZonesCache[war.zone_id]
    if not zone then
        warKillLog(('war=%s rejected: zone cache missing zone_id=%s'):format(war.id, tostring(war.zone_id)))
        return false
    end

    local zx, zy = zoneCenter(zone)
    if not zx or not zy then
        warKillLog(('war=%s rejected: zone center missing'):format(war.id))
        return false
    end

    local radius = tonumber(zone.radius or 0) or 0
    local extra = (Config.War and Config.War.killConfirmRadius) or 50.0
    local maxDist = radius + extra
    local kc = pedCoords(killerSrc)
    local vc = pedCoords(victimSrc)
    local kd = dist2d(kc, zx, zy)
    local vd = dist2d(vc, zx, zy)

    -- نكتفي بأن القاتل أو الضحية داخل نطاق الزون الموسع لأن dead ped أحياناً يتأخر تحديث إحداثياته.
    if kd <= maxDist or vd <= maxDist then return true end

    warKillLog(('war=%s rejected: out of zone killerDist=%.1f victimDist=%.1f max=%.1f'):format(war.id, kd, vd, maxDist))
    return false
end

function ProcessFamilyWarKill(killerSrc, victimSrc, sourceTag, opts)
    opts = opts or {}
    killerSrc = tonumber(killerSrc)
    victimSrc = tonumber(victimSrc)
    sourceTag = sourceTag or 'unknown'

    if not killerSrc or not victimSrc or killerSrc <= 0 or victimSrc <= 0 or killerSrc == victimSrc then
        warKillLog(('ignored invalid src killer=%s victim=%s source=%s'):format(tostring(killerSrc), tostring(victimSrc), sourceTag))
        return false
    end
    if GetPlayerName(killerSrc) == nil or GetPlayerName(victimSrc) == nil then
        warKillLog(('ignored player offline killer=%s victim=%s source=%s'):format(killerSrc, victimSrc, sourceTag))
        return false
    end

    local nowMs = GetGameTimer()
    if not opts.bypassThrottle and (LastKillEventAt[killerSrc] or 0) + (Config.Performance.killEventThrottle or 1000) > nowMs then
        warKillLog(('ignored throttled killer=%s victim=%s source=%s'):format(killerSrc, victimSrc, sourceTag))
        return false
    end
    LastKillEventAt[killerSrc] = nowMs

    local killerCid = GetCitizenId(killerSrc)
    local victimCid = GetCitizenId(victimSrc)
    if not killerCid or not victimCid then
        warKillLog(('ignored missing cid killer=%s victim=%s source=%s'):format(tostring(killerCid), tostring(victimCid), sourceTag))
        return false
    end

    local war, killerGid, victimGid = getWarForKill(killerCid, victimCid)
    if not war then
        warKillLog(('ignored no active war killerCid=%s victimCid=%s source=%s'):format(killerCid, victimCid, sourceTag))
        return false
    end

    if not insideWarZone(war, killerSrc, victimSrc) then return false end

    VictimKillCooldown = VictimKillCooldown or {}
    local cdSec = (Config.War and Config.War.victimCooldownSec) or 30
    local lastDeath = VictimKillCooldown[victimCid] or 0
    if not opts.bypassCooldown and (os.time() - lastDeath) < cdSec then
        warKillLog(('ignored victim cooldown victimCid=%s remaining=%ss'):format(victimCid, cdSec - (os.time() - lastDeath)))
        return false
    end
    VictimKillCooldown[victimCid] = os.time()

    local victimGang = GangsCache[victimGid]
    local isBossKill = victimGang and victimGang.leader_citizenid == victimCid
    local victimMember = MembersCache and MembersCache[victimCid] or nil
    local victimRank = nil
    if victimMember and victimMember.rank_id and RanksCache then
        victimRank = RanksCache[victimMember.rank_id]
        if not victimRank and victimMember.gang_id and RanksCache[victimMember.gang_id] then
            victimRank = RanksCache[victimMember.gang_id][victimMember.rank_id]
        end
    end

    local scorePts
    if isBossKill then
        scorePts = (Config.War and Config.War.points and Config.War.points.boss) or 5
    elseif victimRank and victimRank.tier == 2 then
        scorePts = (Config.War and Config.War.points and Config.War.points.underboss) or 3
    elseif victimRank and victimRank.tier == 1 then
        scorePts = (Config.War and Config.War.points and Config.War.points.boss) or 5
    else
        scorePts = (Config.War and Config.War.points and Config.War.points.member) or 1
    end
    if scorePts < 0 then scorePts = 0 end  -- v0.7.10: يمنع أي نقاط سالبة
    local deathPts = 0  -- v0.7.10: النقاط زيادة فقط، الضحية لا تخسر

    war.scores = war.scores or {}
    war.kills = war.kills or {}
    war.deaths = war.deaths or {}
    war.pending_score_writes = war.pending_score_writes or {}

    war.scores[killerGid] = (war.scores[killerGid] or 0) + scorePts
    -- v0.7.10 disabled: war.scores[victimGid] لم تعد تتأثر
    war.kills[killerGid]  = (war.kills[killerGid] or 0) + 1
    war.deaths[victimGid] = (war.deaths[victimGid] or 0) + 1
    war.pending_score_writes[killerGid] = true
    war.pending_score_writes[victimGid] = true

    LogWarEvent(war.id, isBossKill and 'boss_kill' or 'kill', killerCid, killerGid, victimCid, victimGid, scorePts, { source = sourceTag })

    local kp = ESXBridge.GetPlayer(killerSrc)
    local vp = ESXBridge.GetPlayer(victimSrc)
    local kn = (kp and kp.PlayerData and kp.PlayerData.charinfo and ((kp.PlayerData.charinfo.firstname or '')..' '..(kp.PlayerData.charinfo.lastname or ''))) or GetPlayerName(killerSrc) or 'لاعب'
    local vn = (vp and vp.PlayerData and vp.PlayerData.charinfo and ((vp.PlayerData.charinfo.firstname or '')..' '..(vp.PlayerData.charinfo.lastname or ''))) or GetPlayerName(victimSrc) or 'لاعب'

    TriggerClientEvent('esx_families:client:warKillfeed', -1, {
        killer = kn, victim = vn,
        killerGang = (GangsCache[killerGid] or {}).label or '?',
        victimGang = (GangsCache[victimGid] or {}).label or '?',
        points = scorePts,
    })

    FlushWarScores(war)
    broadcastWarUpdate(war)
    if _G.PushWarHudNow then _G.PushWarHudNow(war) end -- v0.7.11 instant push
    warKillLog(('COUNTED war=%s %s(%s) -> %s(%s) +%s source=%s score=%s:%s'):format(
        war.id, killerCid, killerGid, victimCid, victimGid, scorePts, sourceTag,
        tostring(war.scores[war.attacker_gang_id] or 0), tostring(war.scores[war.defender_gang_id] or 0)
    ))
    return true
end

RegisterNetEvent('qbx_families:server:reportKill', function(killerSrc, victimSrc, sourceTag)
    local actualSrc = source
    if tonumber(killerSrc) ~= actualSrc then
        warKillLog(('ignored spoof report source=%s killerArg=%s victim=%s'):format(actualSrc, tostring(killerSrc), tostring(victimSrc)))
        return
    end
    ProcessFamilyWarKill(actualSrc, victimSrc, sourceTag or 'client-attacker')
end)

RegisterNetEvent('qbx_families:server:reportKillByVictim', function(killerSrc, weaponHash)
    local victimSrc = source
    ProcessFamilyWarKill(killerSrc, victimSrc, 'client-victim')
end)

-- لو baseevents يرسل للسيرفر مباشرة، نحسبه أيضاً.
RegisterNetEvent('baseevents:onPlayerKilled', function(killerSrc, data)
    local victimSrc = source
    ProcessFamilyWarKill(killerSrc, victimSrc, 'baseevents-server')
end)

-- اختبار يدوي من الكونسل/الأدمن: /familywar_testkill killerId victimId
RegisterCommand('familywar_testkill', function(src, args)
    if src ~= 0 and not IsAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='ليس لديك صلاحية' })
        return
    end
    local killer = tonumber(args[1])
    local victim = tonumber(args[2])
    if not killer or not victim then
        print('Usage: familywar_testkill <killerServerId> <victimServerId>')
        return
    end
    local ok = ProcessFamilyWarKill(killer, victim, 'manual-test', { bypassThrottle = true, bypassCooldown = true })
    print(('[esx_families] familywar_testkill result=%s killer=%s victim=%s'):format(tostring(ok), killer, victim))
end, false)


-- ============================================================
-- War Tick Thread — يعمل فقط لو فيه حروب نشطة
-- ============================================================
local TickRunning = false
function EnsureWarTickThread()
    if TickRunning then return end
    if not next(ActiveWars) then return end
    TickRunning = true

    CreateThread(function()
        while next(ActiveWars) do
            Wait(5000)  -- كل 5 ثوانٍ — خفيف جداً
            local t = now()

            for warId, war in pairs(ActiveWars) do
                -- preparing → active
                if war.status == 'preparing' and t >= war.starts_at then
                    -- v0.7.1: فحص حضور الطرفين + online المدافع
                    local zone = ZonesCache[war.zone_id]
                    local attackerPresent, defenderPresent = false, false
                    local defenderOnline = 0
                    if zone then
                        for cid, gid in pairs(war.participants) do
                            local pl = ESXBridge.GetPlayerByCitizenId(cid)
                            if pl and pl.PlayerData then
                                if gid == war.defender_gang_id then defenderOnline = defenderOnline + 1 end
                                local src = pl.PlayerData.source
                                local pc = GetEntityCoords(GetPlayerPed(src))
                                local inZone = #(vector2(pc.x, pc.y) - vector2(zone.center_x, zone.center_y)) <= zone.radius
                                if inZone then
                                    if gid == war.attacker_gang_id then attackerPresent = true end
                                    if gid == war.defender_gang_id then defenderPresent = true end
                                end
                            end
                        end
                    end

                    local cfg = GetWarConfig()
                    local forfeitWindow = (cfg.forfeit_minutes or 3) * 60
                    local elapsed = t - war.starts_at
                    print(('[WAR-TICK v0.7.1] warId=%s atkPresent=%s defPresent=%s defOnline=%d elapsed=%ds window=%ds')
                        :format(tostring(warId), tostring(attackerPresent), tostring(defenderPresent), defenderOnline, elapsed, forfeitWindow))

                    if defenderOnline == 0 and elapsed > forfeitWindow then
                        local atkVault = VaultsCache[war.attacker_gang_id]
                        if atkVault and war.cost_paid and war.cost_paid > 0 and not war.cost_paid_transferred then
                            atkVault.money = (atkVault.money or 0) + war.cost_paid
                            MySQL.update.await('UPDATE family_vaults SET money = ? WHERE id = ?', { atkVault.money, atkVault.id })
                            LogVaultAction(atkVault.id, nil, 'war_cancel_refund', nil, war.cost_paid, ('war #'..war.id..' no_defender_online'))
                            war.cost_paid_transferred = true
                        end
                        war.status = 'cancelled'
                        MySQL.update('UPDATE family_wars SET status=?, end_reason=? WHERE id=?',
                            { 'cancelled', 'cancelled_no_defender', war.id })
                        TriggerClientEvent('ox_lib:notify', -1, {
                            type = 'inform', title = '⚠️ أُلغيت الحرب',
                            description = 'لا يوجد أعضاء أونلاين من المدافع — استُرجعت التكلفة كاملة',
                            duration = 9000,
                        })
                        EndWar(war.id, nil, 'cancelled_no_defender')

                    elseif not attackerPresent and not defenderPresent and elapsed > forfeitWindow then
                        local atkVault = VaultsCache[war.attacker_gang_id]
                        if atkVault and war.cost_paid and war.cost_paid > 0 and not war.cost_paid_transferred then
                            local refund = math.floor(war.cost_paid * 0.5)
                            atkVault.money = (atkVault.money or 0) + refund
                            MySQL.update.await('UPDATE family_vaults SET money = ? WHERE id = ?', { atkVault.money, atkVault.id })
                            LogVaultAction(atkVault.id, nil, 'war_cancel_partial_refund', nil, refund, ('war #'..war.id..' both_absent'))
                            war.cost_paid_transferred = true
                        end
                        war.status = 'cancelled'
                        MySQL.update('UPDATE family_wars SET status=?, end_reason=? WHERE id=?',
                            { 'cancelled', 'both_absent', war.id })
                        TriggerClientEvent('ox_lib:notify', -1, {
                            type = 'inform', title = '⚠️ أُلغيت الحرب',
                            description = 'كلا الطرفين غائب — استُرجع 50% من التكلفة',
                            duration = 9000,
                        })
                        EndWar(war.id, nil, 'both_absent')

                    elseif not attackerPresent and elapsed > forfeitWindow then
                        forfeitWar(war)

                    elseif attackerPresent then
                        war.status = 'active'
                        MySQL.update('UPDATE family_wars SET status = ? WHERE id = ?', { 'active', warId })
                        TriggerClientEvent('ox_lib:notify', -1, {
                            type = 'inform', title = '⚔️ بدأت الحرب',
                            description = ('حرب على %s'):format((zone or {}).name or '?'),
                            duration = 8000,
                        })
                        broadcastWarUpdate(war)
                        if _G.PushWarHudNow then _G.PushWarHudNow(war) end -- v0.7.11 instant push
                    end
                end

                -- active → check timeout
                if war.status == 'active' and t >= war.ends_at then
                    -- لو متعادلين → overtime
                    local s1 = war.scores[war.attacker_gang_id] or 0
                    local s2 = war.scores[war.defender_gang_id] or 0
                    if s1 == s2 then
                        local cfg = GetWarConfig()
                        war.status = 'overtime'
                        war.ends_at = t + ((cfg.overtime_minutes or 10) * 60)
                        MySQL.update('UPDATE family_wars SET status = ?, ends_at = FROM_UNIXTIME(?) WHERE id = ?',
                            { 'overtime', war.ends_at, warId })
                        broadcastWarUpdate(war)
                        if _G.PushWarHudNow then _G.PushWarHudNow(war) end -- v0.7.11 instant push
                    else
                        local winner = s1 > s2 and war.attacker_gang_id or war.defender_gang_id
                        EndWar(warId, winner, 'time_up')
                    end
                end

                -- overtime → time up
                if war.status == 'overtime' and t >= war.ends_at then
                    local s1 = war.scores[war.attacker_gang_id] or 0
                    local s2 = war.scores[war.defender_gang_id] or 0
                    -- لو لسه متعادلين → المدافع يفوز (defender's advantage)
                    local winner = (s1 > s2) and war.attacker_gang_id or war.defender_gang_id
                    EndWar(warId, winner, s1 == s2 and 'overtime_defender_wins' or 'overtime_time_up')
                end

                -- presence ticks (كل دقيقة فعلياً — every 12 ticks of 5s)
                war._tickCounter = (war._tickCounter or 0) + 1
                if war.status == 'active' or war.status == 'overtime' then
                    if war._tickCounter % 12 == 0 then  -- كل ~60 ثانية
                        local zone = ZonesCache[war.zone_id]
                        if zone then
                            local pts = GetAdminConfigNumber('score_presence_per_minute', 2)
                            local presence = { [war.attacker_gang_id] = 0, [war.defender_gang_id] = 0 }
                            for cid, gid in pairs(war.participants) do
                                local p = ESXBridge.GetPlayerByCitizenId(cid)
                                if p and p.PlayerData then
                                    local src = p.PlayerData.source
                                    local pc = GetEntityCoords(GetPlayerPed(src))
                                    if #(vector2(pc.x, pc.y) - vector2(zone.center_x, zone.center_y)) <= zone.radius then
                                        presence[gid] = (presence[gid] or 0) + 1
                                    end
                                end
                            end
                            for gid, count in pairs(presence) do
                                if count > 0 then
                                    war.scores[gid] = (war.scores[gid] or 0) + pts
                                    war.presence_minutes[gid] = (war.presence_minutes[gid] or 0) + 1
                                    war.pending_score_writes[gid] = true
                                end
                            end
                            broadcastWarUpdate(war)
                            if _G.PushWarHudNow then _G.PushWarHudNow(war) end -- v0.7.11 instant push
                        end
                    end

                    -- flush كل ~30 ثانية
                    if war._tickCounter % 6 == 0 then
                        FlushWarScores(war)
                    end
                end
            end
        end
        TickRunning = false
    end)
end

-- ============================================================
-- Callbacks (NUI / Client interactions)
-- ============================================================

-- معلومات الحرب الحالية للاعب (للـ HUD)
lib.callback.register('qbx_families:server:getMyWar', function(source)
    local cid = GetCitizenId(source); if not cid then return nil end
    local gid = GetPlayerGang(cid)
    if not gid then return nil end
    local warId = GangActiveWar[gid]
    if not warId then return nil end
    local war = ActiveWars[warId]
    if not war then return nil end
    return {
        id = war.id, status = war.status,
        attacker = { id = war.attacker_gang_id, label = (GangsCache[war.attacker_gang_id] or {}).label,
                     score = war.scores[war.attacker_gang_id] or 0 },
        defender = { id = war.defender_gang_id, label = (GangsCache[war.defender_gang_id] or {}).label,
                     score = war.scores[war.defender_gang_id] or 0 },
        zone = (ZonesCache[war.zone_id] or {}).name,
        zone_id = war.zone_id,
        starts_at = war.starts_at, ends_at = war.ends_at,
        my_side = (gid == war.attacker_gang_id) and 'attacker' or 'defender',
    }
end)

-- War Council interactions
lib.callback.register('qbx_families:server:declareWar', function(source, zoneId)
    return DeclareWar(source, zoneId)
end)

lib.callback.register('qbx_families:server:surrenderWar', function(source, warId)
    return SurrenderWar(source, warId)
end)

-- قائمة الزونات اللي يقدر يهاجمها (مو زونات عصابته + مو في حرب)
lib.callback.register('qbx_families:server:getAttackableZones', function(source)
    local cid = GetCitizenId(source); if not cid then return {} end
    local myGang = GetPlayerGang(cid)
    if not myGang then return {} end
    local list = {}
    for id, z in pairs(ZonesCache) do
        if z.gang_id ~= myGang and not ZoneActiveWar[id] then
            list[#list+1] = {
                id = id, name = z.name,
                gang_id = z.gang_id,
                gang_label = (GangsCache[z.gang_id] or {}).label,
            }
        end
    end
    return list
end)

-- سجل آخر الحروب (للـ NUI history)
lib.callback.register('qbx_families:server:getWarHistory', function(source, limit)
    limit = math.min(tonumber(limit) or 20, 50)
    return MySQL.query.await(
        'SELECT * FROM family_war_history ORDER BY id DESC LIMIT ?', { limit }) or {}
end)

-- ============================================================
-- Cleanup (قديم حسب Config.War.cleanupOlderThanDays)
-- ============================================================
CreateThread(function()
    local interval = (Config.War.cleanupIntervalMinutes or 60) * 60 * 1000
    while true do
        Wait(interval)
        local days = Config.War.cleanupOlderThanDays or 30
        MySQL.query('DELETE FROM family_war_events WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)', { days })
        MySQL.query('DELETE FROM family_war_history WHERE ended_at < DATE_SUB(NOW(), INTERVAL ? DAY)', { days })
        MySQL.query('UPDATE family_gangs SET coward_until = NULL WHERE coward_until IS NOT NULL AND coward_until < NOW()')
        Shared.Debug('war cleanup ran')
    end
end)

-- ============================================================
-- Restart safety: ابسط نهج — الحروب active أثناء restart تُلغى
-- (cost paid يُسترجع للمهاجم)
-- ============================================================
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Wait(1500)  -- بعد كل caches
    local stuck = MySQL.query.await([[
        SELECT * FROM family_wars WHERE status IN ('preparing','active','overtime')
    ]]) or {}
    for _, w in ipairs(stuck) do
        MySQL.update('UPDATE family_wars SET status = ?, end_reason = ? WHERE id = ?',
            { 'cancelled', 'server_restart', w.id })
        -- استرجاع التكلفة
        local v = VaultsCache[w.attacker_gang_id]
        if v and (w.cost_paid or 0) > 0 then
            v.money = (v.money or 0) + w.cost_paid
            MySQL.update('UPDATE family_vaults SET money = ?, war_locked = 0 WHERE id = ?', { v.money, v.id })
        end
        -- فك القفل
        UnlockVault(w.attacker_gang_id)
        UnlockVault(w.defender_gang_id)
        ClearVaultSnapshot(w.defender_gang_id)
        unlockTradePointsInZone(w.zone_id)
    end
    if #stuck > 0 then
        print(('^3[qbx_families]^7 cancelled %d stuck wars on restart (refunded)'):format(#stuck))
    end
end)

-- ============================================================
-- Exports
-- ============================================================
exports('DeclareWar', DeclareWar)
exports('SurrenderWar', SurrenderWar)
exports('EndWar', EndWar)
exports('IsZoneInWar', function(zoneId) return ZoneActiveWar[zoneId] ~= nil end)
exports('IsGangInWar', function(gangId) return GangActiveWar[gangId] ~= nil end)


-- ═══ v0.7.7 KILL FIX (server receiver) ═══
RegisterNetEvent('esx_families:reportWarKill')
AddEventHandler('esx_families:reportWarKill', function(killerSrv, weapon)
    local victimSrc = source
    print(('^2[esx_families:KILLFIX-SRV]^7 victim=%s killer=%s weapon=%s')
        :format(victimSrc, tostring(killerSrv), tostring(weapon)))
    if not killerSrv or killerSrv <= 0 then
        print('^1[esx_families:KILLFIX-SRV]^7 invalid killerSrv, abort')
        return
    end
    if type(ProcessFamilyWarKill) == 'function' then
        local ok = ProcessFamilyWarKill(killerSrv, victimSrc, 'victim-report')
        print(('^3[esx_families:KILLFIX-SRV]^7 ProcessFamilyWarKill result=%s'):format(tostring(ok)))
    else
        print('^1[esx_families:KILLFIX-SRV]^7 ProcessFamilyWarKill not defined!')
    end
end)


-- ═══ v0.7.7 KILL FIX (server receiver) ═══
RegisterNetEvent('esx_families:reportWarKill')
AddEventHandler('esx_families:reportWarKill', function(killerSrv, weapon)
    local victimSrc = source
    print(('^2[esx_families:KILLFIX-SRV]^7 victim=%s killer=%s weapon=%s')
        :format(victimSrc, tostring(killerSrv), tostring(weapon)))
    if not killerSrv or killerSrv <= 0 then
        print('^1[esx_families:KILLFIX-SRV]^7 invalid killerSrv, abort')
        return
    end
    if type(ProcessFamilyWarKill) == 'function' then
        local ok = ProcessFamilyWarKill(killerSrv, victimSrc, 'victim-report')
        print(('^3[esx_families:KILLFIX-SRV]^7 ProcessFamilyWarKill result=%s'):format(tostring(ok)))
    else
        print('^1[esx_families:KILLFIX-SRV]^7 ProcessFamilyWarKill not defined!')
    end
end)


-- ============================================================
-- v0.7.0b — Server-side baseevents kill detector (Path B)
-- ============================================================
AddEventHandler('baseevents:onPlayerKilled', function(killerId, data)
    local victimSrc = source
    local killerSrc = tonumber(killerId)
    if not killerSrc or killerSrc <= 0 or killerSrc == victimSrc then return end

    local key = KE_dedupKey(killerSrc, victimSrc)
    if KE_isDup(key) then
        print(('[KillEngine][dup] killer=%s victim=%s — مُعالج مسبقاً'):format(killerSrc, victimSrc))
        return
    end

    print(('[KillEngine][PathB] baseevents kill: killer=%s victim=%s'):format(killerSrc, victimSrc))
    -- نمرّرها لنفس reportKill عبر trigger داخلي
    TriggerEvent('__qbx_families_internal:reportKill', killerSrc, victimSrc)
end)

-- internal handler يحاكي reportKill بدون التحقق من source
RegisterNetEvent('__qbx_families_internal:reportKill')
AddEventHandler('__qbx_families_internal:reportKill', function(killerSrc, victimSrc)
    local killerCid = GetCitizenId(killerSrc)
    local victimCid = GetCitizenId(victimSrc)
    if not killerCid then return KE_reject(killerSrc, victimSrc, 'killer cid nil (بدون login؟)') end
    if not victimCid then return KE_reject(killerSrc, victimSrc, 'victim cid nil') end

    local war, killerGid = getWarFor(killerCid)
    if not war then
        local kg = GetPlayerGang and GetPlayerGang(killerCid) or 'nil'
        return KE_reject(killerCid, victimCid, 'no active war for killer (gang='..tostring(kg)..')')
    end

    local victimGid = war.participants[victimCid]
    if not victimGid then
        local vg = GetPlayerGang and GetPlayerGang(victimCid) or nil
        if vg and (vg == war.attacker_gang_id or vg == war.defender_gang_id) then
            war.participants[victimCid] = vg
            victimGid = vg
            print(('[KillEngine][dyn-victim] cid=%s gang=%s'):format(victimCid, vg))
        end
    end
    if not victimGid then
        return KE_reject(killerCid, victimCid, 'victim ليس في أي طرف')
    end
    if victimGid == killerGid then
        return KE_reject(killerCid, victimCid, 'friendly fire gang='..tostring(killerGid))
    end

    -- zone check (إن وُجد)
    if war.zone_id and Config and Config.Zones then
        local zone
        for _, z in ipairs(Config.Zones or {}) do
            if z.id == war.zone_id then zone = z; break end
        end
        if zone and zone.center then
            local p = GetEntityCoords(GetPlayerPed(victimSrc))
            local d = #(vector3(p.x, p.y, p.z) - vector3(zone.center.x, zone.center.y, zone.center.z))
            local maxD = (zone.radius or 50.0) + ((Config.War and Config.War.killConfirmRadius) or 50.0)
            if d > maxD then
                return KE_reject(killerCid, victimCid, ('victim خارج الزون d=%.1f max=%.1f'):format(d, maxD))
            end
        end
    end

    -- احتساب النقطة
    local pts = (Config.War and Config.War.scorePerKill) or 1
    war.scores[killerGid] = (war.scores[killerGid] or 0) + pts
    war.kills[killerGid]  = (war.kills[killerGid] or 0) + 1
    if war.pending_score_writes then war.pending_score_writes[killerGid] = true end
    KE_accept(killerCid, victimCid, killerGid, pts)

    -- broadcast HUD update
    if BroadcastWarUpdate then
        BroadcastWarUpdate(war)
    elseif TriggerClientEvent then
        TriggerClientEvent('qbx_families:client:warUpdate', -1, war)
    end
end)

-- ============================================================
-- v0.7.0b — Diagnostic Command
-- ============================================================
RegisterCommand('familywar_diag', function(src)
    if src ~= 0 then return end  -- console only
    print('=========== [KillEngine DIAG] ===========')
    print('-- Active Wars --')
    local n = 0
    for id, w in pairs(ActiveWars or {}) do
        n = n + 1
        print((' war#%s status=%s att=%s def=%s zone=%s'):format(
            id, w.status or '?', w.attacker_gang_id or '?', w.defender_gang_id or '?', w.zone_id or '?'))
        print(('   scores: %s'):format(json.encode(w.scores or {})))
        print(('   participants (%d):'):format(#(w.participants or {}) > 0 and #w.participants or 0))
        for cid, gid in pairs(w.participants or {}) do
            print(('     cid=%s gang=%s'):format(cid, gid))
        end
    end
    if n == 0 then print(' (لا توجد حروب نشطة)') end

    print('-- Online Players + Gang --')
    for _, pid in ipairs(GetPlayers()) do
        local cid = GetCitizenId and GetCitizenId(tonumber(pid)) or '?'
        local gang = GetPlayerGang and cid ~= '?' and GetPlayerGang(cid) or 'nil'
        print(('  src=%s cid=%s gang=%s name=%s'):format(pid, cid, gang, GetPlayerName(pid) or '?'))
    end

    print('-- Last Accepted Kills --')
    if #KillEngine.accepts == 0 then print(' (none)') end
    for i, e in ipairs(KillEngine.accepts) do
        print(('  [%s] killer=%s victim=%s gang=%s +%s'):format(e.t, e.killer, e.victim, e.gang, e.pts))
    end

    print('-- Last Rejected Kills (السبب) --')
    if #KillEngine.rejects == 0 then print(' (none — ولا قتل وصل أصلاً!)') end
    for i, e in ipairs(KillEngine.rejects) do
        print(('  [%s] killer=%s victim=%s reason=%s'):format(e.t, e.killer, e.victim, e.reason))
    end
    print('=========================================')
end, true)

print('[wars] v0.7.0b War Kill Engine V2 loaded ✓ — استخدم: familywar_diag')

