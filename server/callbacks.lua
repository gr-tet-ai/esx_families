-- ============================================================
-- esx_families - Callbacks v0.4.0
-- نقطة الاتصال الموحّدة بين القوائم (client) والسيرفر
-- كل callback يفحص الصلاحيات بنفسه — لا نعتمد على client أبداً
-- ============================================================

-- ============================================================
-- Helpers محلية
-- ============================================================
local function isLeaderOf(cid, gangId)
    local g = GangsCache[gangId]
    return g and g.leader_citizenid == cid
end

local function isMyGangOrAdmin(src, gangId)
    if IsAdmin(src) then return true end
    local cid = GetCitizenId(src); if not cid then return false end
    return GetPlayerGang(cid) == gangId
end

-- ============================================================
-- 1) معلومات أساسية
-- ============================================================

lib.callback.register('qbx_families:server:isAdmin', function(source)
    return IsAdmin(source)
end)

lib.callback.register('qbx_families:server:getMyContext', function(source)
    -- يرجّع كل ما تحتاجه القائمة الرئيسية في استدعاء واحد (أداء)
    local cid = GetCitizenId(source)
    if not cid then return { isAdmin = false, canOpenF6 = false, canOpenF9 = false } end

    local admin = IsAdmin(source)
    local gangId = GetPlayerGang(cid)

    -- 🧭 F6-CONTEXT-HEAL v0.6.2: لا نعتمد على MembersCache فقط.
    -- إذا DB فيها عضوية والـ cache ضاع بعد restart/patch، نعيد بناء الكاش فور فتح F6.
    if not gangId then
        local row = MySQL.single.await([[
            SELECT id, gang_id, rank_id
            FROM family_members
            WHERE citizenid = ?
            LIMIT 1
        ]], { cid })
        if row and row.gang_id then
            MembersCache[cid] = { id = row.id, gang_id = row.gang_id, rank_id = row.rank_id }
            gangId = row.gang_id
            print(('^2[esx_families]^7 F6-CONTEXT-HEAL: restored DB member %s -> gang=%s rank=%s'):format(cid, tostring(row.gang_id), tostring(row.rank_id)))
        end
    end

    -- 🧭 F6-CONTEXT-HEAL v0.6.2: لو اللاعب قائد في family_gangs لكن ناقص من members، أصلحها من DB لا من التخمين.
    if not gangId then
        local grow = MySQL.single.await('SELECT * FROM family_gangs WHERE leader_citizenid = ? LIMIT 1', { cid })
        if grow and grow.id then
            GangsCache[grow.id] = GangsCache[grow.id] or grow
            local bossRankId = GangRanksIdx and GangRanksIdx[grow.id] and GangRanksIdx[grow.id][1]

            if not bossRankId then
                local r = MySQL.single.await('SELECT * FROM family_ranks WHERE gang_id = ? AND rank_order = 1 LIMIT 1', { grow.id })
                if r and r.id then
                    RanksCache[r.id] = r
                    GangRanksIdx[grow.id] = GangRanksIdx[grow.id] or {}
                    GangRanksIdx[grow.id][1] = r.id
                    bossRankId = r.id
                end
            end

            if not bossRankId and CreateDefaultRanksForGang then
                print(('^3[esx_families]^7 F6-CONTEXT-HEAL: gang %s has no boss rank; creating defaults'):format(tostring(grow.id)))
                CreateDefaultRanksForGang(grow.id, cid)
                bossRankId = GangRanksIdx and GangRanksIdx[grow.id] and GangRanksIdx[grow.id][1]
            end

            if bossRankId then
                MySQL.query.await([[
                    INSERT INTO family_members (gang_id, citizenid, rank_id, invited_by)
                    VALUES (?,?,?,?)
                    ON DUPLICATE KEY UPDATE
                        gang_id = VALUES(gang_id),
                        rank_id = VALUES(rank_id),
                        invited_by = VALUES(invited_by)
                ]], { grow.id, cid, bossRankId, 'f6_context_heal' })
                local mrow = MySQL.single.await('SELECT id, gang_id, rank_id FROM family_members WHERE citizenid = ? LIMIT 1', { cid })
                MembersCache[cid] = { id = mrow and mrow.id or nil, gang_id = grow.id, rank_id = bossRankId }
                gangId = grow.id
                print(('^2[esx_families]^7 F6-CONTEXT-HEAL: ensured leader %s -> gang=%s rank=%s'):format(cid, tostring(grow.id), tostring(bossRankId)))
            else
                print(('^1[esx_families]^7 F6-CONTEXT-HEAL FAILED: no boss rank for gang %s leader %s'):format(tostring(grow.id), cid))
            end
        end
    end

    -- 🩹 CACHE-HEAL v0.6.2-hotfix: لو DB فيه عضوية لكن الكاش ضايع بعد restart/patch
    if not gangId then
        local row = MySQL.single.await('SELECT id, gang_id, rank_id FROM family_members WHERE citizenid = ? LIMIT 1', { cid })
        if row and row.gang_id then
            MembersCache[cid] = { id = row.id, gang_id = row.gang_id, rank_id = row.rank_id }
            gangId = row.gang_id
            print(('^2[esx_families]^7 CACHE-HEAL: restored member %s -> gang %s rank %s'):format(cid, tostring(row.gang_id), tostring(row.rank_id)))
        end
    end

    -- 🩹 AUTO-HEAL v0.6.1: لو القائد ما هو في MembersCache، نضيفه تلقائياً
    -- (الجذر #1: لو الرتب الافتراضية ما اتعملت، نُنشئها أولاً ثم نُدرج القائد)
    if not gangId then
        for gid, g in pairs(GangsCache) do
            if g.leader_citizenid == cid then
                local bossRankId = GangRanksIdx and GangRanksIdx[gid] and GangRanksIdx[gid][1]
                -- v0.6.1: إذا ما في رتب، أنشئها الآن (الإصلاح الجوهري)
                if not bossRankId and CreateDefaultRanksForGang then
                    print(('^3[esx_families]^7 AUTO-HEAL: gang %d (%s) بلا رتب — جاري إنشاء الرتب الافتراضية'):format(gid, g.label))
                    CreateDefaultRanksForGang(gid, cid)
                    bossRankId = GangRanksIdx and GangRanksIdx[gid] and GangRanksIdx[gid][1]
                    if MembersCache[cid] and MembersCache[cid].gang_id == gid then
                        gangId = gid
                        break
                    end
                end
                if bossRankId then
                    if MembersCache[cid] and MembersCache[cid].gang_id ~= gid then
                        MySQL.query.await('DELETE FROM family_members WHERE citizenid = ?', { cid })
                    end
                    local mid = MySQL.insert.await(
                        'INSERT INTO family_members (gang_id, citizenid, rank_id, invited_by) VALUES (?,?,?,?) ' ..
                        'ON DUPLICATE KEY UPDATE gang_id = VALUES(gang_id), rank_id = VALUES(rank_id)',
                        { gid, cid, bossRankId, 'auto_heal' })
                    MembersCache[cid] = { id = mid, gang_id = gid, rank_id = bossRankId }
                    gangId = gid
                    print(('^2[esx_families]^7 AUTO-HEAL: leader %s added to gang %d (%s)'):format(cid, gid, g.label))
                else
                    print(('^1[esx_families]^7 AUTO-HEAL FAILED: gang %d بدون رتب وفشل إنشاؤها'):format(gid))
                end
                break
            end
        end
    end

    local gang = gangId and GangsCache[gangId] or nil
    local rank = GetPlayerRank(cid)
    local vault = gangId and VaultsCache[gangId] or nil
    local isLeader = gang and gang.leader_citizenid == cid or false

    -- عدد الأعضاء + عدد المناطق (سريع من cache)
    local memberCount, zoneCount = 0, 0
    if gangId then
        for _, m in pairs(MembersCache) do
            if m.gang_id == gangId then memberCount = memberCount + 1 end
        end
        for _, z in pairs(ZonesCache) do
            if z.gang_id == gangId then zoneCount = zoneCount + 1 end
        end
    end

    -- حربي الحالية (لو موجودة)
    local myWar = nil
    if gangId and GangActiveWar and GangActiveWar[gangId] then
        local w = ActiveWars[GangActiveWar[gangId]]
        if w then
            local atkScore = tonumber((w.scores or {})[w.attacker_gang_id] or (w.scores or {})[tostring(w.attacker_gang_id)]) or 0
            local defScore = tonumber((w.scores or {})[w.defender_gang_id] or (w.scores or {})[tostring(w.defender_gang_id)]) or 0
            myWar = {
                id = w.id, status = w.status,
                attacker = w.attacker_gang_id,
                defender = w.defender_gang_id,
                attacker_label = (GangsCache[w.attacker_gang_id] or {}).label,
                defender_label = (GangsCache[w.defender_gang_id] or {}).label,
                attacker_score = atkScore,
                defender_score = defScore,
                scores = {
                    [w.attacker_gang_id] = atkScore, [tostring(w.attacker_gang_id)] = atkScore,
                    [w.defender_gang_id] = defScore, [tostring(w.defender_gang_id)] = defScore,
                },
                zone_id = w.zone_id, zone = w.zone_id,
                zone_name = (ZonesCache[w.zone_id] or {}).name,
                starts_at = w.starts_at or 0, ends_at = w.ends_at or 0,
                my_side = (gangId == w.attacker_gang_id) and 'attacker' or 'defender',
            }
        end
    end

    return {
        cid = cid,
        isAdmin = admin,
        gang = gang,
        rank = rank,
        isLeader = isLeader,
        canOpenF6 = (gang ~= nil),               -- أي عضو يقدر يفتح F6 (تظهر له خيارات حسب رتبته)
        canOpenF9 = admin,                       -- F9 للأدمن فقط
        vault = vault and {
            money = vault.money or 0,
            war_locked = vault.war_locked == 1,
        } or nil,
        memberCount = memberCount,
        zoneCount = zoneCount,
        myWar = myWar,
    }
end)


lib.callback.register('qbx_families:server:getMyGang', function(source)
    -- backward compat — لا يزال مستخدم في vault.lua القديم
    local cid = GetCitizenId(source); if not cid then return nil end
    local gid = GetPlayerGang(cid)
    if gid and GangsCache[gid] then return GangsCache[gid] end
    -- fallback: leader
    for _, g in pairs(GangsCache) do
        if g.leader_citizenid == cid then return g end
    end
    -- fallback: keyholder
    for vaultId, holders in pairs(VaultKeysCache) do
        if holders[cid] then
            for gangId, v in pairs(VaultsCache) do
                if v.id == vaultId then return GangsCache[gangId] end
            end
        end
    end
    return nil
end)

-- ============================================================
-- 2) قراءة عامة (لكل اللاعبين)
-- ============================================================

lib.callback.register('qbx_families:server:listGangsPublic', function(source)
    -- معلومات عامة فقط (بدون citizenid للقائد)
    local list = {}
    for _, g in pairs(GangsCache) do
        local memberCount = 0
        for _, m in pairs(MembersCache) do
            if m.gang_id == g.id then memberCount = memberCount + 1 end
        end
        local zoneCount = 0
        for _, z in pairs(ZonesCache) do
            if z.gang_id == g.id then zoneCount = zoneCount + 1 end
        end
        list[#list+1] = {
            id = g.id, name = g.name, label = g.label,
            blip_color = g.blip_color,
            member_count = memberCount,
            zone_count = zoneCount,
            in_war = GangActiveWar and GangActiveWar[g.id] ~= nil,
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end)

lib.callback.register('qbx_families:server:listActiveWars', function(source)
    -- معلومات عامة عن الحروب النشطة (لكل اللاعبين)
    local list = {}
    if not ActiveWars then return list end
    for warId, w in pairs(ActiveWars) do
        list[#list+1] = {
            id = warId, status = w.status,
            attacker = (GangsCache[w.attacker_gang_id] or {}).label or '?',
            defender = (GangsCache[w.defender_gang_id] or {}).label or '?',
            zone = (ZonesCache[w.zone_id] or {}).name or '?',
            attacker_score = w.scores[w.attacker_gang_id] or 0,
            defender_score = w.scores[w.defender_gang_id] or 0,
            ends_at = w.ends_at,
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end)

-- ============================================================
-- 3) قراءة عصابة واحدة (لأعضائها أو الأدمن)
-- ============================================================

lib.callback.register('qbx_families:server:getGangDetails', function(source, gangId)
    if not isMyGangOrAdmin(source, gangId) then return nil end
    local g = GangsCache[gangId]
    if not g then return nil end

    local zones, vault = {}, VaultsCache[gangId]
    for _, z in pairs(ZonesCache) do
        if z.gang_id == gangId then
            zones[#zones+1] = {
                id = z.id, name = z.name,
                center_x = z.center_x, center_y = z.center_y, center_z = z.center_z,
                radius = z.radius, protection_percent = z.protection_percent,
            }
        end
    end

    return {
        gang = g,
        vault = vault and {
            id = vault.id, money = vault.money or 0,
            coords = { x = vault.coords_x, y = vault.coords_y, z = vault.coords_z },
            war_locked = vault.war_locked == 1,
        } or nil,
        zones = zones,
    }
end)

lib.callback.register('qbx_families:server:getAllZonesAdmin', function(source)
    if not IsAdmin(source) then return {} end
    local list = {}
    for _, z in pairs(ZonesCache) do
        local g = GangsCache[z.gang_id]
        list[#list+1] = {
            id = z.id, name = z.name,
            gang_id = z.gang_id, gang_label = g and g.label or '?',
            center_x = z.center_x, center_y = z.center_y, center_z = z.center_z,
            radius = z.radius, protection_percent = z.protection_percent,
            in_war = ZoneActiveWar and ZoneActiveWar[z.id] ~= nil,
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end)

-- ============================================================
-- 4) قائمة العصابات (للأدمن — نسخة كاملة)
-- ============================================================

lib.callback.register('qbx_families:server:getAllGangs', function(source)
    if not IsAdmin(source) then return {} end
    local list = {}
    for _, g in pairs(GangsCache) do table.insert(list, g) end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end)

-- ============================================================
-- 5) إدارة العصابات (Admin)
-- ============================================================

lib.callback.register('qbx_families:server:adminCreateGang', function(source, name, label, leaderId, color)
    if not IsAdmin(source) then return false, 'للأدمن فقط' end
    if not name or not label or not leaderId then return false, 'بيانات ناقصة' end

    -- v0.5.0: تطبيع citizenid
    leaderId = ESXBridge.NormalizeCitizenId(leaderId)
    if not leaderId then return false, 'CitizenID غير صالح' end

    -- v0.5.0: تحقق من وجود اللاعب (أونلاين أو في DB)
    local exists, leaderSrc = ESXBridge.CitizenExists(leaderId)
    if not exists then
        return false, ('اللاعب %s غير موجود في قاعدة البيانات (لازم يدخل السيرفر مرة وحدة على الأقل)'):format(leaderId)
    end

    -- تنظيف بسيط للاسم (lowercase, no spaces)
    name = string.lower(string.gsub(name, '%s+', '_'))

    local existsName = MySQL.scalar.await('SELECT id FROM family_gangs WHERE name = ?', { name })
    if existsName then return false, 'الاسم موجود مسبقاً' end

    -- v0.5.0: لو اللاعب في عصابة أخرى، نظّفه أولاً (وإلا INSERT IGNORE يفشل صامتاً)
    if MembersCache[leaderId] then
        MySQL.query.await('DELETE FROM family_members WHERE citizenid = ?', { leaderId })
        MembersCache[leaderId] = nil
    end

    local id = MySQL.insert.await(
        'INSERT INTO family_gangs (name, label, leader_citizenid, blip_color) VALUES (?, ?, ?, ?)',
        { name, label, leaderId, color or 1 }
    )
    if not id then return false, 'فشل الإنشاء في DB' end

    GangsCache[id] = { id = id, name = name, label = label, leader_citizenid = leaderId, blip_color = color or 1 }

    if CreateDefaultRanksForGang then
        CreateDefaultRanksForGang(id, leaderId)
    end

    -- v0.5.0: لو القائد أونلاين، أبلغه فوراً ليُحدّث context الكلاينت
    if leaderSrc then
        TriggerClientEvent('esx_families:client:youJoinedGang', leaderSrc, {
            gang = GangsCache[id],
            asLeader = true,
        })
        TriggerClientEvent('ox_lib:notify', leaderSrc, {
            type = 'success', icon = 'crown', duration = 8000,
            title = '👑 تهانينا!',
            description = ('أصبحت قائد عائلة %s\nاضغط F6 لفتح لوحة العائلة'):format(label),
        })
    end

    local onlineMsg = leaderSrc and ' (تم إبلاغ القائد أونلاين)' or ' (سيُفعّل عند دخول القائد)'
    return true, ('تم إنشاء %s (ID: %d) — 3 رتب افتراضية%s'):format(label, id, onlineMsg)
end)


lib.callback.register('qbx_families:server:adminChangeLeader', function(source, gangId, newLeaderCid)
    if not IsAdmin(source) then return false, 'للأدمن فقط' end
    local g = GangsCache[gangId]; if not g then return false, 'العصابة غير موجودة' end

    -- v0.5.0: تطبيع
    newLeaderCid = ESXBridge.NormalizeCitizenId(newLeaderCid)
    if not newLeaderCid then return false, 'CitizenID فارغ أو غير صالح' end

    local exists, leaderSrc = ESXBridge.CitizenExists(newLeaderCid)
    if not exists then
        return false, ('اللاعب %s غير موجود في DB'):format(newLeaderCid)
    end

    MySQL.update.await('UPDATE family_gangs SET leader_citizenid = ? WHERE id = ?', { newLeaderCid, gangId })
    g.leader_citizenid = newLeaderCid

    -- نضمن أن القائد الجديد عضو + برتبة Boss
    local bossRankId = GangRanksIdx and GangRanksIdx[gangId] and GangRanksIdx[gangId][1]
    if bossRankId then
        local existing = MembersCache[newLeaderCid]
        if existing and existing.gang_id == gangId then
            MySQL.update.await('UPDATE family_members SET rank_id = ? WHERE citizenid = ?', { bossRankId, newLeaderCid })
            existing.rank_id = bossRankId
        else
            if existing then
                MySQL.query.await('DELETE FROM family_members WHERE citizenid = ?', { newLeaderCid })
            end
            local mid = MySQL.insert.await(
                'INSERT INTO family_members (gang_id, citizenid, rank_id, invited_by) VALUES (?,?,?,?)',
                { gangId, newLeaderCid, bossRankId, 'admin' })
            MembersCache[newLeaderCid] = { id = mid, gang_id = gangId, rank_id = bossRankId }
        end
    end

    -- v0.5.0: أبلغ القائد الجديد لو أونلاين
    if leaderSrc then
        TriggerClientEvent('esx_families:client:youJoinedGang', leaderSrc, {
            gang = g, asLeader = true,
        })
        TriggerClientEvent('ox_lib:notify', leaderSrc, {
            type = 'success', icon = 'crown', duration = 8000,
            title = '👑 تعيين قيادة',
            description = ('أصبحت قائد عائلة %s'):format(g.label),
        })
    end

    return true, ('تم تعيين %s كقائد لـ %s'):format(newLeaderCid, g.label)
end)


lib.callback.register('qbx_families:server:adminDeleteGang', function(source, gangId)
    if not IsAdmin(source) then return false, 'للأدمن فقط' end
    local gang = GangsCache[gangId]
    if not gang then return false, 'العصابة غير موجودة' end

    -- منع الحذف لو في حرب
    if GangActiveWar and GangActiveWar[gangId] then
        return false, 'لا يمكن حذف عصابة في حرب نشطة. أنهِ الحرب أولاً'
    end

    MySQL.query.await('DELETE FROM family_gangs WHERE id = ?', { gangId })

    -- تنظيف الكاش
    local vault = VaultsCache[gangId]
    if vault then
        VaultKeysCache[vault.id] = nil
        VaultsCache[gangId] = nil
        TriggerClientEvent('qbx_families:client:vaultDeleted', -1, gangId)
    end
    for zid, z in pairs(ZonesCache) do
        if z.gang_id == gangId then ZonesCache[zid] = nil end
    end
    -- تنظيف members + ranks من الكاش (DB يحذف عبر CASCADE)
    for cid, m in pairs(MembersCache) do
        if m.gang_id == gangId then MembersCache[cid] = nil end
    end
    if RanksCache then
        for rid, r in pairs(RanksCache) do
            if r.gang_id == gangId then RanksCache[rid] = nil end
        end
    end
    if GangRanksIdx then GangRanksIdx[gangId] = nil end
    GangsCache[gangId] = nil

    SyncZonesToAll()
    return true, ('تم حذف عصابة %s مع كل بياناتها'):format(gang.label)
end)

-- ============================================================
-- 6) إدارة المناطق (Admin)
-- ============================================================

lib.callback.register('qbx_families:server:adminCreateZone', function(source, gangId, zoneName, radius, protection)
    if not IsAdmin(source) then return false, 'للأدمن فقط' end
    if not GangsCache[gangId] then return false, 'العصابة غير موجودة' end
    if not zoneName or zoneName == '' then return false, 'الاسم مطلوب' end

    local prot = math.max(Config.MinProtectionPercent, math.min(Config.MaxProtectionPercent, protection or 10))
    radius = math.max(20, math.min(500, tonumber(radius) or 80))
    local coords = GetEntityCoords(GetPlayerPed(source))

    local id = MySQL.insert.await(
        'INSERT INTO family_zones (name, gang_id, center_x, center_y, center_z, radius, protection_percent) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { zoneName, gangId, coords.x, coords.y, coords.z, radius, prot }
    )
    if not id then return false, 'فشل الإنشاء' end

    ZonesCache[id] = {
        id = id, name = zoneName, gang_id = gangId,
        center_x = coords.x, center_y = coords.y, center_z = coords.z,
        radius = radius, protection_percent = prot,
    }
    -- إعادة بناء spatial grid (إذا كانت الدالة موجودة)
    if Shared and Shared.RebuildSpatialGrid then
        Shared.RebuildSpatialGrid(ZonesCache)
    end
    SyncZonesToAll()
    return true, ('تم إنشاء زون %s | شعاع %dم | حماية %.1f%%'):format(zoneName, radius, prot)
end)

lib.callback.register('qbx_families:server:adminDeleteZone', function(source, zoneId)
    if not IsAdmin(source) then return false, 'للأدمن فقط' end
    if not ZonesCache[zoneId] then return false, 'الزون غير موجود' end
    if ZoneActiveWar and ZoneActiveWar[zoneId] then
        return false, 'لا يمكن حذف زون في حرب نشطة'
    end
    MySQL.query.await('DELETE FROM family_zones WHERE id = ?', { zoneId })
    ZonesCache[zoneId] = nil
    if Shared and Shared.RebuildSpatialGrid then
        Shared.RebuildSpatialGrid(ZonesCache)
    end
    SyncZonesToAll()
    return true, 'تم حذف الزون'
end)

-- ============================================================
-- 7) إدارة الخزائن (Admin)
-- ============================================================

lib.callback.register('qbx_families:server:adminCreateVault', function(source, gangId)
    if not IsAdmin(source) then return false, 'للأدمن فقط' end
    local gang = GangsCache[gangId]
    if not gang then return false, 'العصابة غير موجودة' end
    if VaultsCache[gangId] then return false, 'هذه العصابة عندها خزنة بالفعل' end

    local coords = GetEntityCoords(GetPlayerPed(source))
    local id = MySQL.insert.await(
        'INSERT INTO family_vaults (gang_id, coords_x, coords_y, coords_z) VALUES (?, ?, ?, ?)',
        { gangId, coords.x, coords.y, coords.z }
    )
    if not id then return false, 'فشل الإنشاء' end

    VaultsCache[gangId] = {
        id = id, gang_id = gangId,
        coords_x = coords.x, coords_y = coords.y, coords_z = coords.z, money = 0,
    }
    VaultKeysCache[id] = {}
    TriggerClientEvent('qbx_families:client:vaultCreated', -1, VaultsCache[gangId], gang)
    return true, ('تم إنشاء خزنة %s'):format(gang.label)
end)

lib.callback.register('qbx_families:server:adminDeleteVault', function(source, gangId)
    if not IsAdmin(source) then return false, 'للأدمن فقط' end
    local vault = VaultsCache[gangId]
    if not vault then return false, 'لا توجد خزنة لهذه العصابة' end
    if vault.war_locked == 1 then return false, 'الخزنة مقفلة (حرب). انتظر أو أنهِ الحرب' end

    MySQL.query.await('DELETE FROM family_vault_keys WHERE vault_id = ?', { vault.id })
    MySQL.query.await('DELETE FROM family_vaults WHERE id = ?', { vault.id })

    VaultKeysCache[vault.id] = nil
    VaultsCache[gangId] = nil

    TriggerClientEvent('qbx_families:client:vaultDeleted', -1, gangId)
    return true, 'تم حذف الخزنة'
end)

-- ============================================================
-- 8) فعاليات نطلبها من الكلاينت (مزامنة أولية)
-- ============================================================

RegisterNetEvent('qbx_families:server:requestZones', function()
    local src = source
    TriggerClientEvent('qbx_families:client:syncZones', src, ZonesCache, GangsCache)
end)

RegisterNetEvent('qbx_families:server:requestVaults', function()
    local src = source
    for gangId, v in pairs(VaultsCache) do
        local gang = GangsCache[gangId]
        if gang then
            TriggerClientEvent('qbx_families:client:vaultCreated', src, v, gang)
        end
    end
end)

-- ============================================================
-- 9) Vault logs (يستخدمها client/vault.lua)
-- ============================================================

lib.callback.register('qbx_families:server:getVaultLogs', function(source, gangId, limit)
    local vault = VaultsCache[gangId]
    if not vault then return {} end
    local cid = GetCitizenId(source)
    if not cid then return {} end
    -- آدمن أو عضو/قائد/keyholder
    local can = IsAdmin(source) or isLeaderOf(cid, gangId) or GetPlayerGang(cid) == gangId
        or (VaultKeysCache[vault.id] and VaultKeysCache[vault.id][cid])
    if not can then return {} end

    limit = math.min(tonumber(limit) or 30, 100)
    return MySQL.query.await(
        'SELECT * FROM family_vault_logs WHERE vault_id = ? ORDER BY id DESC LIMIT ?',
        { vault.id, limit }) or {}
end)

-- ============================================================
-- 10) إخراج عضو نفسه من العائلة (Leave)
-- ============================================================

lib.callback.register('qbx_families:server:leaveGang', function(source)
    local cid = GetCitizenId(source); if not cid then return false end
    local m = MembersCache[cid]; if not m then return false, 'لست في عائلة' end
    -- القائد لا يقدر يغادر — يجب نقل القيادة أو حذف العصابة
    local gang = GangsCache[m.gang_id]
    if gang and gang.leader_citizenid == cid then
        return false, 'القائد لا يقدر يغادر — انقل القيادة أو احذف العصابة (للأدمن)'
    end
    MySQL.query.await('DELETE FROM family_members WHERE citizenid = ?', { cid })
    MembersCache[cid] = nil
    -- v0.5.1: أبلغ نفس اللاعب لتحديث UI/HUD
    TriggerClientEvent('esx_families:client:youLeftGang', source)
    return true, 'غادرت العائلة'
end)

lib.callback.register('qbx_families:server:getOnlinePlayers', function(source)
    local allowed = false

    if type(IsAdmin) == 'function' then
        allowed = IsAdmin(source) == true
    elseif IsPlayerAceAllowed then
        allowed = IsPlayerAceAllowed(source, 'command') == true
    end

    if not allowed then return {} end

    local list = {}

    for _, sid in ipairs(GetPlayers()) do
        local id = tonumber(sid)
        local name = GetPlayerName(id) or ('Player ' .. tostring(id))
        local identifier = nil

        if ESX and ESX.GetPlayerFromId then
            local xPlayer = ESX.GetPlayerFromId(id)
            if xPlayer then
                identifier = xPlayer.identifier
                if xPlayer.getName then
                    name = xPlayer.getName() or name
                end
            end
        end

        list[#list + 1] = {
            source = id,
            serverId = id,
            id = id,
            identifier = identifier,
            citizenid = identifier,
            name = name,
            label = ('[%s] %s'):format(id, name)
        }
    end

    return list
end)
