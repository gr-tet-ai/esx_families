-- ============================================================
-- أوامر الآدمن: إنشاء عصابة + زون + خزنة
-- ============================================================

-- /creategang <name> <label> <leader_citizenid> [blip_color]
lib.addCommand('creategang', {
    help = 'إنشاء عصابة جديدة (آدمن)',
    params = {
        { name = 'name',     type = 'string', help = 'الاسم البرمجي (انجليزي بدون مسافات) مثل: lacosa' },
        { name = 'label',    type = 'string', help = 'الاسم الظاهر مثل: La Cosa Nostra' },
        { name = 'leaderid', type = 'string', help = 'CitizenID للقائد' },
        { name = 'color',    type = 'number', help = 'لون البليب (افتراضي 1)', optional = true },
    },
    restricted = false,
}, function(source, args)
    if not IsAdmin(source) then
        return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'هذا الأمر للآدمن فقط' })
    end

    local name, label, leaderId = args.name, args.label, args.leaderid
    local color = args.color or 1

    local exists = MySQL.scalar.await('SELECT id FROM family_gangs WHERE name = ?', { name })
    if exists then
        return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'اسم العصابة موجود مسبقاً' })
    end

    local id = MySQL.insert.await(
        'INSERT INTO family_gangs (name, label, leader_citizenid, blip_color) VALUES (?, ?, ?, ?)',
        { name, label, leaderId, color }
    )
    if not id then
        return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'فشل الإنشاء' })
    end

    GangsCache[id] = { id = id, name = name, label = label, leader_citizenid = leaderId, blip_color = color }

    -- v0.6.1: إنشاء الرتب الافتراضية + إدخال القائد كعضو Boss تلقائياً (الجذر #1)
    if CreateDefaultRanksForGang then
        CreateDefaultRanksForGang(id, leaderId)
    end

    TriggerClientEvent('ox_lib:notify', source,
        { type = 'success', description = ('تم إنشاء عصابة %s (ID: %d) | القائد: %s | + رتب افتراضية'):format(label, id, leaderId) })
end)

-- /createzone <gang_id> <name> <radius> <protection%>
-- يستخدم موقع اللاعب الحالي كمركز للزون
lib.addCommand('createzone', {
    help = 'إنشاء زون عند موقعك الحالي (آدمن)',
    params = {
        { name = 'gangid',     type = 'number', help = 'ID العصابة المالكة' },
        { name = 'zonename',   type = 'string', help = 'اسم الزون' },
        { name = 'radius',     type = 'number', help = 'الشعاع (متر) مثل 80' },
        { name = 'protection', type = 'number', help = 'نسبة الحماية % (1-30)' },
    },
}, function(source, args)
    if not IsAdmin(source) then
        return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'للآدمن فقط' })
    end

    local gang = GangsCache[args.gangid]
    if not gang then
        return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'العصابة غير موجودة' })
    end

    local prot = math.max(Config.MinProtectionPercent, math.min(Config.MaxProtectionPercent, args.protection))

    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)

    local id = MySQL.insert.await(
        'INSERT INTO family_zones (name, gang_id, center_x, center_y, center_z, radius, protection_percent) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { args.zonename, args.gangid, coords.x, coords.y, coords.z, args.radius, prot }
    )
    if not id then
        return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'فشل الإنشاء' })
    end

    ZonesCache[id] = {
        id = id, name = args.zonename, gang_id = args.gangid,
        center_x = coords.x, center_y = coords.y, center_z = coords.z,
        radius = args.radius, protection_percent = prot,
    }
    SyncZonesToAll()
    TriggerClientEvent('ox_lib:notify', source,
        { type = 'success', description = ('تم إنشاء زون %s لعصابة %s | حماية %.1f%%'):format(args.zonename, gang.label, prot) })
end)

-- /deletezone <zone_id>
lib.addCommand('deletezone', {
    help = 'حذف زون',
    params = { { name = 'zoneid', type = 'number' } },
}, function(source, args)
    if not IsAdmin(source) then return end
    if not ZonesCache[args.zoneid] then
        return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'الزون غير موجود' })
    end
    MySQL.query.await('DELETE FROM family_zones WHERE id = ?', { args.zoneid })
    ZonesCache[args.zoneid] = nil
    SyncZonesToAll()
    TriggerClientEvent('ox_lib:notify', source, { type = 'success', description = 'تم حذف الزون' })
end)

-- /createvault <gang_id>
-- ينشئ خزنة عند موقع اللاعب الحالي (داخل بيت القائد)
lib.addCommand('createvault', {
    help = 'إنشاء خزنة عند موقعك (آدمن - داخل بيت القائد)',
    params = { { name = 'gangid', type = 'number' } },
}, function(source, args)
    if not IsAdmin(source) then return end

    local gang = GangsCache[args.gangid]
    if not gang then
        return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'العصابة غير موجودة' })
    end

    if VaultsCache[args.gangid] then
        return TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'هذه العصابة عندها خزنة بالفعل' })
    end

    local coords = GetEntityCoords(GetPlayerPed(source))
    local id = MySQL.insert.await(
        'INSERT INTO family_vaults (gang_id, coords_x, coords_y, coords_z) VALUES (?, ?, ?, ?)',
        { args.gangid, coords.x, coords.y, coords.z }
    )
    if not id then return end

    VaultsCache[args.gangid] = {
        id = id, gang_id = args.gangid,
        coords_x = coords.x, coords_y = coords.y, coords_z = coords.z, money = 0,
    }
    VaultKeysCache[id] = {}

    -- إرسال إحداثيات الخزنة لصاحب البيت (القائد) فقط - نبثها للجميع لكن الكلاينت يفلتر
    TriggerClientEvent('qbx_families:client:vaultCreated', -1, VaultsCache[args.gangid], gang)
    TriggerClientEvent('ox_lib:notify', source,
        { type = 'success', description = ('تم إنشاء خزنة عصابة %s'):format(gang.label) })
end)

-- /listgangs
lib.addCommand('listgangs', { help = 'عرض كل العصابات' }, function(source)
    if not IsAdmin(source) then return end
    local lines = { '=== العصابات ===' }
    for id, g in pairs(GangsCache) do
        table.insert(lines, ('ID: %d | %s (%s) | قائد: %s'):format(id, g.label, g.name, g.leader_citizenid))
    end
    TriggerClientEvent('chat:addMessage', source, { args = { '^3qbx_families', table.concat(lines, '\n') } })
end)
