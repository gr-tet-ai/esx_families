-- ============================================================
-- esx_families v0.6.1 — Diagnostics & Test-Data Seeder
-- /family_diag           — تشخيص حالة اللاعب
-- /seed_test_gang        — إنشاء عصابة test ثانية + زون test (آدمن)
-- ============================================================

lib.addCommand('family_diag', {
    help = 'تشخيص حالة عضويتك في النظام',
}, function(source)
    local src = source
    local cid = GetCitizenId(src)
    local lines = { '═══ Family Diagnostics ═══' }

    -- 1) citizenid
    table.insert(lines, ('citizenid : %s'):format(cid or '❌ nil'))

    -- 2) ESX identifier raw
    if ESX and ESX.GetPlayerFromId then
        local xp = ESX.GetPlayerFromId(src)
        table.insert(lines, ('xPlayer.identifier : %s'):format(xp and xp.identifier or '❌ nil'))
        table.insert(lines, ('xPlayer.job : %s'):format(xp and xp.job and xp.job.name or '?'))
    end

    if not cid then
        for _, l in ipairs(lines) do print(l); TriggerClientEvent('chat:addMessage', src, { args = { '[diag]', l } }) end
        return
    end

    -- 3) في MembersCache؟
    local m = MembersCache[cid]
    table.insert(lines, ('MembersCache : %s'):format(m and ('gang=%d rank=%s'):format(m.gang_id, tostring(m.rank_id)) or '❌ nil'))

    -- 4) DB direct check
    local row = MySQL.single.await('SELECT * FROM family_members WHERE citizenid = ?', { cid })
    table.insert(lines, ('family_members (DB) : %s'):format(row and ('gang=%d rank=%s'):format(row.gang_id, tostring(row.rank_id)) or '❌ غير موجود'))

    -- 5) هل أنت قائد لعصابة؟
    for gid, g in pairs(GangsCache) do
        if g.leader_citizenid == cid then
            table.insert(lines, ('قائد عصابة : ID=%d label=%s'):format(gid, g.label))
            local ranksCount = 0
            if GangRanksIdx[gid] then for _ in pairs(GangRanksIdx[gid]) do ranksCount = ranksCount + 1 end end
            table.insert(lines, ('عدد الرتب : %d %s'):format(ranksCount, ranksCount == 0 and '⚠️ مفقودة!' or '✓'))
        end
    end

    -- 6) أقرب زون
    local coords = GetEntityCoords(GetPlayerPed(src))
    local nearest, ndist = nil, math.huge
    for _, z in pairs(ZonesCache) do
        local d = #(vector2(coords.x, coords.y) - vector2(z.center_x, z.center_y))
        if d < ndist then ndist = d; nearest = z end
    end
    if nearest then
        table.insert(lines, ('أقرب زون : %s (gang=%d) على بُعد %.1f م (radius=%.0f)'):format(
            nearest.name or '?', nearest.gang_id, ndist, nearest.radius))
    else
        table.insert(lines, 'أقرب زون : ❌ لا يوجد زونات في النظام')
    end

    -- 7) أقرب خزنة
    local nv, nvd = nil, math.huge
    for gid, v in pairs(VaultsCache) do
        local d = #(coords - vector3(v.coords_x, v.coords_y, v.coords_z))
        if d < nvd then nvd = d; nv = { gid = gid, v = v } end
    end
    if nv then
        table.insert(lines, ('أقرب خزنة : gang=%d على بُعد %.1f م (interactDist=%.1f)'):format(
            nv.gid, nvd, Config.VaultInteractDistance or 2.0))
    end

    -- إجمالي إحصاءات
    local gc, zc, mc, rc = 0, 0, 0, 0
    for _ in pairs(GangsCache) do gc = gc + 1 end
    for _ in pairs(ZonesCache) do zc = zc + 1 end
    for _ in pairs(MembersCache) do mc = mc + 1 end
    for _ in pairs(RanksCache) do rc = rc + 1 end
    table.insert(lines, ('═══ النظام: gangs=%d zones=%d members=%d ranks=%d'):format(gc, zc, mc, rc))

    for _, l in ipairs(lines) do
        print(l)
        TriggerClientEvent('chat:addMessage', src, { color = {255,215,0}, args = { '[diag]', l } })
    end
end)

-- ============================================================
-- /seed_test_gang — إنشاء عصابة test + زون عند موقعك (لاختبار الحرب)
-- ============================================================
lib.addCommand('seed_test_gang', {
    help = 'إنشاء عصابة + زون test عند موقعك (آدمن — لاختبار الحرب)',
    params = {
        { name = 'leaderid', type = 'string', help = 'CitizenID للقائد الوهمي (ممكن أي string)', optional = true },
    },
}, function(source, args)
    if not IsAdmin(source) then
        return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'للآدمن فقط' })
    end
    local leaderId = args.leaderid or ('test_leader_' .. os.time())
    local stamp = os.time()
    local name  = 'test' .. stamp
    local label = 'Test Family ' .. stamp

    -- (1) إنشاء العصابة
    local exists = MySQL.scalar.await('SELECT id FROM family_gangs WHERE name = ?', { name })
    if exists then
        return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'موجود' })
    end
    local gid = MySQL.insert.await(
        'INSERT INTO family_gangs (name, label, leader_citizenid, blip_color) VALUES (?,?,?,?)',
        { name, label, leaderId, 3 })
    if not gid then
        return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'فشل إنشاء العصابة' })
    end
    GangsCache[gid] = { id = gid, name = name, label = label, leader_citizenid = leaderId, blip_color = 3 }

    -- (2) رتب افتراضية + إدخال القائد الوهمي
    if CreateDefaultRanksForGang then CreateDefaultRanksForGang(gid, leaderId) end

    -- (3) زون عند موقع الآدمن
    local coords = GetEntityCoords(GetPlayerPed(source))
    local zid = MySQL.insert.await([[
        INSERT INTO family_zones (gang_id, name, center_x, center_y, center_z, radius, protection_percent)
        VALUES (?,?,?,?,?,?,?)
    ]], { gid, 'منطقة test ' .. stamp, coords.x, coords.y, coords.z, 80.0, 5.0 })
    if zid then
        ZonesCache[zid] = {
            id = zid, gang_id = gid, name = 'منطقة test ' .. stamp,
            center_x = coords.x, center_y = coords.y, center_z = coords.z,
            radius = 80.0, protection_percent = 5.0,
        }
        -- client سيعيد البناء عبر SyncZonesToAll
        SyncZonesToAll()
    end

    TriggerClientEvent('ox_lib:notify', source, {
        type = 'success', duration = 8000,
        description = ('✓ test gang #%d + zone #%s | leader=%s'):format(gid, tostring(zid), leaderId),
    })
    print(('^2[esx_families]^7 SEED: gang #%d (%s) + zone #%s @ leader=%s'):format(gid, label, tostring(zid), leaderId))
end)

-- ============================================================
-- v0.6.2-hotfix: /family_fixme [gangId]
-- يصلح أكثر سبب شائع لعدم فتح F6 بعد مشكلة اختيار Server ID:
-- leader_citizenid في DB يكون على لاعب غلط، أو القائد غير موجود في family_members.
-- ============================================================
local function _famSend(src, msg, color)
    print('[family_fixme] ' .. msg)
    if src and src > 0 then
        TriggerClientEvent('chat:addMessage', src, { color = color or {255, 215, 0}, args = { '[family_fixme]', msg } })
    end
end

local function _famEnsureBossRank(gangId)
    gangId = tonumber(gangId)
    local bossRankId = GangRanksIdx and GangRanksIdx[gangId] and GangRanksIdx[gangId][1]
    if bossRankId then return bossRankId end

    local row = MySQL.single.await('SELECT * FROM family_ranks WHERE gang_id = ? AND rank_order = 1 LIMIT 1', { gangId })
    if row and row.id then
        RanksCache[row.id] = row
        GangRanksIdx[gangId] = GangRanksIdx[gangId] or {}
        GangRanksIdx[gangId][1] = row.id
        return row.id
    end

    local id = MySQL.insert.await([[
        INSERT INTO family_ranks
        (gang_id, rank_order, label, tier,
         can_open_vault, can_withdraw, can_deposit,
         can_invite, can_kick, can_promote, can_manage_zones,
         daily_withdraw_limit)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
    ]], { gangId, 1, 'زعيم', 1, 1, 1, 1, 1, 1, 1, 1, 0 })

    if id then
        local r = {
            id = id, gang_id = gangId, rank_order = 1, label = 'زعيم', tier = 1,
            can_open_vault = 1, can_withdraw = 1, can_deposit = 1,
            can_invite = 1, can_kick = 1, can_promote = 1, can_manage_zones = 1,
            daily_withdraw_limit = 0,
        }
        RanksCache[id] = r
        GangRanksIdx[gangId] = GangRanksIdx[gangId] or {}
        GangRanksIdx[gangId][1] = id
        return id
    end

    return nil
end

lib.addCommand('family_fixme', {
    help = 'إصلاح F6: يجعل لاعبك قائد العائلة المحددة ويضيفك كزعيم في family_members',
    params = {
        { name = 'gangid', type = 'number', help = 'رقم العائلة من F9 أو /family_diag', optional = true },
    },
}, function(source, args)
    local src = tonumber(source) or 0
    if src <= 0 then
        print('[family_fixme] استخدم الأمر من داخل اللعبة وليس من الكونسول: /family_fixme <gangId>')
        return
    end
    if not IsAdmin(src) then
        return TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'للأدمن فقط' })
    end

    local cid = GetCitizenId(src)
    if not cid then
        return _famSend(src, 'تعذر قراءة identifier حق لاعبك — انتظر ثواني بعد الدخول وجرب.', {255, 80, 80})
    end

    local gangId = tonumber(args and (args.gangid or args[1]))
    if not gangId then
        local ids = {}
        for gid, g in pairs(GangsCache or {}) do
            ids[#ids+1] = { id = tonumber(gid), label = g.label or g.name or '?' }
        end
        table.sort(ids, function(a, b) return a.id < b.id end)
        if #ids == 1 then
            gangId = ids[1].id
        else
            _famSend(src, 'حدد رقم العائلة: /family_fixme <gangId>', {255, 215, 0})
            for _, g in ipairs(ids) do
                _famSend(src, ('ID=%d | %s'):format(g.id, g.label), {200, 220, 255})
            end
            return
        end
    end

    local gang = GangsCache and GangsCache[gangId]
    if not gang then
        return _famSend(src, ('العائلة #%s غير موجودة في الكاش. سو restart esx_families ثم جرب.'):format(tostring(gangId)), {255, 80, 80})
    end

    local bossRankId = _famEnsureBossRank(gangId)
    if not bossRankId then
        return _famSend(src, 'فشل إنشاء/قراءة رتبة الزعيم.', {255, 80, 80})
    end

    MySQL.update.await('UPDATE family_gangs SET leader_citizenid = ? WHERE id = ?', { cid, gangId })
    gang.leader_citizenid = cid
    GangsCache[gangId] = gang

    MySQL.query.await([[
        INSERT INTO family_members (gang_id, citizenid, rank_id, invited_by)
        VALUES (?,?,?,?)
        ON DUPLICATE KEY UPDATE
            gang_id = VALUES(gang_id),
            rank_id = VALUES(rank_id),
            invited_by = VALUES(invited_by)
    ]], { gangId, cid, bossRankId, 'family_fixme' })

    local mrow = MySQL.single.await('SELECT id, gang_id, rank_id FROM family_members WHERE citizenid = ? LIMIT 1', { cid })
    MembersCache[cid] = { id = mrow and mrow.id or nil, gang_id = gangId, rank_id = bossRankId }

    TriggerClientEvent('esx_families:client:youJoinedGang', src, { gang = gang, asLeader = true })
    TriggerClientEvent('ox_lib:notify', src, {
        type = 'success', duration = 9000,
        title = 'F6 repaired',
        description = ('تم تعيينك قائد %s وإضافتك كزعيم. جرّب /familymenu ثم F6.'):format(gang.label or ('#' .. gangId)),
    })

    _famSend(src, ('OK: cid=%s صار قائد gang=%d rank=%s'):format(cid, gangId, tostring(bossRankId)), {80, 255, 120})
end)

-- ============================================================
-- v0.6.2: /family_f6_report — تقرير قراءة فقط يوضح سبب ظهور "لست في عائلة"
-- ============================================================
lib.addCommand('family_f6_report', {
    help = 'تقرير F6: يطابق identifier الحالي مع DB والكاش والطلبات',
}, function(source)
    local src = source
    local cid = GetCitizenId(src)
    local lines = { '═══ F6 Context Report v0.6.2 ═══' }
    table.insert(lines, ('source=%s cid=%s isAdmin=%s'):format(tostring(src), tostring(cid), tostring(IsAdmin(src))))

    if ESX and ESX.GetPlayerFromId then
        local xp = ESX.GetPlayerFromId(src)
        table.insert(lines, ('xPlayer.identifier=%s'):format(xp and xp.identifier or 'nil'))
    end

    if cid then
        local mc = MembersCache and MembersCache[cid] or nil
        table.insert(lines, ('MembersCache=%s'):format(mc and ('gang=' .. tostring(mc.gang_id) .. ' rank=' .. tostring(mc.rank_id)) or 'nil'))

        local dbm = MySQL.single.await('SELECT id, gang_id, rank_id FROM family_members WHERE citizenid = ? LIMIT 1', { cid })
        table.insert(lines, ('DB family_members=%s'):format(dbm and ('id=' .. tostring(dbm.id) .. ' gang=' .. tostring(dbm.gang_id) .. ' rank=' .. tostring(dbm.rank_id)) or 'nil'))

        local dbg = MySQL.single.await('SELECT id, label, leader_citizenid FROM family_gangs WHERE leader_citizenid = ? LIMIT 1', { cid })
        table.insert(lines, ('DB leader_gang=%s'):format(dbg and ('id=' .. tostring(dbg.id) .. ' label=' .. tostring(dbg.label)) or 'nil'))

        local gid = (mc and mc.gang_id) or (dbm and dbm.gang_id) or (dbg and dbg.id)
        if gid then
            local reqCount = MySQL.scalar.await("SELECT COUNT(*) FROM family_join_requests WHERE gang_id = ? AND status = 'pending'", { gid }) or 0
            table.insert(lines, ('pending_join_requests=%s'):format(tostring(reqCount)))
        end
    end

    for _, l in ipairs(lines) do
        print('[family_f6_report] ' .. l)
        TriggerClientEvent('chat:addMessage', src, { color = {80, 220, 255}, args = { '[f6]', l } })
    end
end)

-- ============================================================
-- v0.6.3: /family_id_report — verifies canonical ESX identifier vs DB
-- ============================================================
lib.addCommand('family_id_report', {
    help = 'تقرير المعرّف: يوضح هل النظام يستخدم char أو license'
}, function(source)
    local src = source
    local xPlayer = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src) or nil
    local cid = GetCitizenId(src)
    local license = nil
    for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
        if tostring(identifier):match('^license:') then license = identifier break end
    end

    local lines = { '═══ Identifier Report v0.6.3 ═══' }
    lines[#lines+1] = ('GetCitizenId=%s'):format(tostring(cid))
    lines[#lines+1] = ('xPlayer.identifier=%s'):format(xPlayer and tostring(xPlayer.identifier) or 'nil')
    lines[#lines+1] = ('license_identifier=%s'):format(tostring(license))

    if cid then
        local dbm = MySQL.single.await('SELECT id, gang_id, rank_id FROM family_members WHERE citizenid = ? LIMIT 1', { cid })
        local dbg = MySQL.single.await('SELECT id, label, leader_citizenid FROM family_gangs WHERE leader_citizenid = ? LIMIT 1', { cid })
        lines[#lines+1] = ('DB family_members=%s'):format(dbm and ('id=' .. dbm.id .. ' gang=' .. dbm.gang_id .. ' rank=' .. tostring(dbm.rank_id)) or 'nil')
        lines[#lines+1] = ('DB leader_gang=%s'):format(dbg and ('id=' .. dbg.id .. ' label=' .. tostring(dbg.label)) or 'nil')
    end

    for _, line in ipairs(lines) do
        print('[family_id_report] ' .. line)
        TriggerClientEvent('chat:addMessage', src, { color = {80, 220, 255}, args = { '[id]', line } })
    end
end)

