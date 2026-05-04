-- ============================================================
-- qbx_families - War Admin Commands & Callbacks v0.3.0
-- /warcouncil set | /testmode on/off | /endwar | /forcewar
-- ============================================================

-- ===== Get War Council coords (يُستخدم من client wars.lua) =====
lib.callback.register('qbx_families:server:getCouncilCoords', function(source)
    local raw = GetAdminConfig('war_council_coords')
    if not raw then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if ok and decoded and decoded.x then return decoded end
    return nil
end)

-- ===== /warcouncil set — تحديد إحداثيات War Council من موقع الآدمن =====
lib.addCommand('warcouncil', {
    help = 'إدارة War Council (آدمن): set / show',
    params = { { name = 'action', type = 'string', help = 'set | show' } },
}, function(source, args)
    if not IsAdmin(source) then
        return TriggerClientEvent('ox_lib:notify', source, { type='error', description='للآدمن فقط' })
    end
    if args.action == 'set' then
        local c = GetEntityCoords(GetPlayerPed(source))
        SetAdminConfig('war_council_coords', { x = c.x, y = c.y, z = c.z })
        TriggerClientEvent('qbx_families:client:respawnCouncilPed', -1)
        TriggerClientEvent('ox_lib:notify', source, {
            type='success', title='War Council',
            description=('تم التحديث: %.2f, %.2f, %.2f'):format(c.x, c.y, c.z) })
    elseif args.action == 'show' then
        local raw = GetAdminConfig('war_council_coords')
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^3War Council', raw or 'غير محدد' } })
    end
end)

-- ===== /testmode on/off =====
lib.addCommand('testmode', {
    help = 'تفعيل/تعطيل Test Mode للحرب (آدمن)',
    params = { { name = 'state', type = 'string', help = 'on | off | status' } },
}, function(source, args)
    if not IsAdmin(source) then return end
    if args.state == 'on' then
        local ok, msg = EnableTestMode()
        TriggerClientEvent('ox_lib:notify', source, { type = ok and 'success' or 'error', description = msg })
    elseif args.state == 'off' then
        DisableTestMode()
        TriggerClientEvent('ox_lib:notify', source, { type='success', description='Test Mode مُعطّل' })
    else
        local active = IsTestMode()
        TriggerClientEvent('ox_lib:notify', source,
            { type='inform', description='Test Mode: '..(active and 'ON' or 'OFF') })
    end
end)

-- ===== /endwar <war_id> [winner_gang_id] =====
lib.addCommand('endwar', {
    help = 'إنهاء حرب قسري (آدمن)',
    params = {
        { name = 'warid', type = 'number' },
        { name = 'winnerid', type = 'number', optional = true },
    },
}, function(source, args)
    if not IsAdmin(source) then return end
    local war = ActiveWars[args.warid]
    if not war then
        return TriggerClientEvent('ox_lib:notify', source, { type='error', description='غير موجودة' })
    end
    local winner = args.winnerid or war.defender_gang_id
    EndWar(args.warid, winner, 'admin_force_end')
    TriggerClientEvent('ox_lib:notify', source, { type='success', description='تم إنهاء الحرب' })
end)

-- ===== /refundwar <war_id> =====
lib.addCommand('refundwar', {
    help = 'إلغاء حرب واسترجاع التكلفة (آدمن)',
    params = { { name = 'warid', type = 'number' } },
}, function(source, args)
    if not IsAdmin(source) then return end
    local war = ActiveWars[args.warid]
    if not war then
        return TriggerClientEvent('ox_lib:notify', source, { type='error', description='غير موجودة' })
    end
    local v = VaultsCache[war.attacker_gang_id]
    if v and (war.cost_paid or 0) > 0 then
        v.money = (v.money or 0) + war.cost_paid
        MySQL.update.await('UPDATE family_vaults SET money = ? WHERE id = ?', { v.money, v.id })
        LogVaultAction(v.id, nil, 'war_refund', nil, war.cost_paid, ('war #'..args.warid))
    end
    UnlockVault(war.attacker_gang_id)
    UnlockVault(war.defender_gang_id)
    ClearVaultSnapshot(war.defender_gang_id)
    ZoneActiveWar[war.zone_id] = nil
    GangActiveWar[war.attacker_gang_id] = nil
    GangActiveWar[war.defender_gang_id] = nil
    ActiveWars[args.warid] = nil
    MySQL.update('UPDATE family_wars SET status = ?, end_reason = ? WHERE id = ?',
        { 'refunded', 'admin_refund', args.warid })
    TriggerClientEvent('ox_lib:notify', source, { type='success', description='تم الإلغاء والاسترجاع' })
end)

-- ===== /listwars =====
lib.addCommand('listwars', { help = 'عرض الحروب النشطة (آدمن)' }, function(source)
    if not IsAdmin(source) then return end
    local lines = { '=== الحروب النشطة ===' }
    local n = 0
    for warId, war in pairs(ActiveWars) do
        n = n + 1
        local atk = (GangsCache[war.attacker_gang_id] or {}).label or '?'
        local def = (GangsCache[war.defender_gang_id] or {}).label or '?'
        local zone = (ZonesCache[war.zone_id] or {}).name or '?'
        lines[#lines+1] = ('#%d %s vs %s | %s | %s | %d-%d'):format(
            warId, atk, def, zone, war.status,
            war.scores[war.attacker_gang_id] or 0, war.scores[war.defender_gang_id] or 0)
    end
    if n == 0 then lines[#lines+1] = 'لا يوجد' end
    TriggerClientEvent('chat:addMessage', source, { args = { '^3qbx_families', table.concat(lines, '\n') } })
end)

-- ===== /attachpoints =====
lib.addCommand('attachpoints', { help = 'إعادة ربط نقاط البيع بالزونات (آدمن)' }, function(source)
    if not IsAdmin(source) then return end
    local n = 0
    for _, p in pairs(TradePointsCache) do
        AttachTradePointToZone(p)
        n = n + 1
    end
    SyncTradePointsToAll()
    TriggerClientEvent('ox_lib:notify', source, {
        type='success', description=('تم تحديث ربط %d نقطة بيع'):format(n) })
end)

-- ============================================================
-- v0.4.0: Net Events للقائمة (admin menu)
-- ============================================================

RegisterNetEvent('qbx_families:server:adminEndWar', function(warId, winnerSide)
    local src = source
    if not IsAdmin(src) then return end
    local war = ActiveWars[warId]
    if not war then
        return TriggerClientEvent('ox_lib:notify', src, { type='error', description='الحرب غير موجودة' })
    end
    local winner = (winnerSide == 'attacker') and war.attacker_gang_id or war.defender_gang_id
    EndWar(warId, winner, 'admin_force_end')
    TriggerClientEvent('ox_lib:notify', src, { type='success', description='تم إنهاء الحرب' })
end)

RegisterNetEvent('qbx_families:server:adminRefundWar', function(warId)
    local src = source
    if not IsAdmin(src) then return end
    local war = ActiveWars[warId]
    if not war then
        return TriggerClientEvent('ox_lib:notify', src, { type='error', description='الحرب غير موجودة' })
    end
    local v = VaultsCache[war.attacker_gang_id]
    if v and (war.cost_paid or 0) > 0 then
        v.money = (v.money or 0) + war.cost_paid
        MySQL.update.await('UPDATE family_vaults SET money = ? WHERE id = ?', { v.money, v.id })
        if LogVaultAction then
            LogVaultAction(v.id, nil, 'war_refund', nil, war.cost_paid, ('war #'..warId))
        end
    end
    UnlockVault(war.attacker_gang_id)
    UnlockVault(war.defender_gang_id)
    ClearVaultSnapshot(war.defender_gang_id)
    ClearVaultSnapshot(war.attacker_gang_id)
    if ZoneActiveWar then ZoneActiveWar[war.zone_id] = nil end
    if GangActiveWar then
        GangActiveWar[war.attacker_gang_id] = nil
        GangActiveWar[war.defender_gang_id] = nil
    end
    ActiveWars[warId] = nil
    MySQL.update('UPDATE family_wars SET status = ?, end_reason = ? WHERE id = ?',
        { 'refunded', 'admin_refund', warId })
    TriggerClientEvent('ox_lib:notify', src, { type='success', description='تم الإلغاء والاسترجاع' })
end)

RegisterNetEvent('qbx_families:server:adminToggleTestMode', function(state)
    local src = source
    if not IsAdmin(src) then return end
    if state == 'on' then
        if EnableTestMode then
            local ok, msg = EnableTestMode()
            TriggerClientEvent('ox_lib:notify', src, { type = ok and 'success' or 'error', description = msg })
        end
    elseif state == 'off' then
        if DisableTestMode then
            DisableTestMode()
            TriggerClientEvent('ox_lib:notify', src, { type='success', description='Test Mode معطّل' })
        end
    end
end)

-- ============================================================
-- v0.5.2: Force Declare War (آدمن)
-- يتجاوز كل القيود (cooldown, members, cost) ويبدأ حرب فوراً
-- ============================================================
lib.callback.register('qbx_families:server:adminForceDeclareWar',
function(source, attackerGangId, defenderGangId, zoneId, instantStart)
    if not IsAdmin(source) then return false, 'للآدمن فقط' end
    if not GangsCache[attackerGangId] then return false, 'العصابة المهاجمة غير موجودة' end
    if not GangsCache[defenderGangId] then return false, 'العصابة المدافعة غير موجودة' end
    if attackerGangId == defenderGangId then return false, 'نفس العصابة!' end
    if not ZonesCache[zoneId] then return false, 'الزون غير موجود' end
    if ZoneActiveWar[zoneId] then return false, 'الزون في حرب نشطة' end
    if GangActiveWar[attackerGangId] then return false, 'المهاجم في حرب نشطة' end
    if GangActiveWar[defenderGangId] then return false, 'المدافع في حرب نشطة' end

    local cfg = GetWarConfig()
    local prep = instantStart and 0 or (cfg.prep_minutes or 5)
    local startsAt = os.time() + (prep * 60)
    local endsAt   = startsAt + ((cfg.duration_minutes or 30) * 60)

    local warId = MySQL.insert.await([[
        INSERT INTO family_wars
        (attacker_gang_id, defender_gang_id, zone_id, status,
         starts_at, ends_at, cost_paid, loot_percent, is_test_mode)
        VALUES (?, ?, ?, ?, FROM_UNIXTIME(?), FROM_UNIXTIME(?), 0, ?, 1)
    ]], { attackerGangId, defenderGangId, zoneId,
          instantStart and 'active' or 'preparing',
          startsAt, endsAt, cfg.loot_percent or 30 })
    if not warId then return false, 'فشل إنشاء الحرب' end

    -- snapshot + قفل
    if SnapshotVault then SnapshotVault(defenderGangId) end
    if LockVault then LockVault(attackerGangId); LockVault(defenderGangId) end

    -- snapshot الأعضاء
    local atkM, defM = {}, {}
    for c, m in pairs(MembersCache or {}) do
        if m.gang_id == attackerGangId then atkM[#atkM+1] = c
        elseif m.gang_id == defenderGangId then defM[#defM+1] = c end
    end
    if #atkM + #defM > 0 then
        local ph, vals = {}, {}
        for _, c in ipairs(atkM) do
            ph[#ph+1]='(?,?,?)'; vals[#vals+1]=warId; vals[#vals+1]=c; vals[#vals+1]=attackerGangId
        end
        for _, c in ipairs(defM) do
            ph[#ph+1]='(?,?,?)'; vals[#vals+1]=warId; vals[#vals+1]=c; vals[#vals+1]=defenderGangId
        end
        MySQL.query.await(
            'INSERT INTO family_war_participants (war_id, citizenid, gang_id) VALUES '..table.concat(ph,','), vals)
    end

    MySQL.query.await(
        'INSERT INTO family_war_scores (war_id, gang_id) VALUES (?,?), (?,?)',
        { warId, attackerGangId, warId, defenderGangId })

    -- قفل نقاط البيع في الزون
    for _, p in pairs(TradePointsCache or {}) do
        if p.zone_id == zoneId then
            p.war_disabled = 1
            MySQL.update('UPDATE family_trade_points SET war_disabled = 1 WHERE id = ?', { p.id })
        end
    end

    local war = {
        id = warId, attacker_gang_id = attackerGangId, defender_gang_id = defenderGangId,
        zone_id = zoneId, status = instantStart and 'active' or 'preparing',
        starts_at = startsAt, ends_at = endsAt, cost_paid = 0,
        loot_percent = cfg.loot_percent or 30, is_test_mode = true,
        scores = { [attackerGangId]=0, [defenderGangId]=0 },
        kills  = { [attackerGangId]=0, [defenderGangId]=0 },
        deaths = { [attackerGangId]=0, [defenderGangId]=0 },
        presence_minutes = { [attackerGangId]=0, [defenderGangId]=0 },
        participants = {}, pending_score_writes = {},
    }
    for _, c in ipairs(atkM) do war.participants[c] = attackerGangId end
    for _, c in ipairs(defM) do war.participants[c] = defenderGangId end

    ActiveWars[warId] = war
    ZoneActiveWar[zoneId] = warId
    GangActiveWar[attackerGangId] = warId
    GangActiveWar[defenderGangId] = warId

    LogWarEvent(warId, 'admin_force_declared', nil, attackerGangId, nil, defenderGangId, 0,
        { admin_src = source, instant = instantStart })

    TriggerClientEvent('ox_lib:notify', -1, {
        type = 'warning', title = '⚔️ حرب مفروضة (آدمن)',
        description = ('%s ضد %s — زون %s%s'):format(
            GangsCache[attackerGangId].label, GangsCache[defenderGangId].label,
            ZonesCache[zoneId].name, instantStart and ' | بدأت الآن!' or ' | تحضير '..prep..'د'),
        duration = 12000,
    })

    -- broadcast + ابدأ tick thread
    TriggerClientEvent('qbx_families:client:warUpdate', -1, {
        id = war.id, attacker = attackerGangId, defender = defenderGangId,
        zone = zoneId, status = war.status, starts_at = startsAt, ends_at = endsAt,
        scores = war.scores,
    })
    if EnsureWarTickThread then EnsureWarTickThread() end

    return true, ('تم — Wars #%d'):format(warId)
end)

-- قائمة العائلات (للأدمن — اختيار في force-war flow)
lib.callback.register('qbx_families:server:adminListGangsForWar', function(source)
    if not IsAdmin(source) then return {} end
    local list = {}
    for id, g in pairs(GangsCache) do
        list[#list+1] = { id = id, label = g.label, name = g.name,
            in_war = GangActiveWar[id] ~= nil }
    end
    table.sort(list, function(a,b) return a.label < b.label end)
    return list
end)

-- قائمة الزونات (للأدمن — اختيار في force-war flow)
lib.callback.register('qbx_families:server:adminListZonesForWar', function(source)
    if not IsAdmin(source) then return {} end
    local list = {}
    for id, z in pairs(ZonesCache) do
        list[#list+1] = { id = id, name = z.name, gang_id = z.gang_id,
            gang_label = (GangsCache[z.gang_id] or {}).label,
            in_war = ZoneActiveWar[id] ~= nil }
    end
    table.sort(list, function(a,b) return a.name < b.name end)
    return list
end)

RegisterNetEvent('qbx_families:server:adminSetWarCouncil', function()
    local src = source
    if not IsAdmin(src) then return end
    local c = GetEntityCoords(GetPlayerPed(src))
    if SetAdminConfig then
        SetAdminConfig('war_council_coords', { x = c.x, y = c.y, z = c.z })
        TriggerClientEvent('qbx_families:client:respawnCouncilPed', -1)
        TriggerClientEvent('ox_lib:notify', src, {
            type='success', title='War Council',
            description=('تم التحديث: %.2f, %.2f, %.2f'):format(c.x, c.y, c.z) })
    else
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='SetAdminConfig غير متاح' })
    end
end)
