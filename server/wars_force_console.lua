-- ============================================================
-- esx_families v0.7.0c — Console Force War Commands
-- Fixes: txAdmin "No such command familywar_force"
-- Commands:
--   familywar_list
--   familywar_force <attackerId/name> <defenderId/name> [zoneId|auto] [now|prep]
--   familywar_force <attacker name> | <defender name> [| zoneId|auto] [| now|prep]
--   familywar_force auto
-- ============================================================

local function fwNow()
    return os.time()
end

local function fwTrim(s)
    s = tostring(s or '')
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    return s
end

local function fwNorm(s)
    s = fwTrim(s):lower()
    s = s:gsub('ـ', '')
    s = s:gsub('%s+', '')
    return s
end

local function fwConsoleOrAdmin(src)
    return src == 0 or (IsAdmin and IsAdmin(src))
end

local function fwReply(src, msg)
    msg = tostring(msg or '')
    print('[esx_families:forcewar] ' .. msg)
    if src and src ~= 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { '^3esx_families', msg } })
    end
end

local function fwGangName(id)
    local g = GangsCache and GangsCache[id]
    return (g and (g.label or g.name)) or ('gang#' .. tostring(id))
end

local function fwZoneName(id)
    local z = ZonesCache and ZonesCache[id]
    return (z and (z.name or z.label)) or ('zone#' .. tostring(id))
end

local function fwFindGang(query)
    query = fwTrim(query)
    if query == '' then return nil, 'اسم/ID العائلة فاضي' end

    local asNum = tonumber(query)
    if asNum and GangsCache and GangsCache[asNum] then
        return asNum, GangsCache[asNum]
    end

    local nq = fwNorm(query)
    local exact, partial = {}, {}

    for id, g in pairs(GangsCache or {}) do
        local label = fwNorm(g.label or '')
        local name = fwNorm(g.name or '')
        if label == nq or name == nq then
            exact[#exact + 1] = { id = id, gang = g }
        elseif nq ~= '' and (
            (label ~= '' and label:find(nq, 1, true)) or
            (name ~= '' and name:find(nq, 1, true)) or
            (label ~= '' and nq:find(label, 1, true)) or
            (name ~= '' and nq:find(name, 1, true))
        ) then
            partial[#partial + 1] = { id = id, gang = g }
        end
    end

    local list = (#exact > 0) and exact or partial
    if #list == 1 then return list[1].id, list[1].gang end
    if #list == 0 then return nil, 'ما لقيت عائلة تطابق: ' .. query end

    local names = {}
    for _, row in ipairs(list) do
        names[#names + 1] = ('%s=%s'):format(row.id, row.gang.label or row.gang.name or '?')
    end
    return nil, 'الاسم غير محدد، استخدم ID: ' .. table.concat(names, ', ')
end

local function fwFindZoneForDefender(defenderGangId, zoneQuery)
    zoneQuery = fwTrim(zoneQuery or '')

    if zoneQuery ~= '' and zoneQuery ~= 'auto' then
        local zid = tonumber(zoneQuery)
        if not zid or not ZonesCache or not ZonesCache[zid] then
            return nil, 'الزون غير موجود: ' .. zoneQuery
        end
        if ZonesCache[zid].gang_id ~= defenderGangId then
            return nil, ('الزون %s مو مملوك للمدافع %s'):format(zid, fwGangName(defenderGangId))
        end
        return zid, ZonesCache[zid]
    end

    local candidates = {}
    for id, z in pairs(ZonesCache or {}) do
        if z.gang_id == defenderGangId and not (ZoneActiveWar and ZoneActiveWar[id]) then
            candidates[#candidates + 1] = { id = id, zone = z }
        end
    end
    table.sort(candidates, function(a, b) return tostring(a.zone.name or a.id) < tostring(b.zone.name or b.id) end)

    if #candidates == 0 then
        return nil, 'ما فيه زون فاضي مملوك للمدافع: ' .. fwGangName(defenderGangId)
    end
    return candidates[1].id, candidates[1].zone
end

local function fwParseForceArgs(args, rawCommand)
    local raw = tostring(rawCommand or ''):gsub('^%S+%s*', '')
    raw = fwTrim(raw)

    if raw == '' then return nil, nil, nil, nil, 'missing' end
    if fwNorm(raw) == 'auto' then return 'auto', nil, nil, 'now', nil end

    if raw:find('|', 1, true) then
        local parts = {}
        for part in raw:gmatch('[^|]+') do parts[#parts + 1] = fwTrim(part) end
        return parts[1], parts[2], parts[3], parts[4] or 'now', nil
    end

    if #args >= 2 then
        return args[1], args[2], args[3], args[4] or 'now', nil
    end

    return nil, nil, nil, nil, 'missing'
end

local function fwBroadcastWar(war)
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

    if war.status == 'active' then
        local zone = ZonesCache and ZonesCache[war.zone_id]
        if zone then
            TriggerClientEvent('esx_families:client:warStarted', -1, war.id, {
                center_x = zone.center_x,
                center_y = zone.center_y,
                center_z = zone.center_z,
                radius = zone.radius,
                name = zone.name,
            })
        end
    end
end

local function fwLockTradePoints(zoneId)
    for _, p in pairs(TradePointsCache or {}) do
        if p.zone_id == zoneId then
            p.war_disabled = 1
            MySQL.update('UPDATE family_trade_points SET war_disabled = 1 WHERE id = ?', { p.id })
        end
    end
end

local function fwCreateWar(src, attackerGangId, defenderGangId, zoneId, instantStart)
    if not GangsCache or not ZonesCache then return false, 'الكاش غير جاهز' end
    if not GangsCache[attackerGangId] then return false, 'المهاجم غير موجود' end
    if not GangsCache[defenderGangId] then return false, 'المدافع غير موجود' end
    if attackerGangId == defenderGangId then return false, 'لازم عائلتين مختلفتين' end
    if not ZonesCache[zoneId] then return false, 'الزون غير موجود' end
    if ZonesCache[zoneId].gang_id ~= defenderGangId then return false, 'الزون لازم يكون مملوك للمدافع' end
    if ZoneActiveWar and ZoneActiveWar[zoneId] then return false, 'الزون في حرب نشطة' end
    if GangActiveWar and GangActiveWar[attackerGangId] then return false, 'المهاجم في حرب نشطة' end
    if GangActiveWar and GangActiveWar[defenderGangId] then return false, 'المدافع في حرب نشطة' end

    local cfg = (GetWarConfig and GetWarConfig()) or {}
    local prep = instantStart and 0 or tonumber(cfg.prep_minutes or 5) or 5
    local duration = tonumber(cfg.duration_minutes or 30) or 30
    local startsAt = fwNow() + (prep * 60)
    local endsAt = startsAt + (duration * 60)
    local status = instantStart and 'active' or 'preparing'
    local lootPercent = tonumber(cfg.loot_percent or 30) or 30

    local warId = MySQL.insert.await([[
        INSERT INTO family_wars
        (attacker_gang_id, defender_gang_id, zone_id, status,
         starts_at, ends_at, cost_paid, loot_percent, is_test_mode)
        VALUES (?, ?, ?, ?, FROM_UNIXTIME(?), FROM_UNIXTIME(?), 0, ?, 1)
    ]], { attackerGangId, defenderGangId, zoneId, status, startsAt, endsAt, lootPercent })

    if not warId then return false, 'فشل إنشاء سجل الحرب في DB' end

    if SnapshotVault then SnapshotVault(defenderGangId) end
    if LockVault then
        LockVault(attackerGangId)
        LockVault(defenderGangId)
    end

    local atkMembers, defMembers = {}, {}
    for cid, m in pairs(MembersCache or {}) do
        if m.gang_id == attackerGangId then
            atkMembers[#atkMembers + 1] = cid
        elseif m.gang_id == defenderGangId then
            defMembers[#defMembers + 1] = cid
        end
    end

    if (#atkMembers + #defMembers) > 0 then
        local placeholders, values = {}, {}
        for _, cid in ipairs(atkMembers) do
            placeholders[#placeholders + 1] = '(?,?,?)'
            values[#values + 1] = warId
            values[#values + 1] = cid
            values[#values + 1] = attackerGangId
        end
        for _, cid in ipairs(defMembers) do
            placeholders[#placeholders + 1] = '(?,?,?)'
            values[#values + 1] = warId
            values[#values + 1] = cid
            values[#values + 1] = defenderGangId
        end
        MySQL.query.await('INSERT INTO family_war_participants (war_id, citizenid, gang_id) VALUES ' .. table.concat(placeholders, ','), values)
    end

    MySQL.query.await('INSERT INTO family_war_scores (war_id, gang_id) VALUES (?,?), (?,?)', {
        warId, attackerGangId, warId, defenderGangId
    })

    fwLockTradePoints(zoneId)

    local war = {
        id = warId,
        attacker_gang_id = attackerGangId,
        defender_gang_id = defenderGangId,
        zone_id = zoneId,
        status = status,
        starts_at = startsAt,
        ends_at = endsAt,
        cost_paid = 0,
        loot_percent = lootPercent,
        is_test_mode = true,
        scores = { [attackerGangId] = 0, [defenderGangId] = 0 },
        kills = { [attackerGangId] = 0, [defenderGangId] = 0 },
        deaths = { [attackerGangId] = 0, [defenderGangId] = 0 },
        presence_minutes = { [attackerGangId] = 0, [defenderGangId] = 0 },
        participants = {},
        pending_score_writes = {},
    }

    for _, cid in ipairs(atkMembers) do war.participants[cid] = attackerGangId end
    for _, cid in ipairs(defMembers) do war.participants[cid] = defenderGangId end

    ActiveWars[warId] = war
    ZoneActiveWar[zoneId] = warId
    GangActiveWar[attackerGangId] = warId
    GangActiveWar[defenderGangId] = warId

    if LogWarEvent then
        LogWarEvent(warId, 'admin_console_force_declared', nil, attackerGangId, nil, defenderGangId, 0, {
            admin_src = src,
            instant = instantStart,
            zone = fwZoneName(zoneId),
        })
    end

    TriggerClientEvent('ox_lib:notify', -1, {
        type = 'warning',
        title = '⚔️ حرب مفروضة',
        description = ('%s ضد %s — %s%s'):format(
            fwGangName(attackerGangId), fwGangName(defenderGangId), fwZoneName(zoneId),
            instantStart and ' | بدأت الآن' or (' | تحضير ' .. tostring(prep) .. 'د')
        ),
        duration = 12000,
    })

    fwBroadcastWar(war)
    if EnsureWarTickThread then EnsureWarTickThread() end

    return true, ('war#%s %s vs %s zone=%s status=%s participants=%s'):format(
        warId, fwGangName(attackerGangId), fwGangName(defenderGangId), fwZoneName(zoneId), status,
        tostring(#atkMembers + #defMembers)
    )
end

RegisterCommand('familywar_list', function(src)
    if not fwConsoleOrAdmin(src) then return end

    fwReply(src, '===== Families =====')
    local gangs = {}
    for id, g in pairs(GangsCache or {}) do gangs[#gangs + 1] = { id = id, gang = g } end
    table.sort(gangs, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
    for _, row in ipairs(gangs) do
        fwReply(src, (' gang %s | %s | name=%s | inWar=%s'):format(
            row.id, row.gang.label or '?', row.gang.name or '?', tostring(GangActiveWar and GangActiveWar[row.id] or false)
        ))
    end

    fwReply(src, '===== Zones =====')
    local zones = {}
    for id, z in pairs(ZonesCache or {}) do zones[#zones + 1] = { id = id, zone = z } end
    table.sort(zones, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
    for _, row in ipairs(zones) do
        fwReply(src, (' zone %s | %s | owner=%s(%s) | inWar=%s'):format(
            row.id, row.zone.name or '?', fwGangName(row.zone.gang_id), tostring(row.zone.gang_id),
            tostring(ZoneActiveWar and ZoneActiveWar[row.id] or false)
        ))
    end
end, false)

RegisterCommand('familywar_force', function(src, args, rawCommand)
    if not fwConsoleOrAdmin(src) then return end

    local aQuery, dQuery, zoneQuery, mode, parseErr = fwParseForceArgs(args or {}, rawCommand)
    if parseErr == 'missing' then
        fwReply(src, 'Usage: familywar_force <attackerId/name> <defenderId/name> [zoneId|auto] [now|prep]')
        fwReply(src, 'Arabic names with spaces: familywar_force اسم المهاجم | اسم المدافع | auto | now')
        fwReply(src, 'List IDs: familywar_list')
        return
    end

    if aQuery == 'auto' then
        local all = {}
        for id in pairs(GangsCache or {}) do
            if not (GangActiveWar and GangActiveWar[id]) then all[#all + 1] = id end
        end
        table.sort(all)
        if #all < 2 then return fwReply(src, 'auto failed: تحتاج عائلتين فاضيتين على الأقل') end
        aQuery = tostring(all[1])
        dQuery = tostring(all[2])
        zoneQuery = 'auto'
        mode = 'now'
    end

    local attackerGangId, _, err = fwFindGang(aQuery)
    if not attackerGangId then return fwReply(src, err) end
    local defenderGangId; defenderGangId, _, err = fwFindGang(dQuery)
    if not defenderGangId then return fwReply(src, err) end

    local zoneId; zoneId, _, err = fwFindZoneForDefender(defenderGangId, zoneQuery)
    if not zoneId then return fwReply(src, err) end

    local instant = (fwNorm(mode or 'now') ~= 'prep')
    local ok, msg = fwCreateWar(src, attackerGangId, defenderGangId, zoneId, instant)
    fwReply(src, (ok and 'OK: ' or 'FAILED: ') .. tostring(msg))
end, false)

print('[esx_families] v0.7.0c force-war console commands loaded ✓: familywar_list / familywar_force')
