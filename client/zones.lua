-- ============================================================
-- Blips + كشف الدخول/الخروج من الزون v0.3.0
-- مُحسَّن: spatial grid في الكلاينت أيضاً (O(1) lookup)
-- + adaptive sleep (idle 2s, active 250ms)
-- ============================================================

ClientGlowBlips = ClientGlowBlips or {}

function RebuildBlips()
    -- مسح القديم
    for _, b in pairs(ClientBlips)       do RemoveBlip(b) end
    for _, b in pairs(ClientRadiusBlips) do RemoveBlip(b) end
    for _, b in pairs(ClientGlowBlips)   do RemoveBlip(b) end
    ClientBlips, ClientRadiusBlips, ClientGlowBlips = {}, {}, {}

    for id, z in pairs(ClientZones) do
        local gang = ClientGangs[z.gang_id]
        local color = gang and gang.blip_color or 1

        local b = AddBlipForCoord(z.center_x, z.center_y, z.center_z)
        SetBlipSprite(b, Config.BlipSettings.sprite)
        SetBlipDisplay(b, Config.BlipSettings.display)
        SetBlipScale(b, Config.BlipSettings.scale)
        SetBlipColour(b, color)
        SetBlipAlpha(b, Config.BlipSettings.alpha)
        SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(('%s - %s'):format(z.name, gang and gang.label or '?'))
        EndTextCommandSetBlipName(b)
        ClientBlips[id] = b

        local rb = AddBlipForRadius(z.center_x, z.center_y, z.center_z, z.radius)
        SetBlipColour(rb, Config.RadiusBlip.color or 1)
        SetBlipAlpha(rb, Config.RadiusBlip.alpha or 140)
        if Config.RadiusBlip.highDetail then SetBlipHighDetail(rb, true) end
        if Config.RadiusBlip.flashes then
            SetBlipFlashes(rb, true)
            SetBlipFlashInterval(rb, Config.RadiusBlip.flashInterval or 600)
        end
        ClientRadiusBlips[id] = rb

        local gb = AddBlipForRadius(z.center_x, z.center_y, z.center_z, z.radius * 0.55)
        SetBlipColour(gb, 1); SetBlipAlpha(gb, 180); SetBlipHighDetail(gb, true)
        SetBlipFlashes(gb, true); SetBlipFlashInterval(gb, 900)
        ClientGlowBlips[id] = gb
    end

    -- بناء spatial grid في الكلاينت
    Shared.RebuildSpatialGrid(ClientZones)
end

-- فحص دخول/خروج الزون (adaptive sleep)
CreateThread(function()
    local activeSleep = (Config.Performance and Config.Performance.clientActiveSleep) or 250
    local idleSleep   = (Config.Performance and Config.Performance.clientIdleSleep) or 2000
    while true do
        local sleep = CurrentZone and activeSleep or idleSleep
        Wait(sleep)
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        -- O(1) عبر grid
        local foundZone = Shared.FindZoneAt(coords.x, coords.y, ClientZones)

        if foundZone and (not CurrentZone or CurrentZone.id ~= foundZone.id) then
            CurrentZone = foundZone
            OnEnterZone(foundZone)
        elseif not foundZone and CurrentZone then
            OnExitZone(CurrentZone)
            CurrentZone = nil
        end
    end
end)

function OnEnterZone(zone)
    local gang = ClientGangs[zone.gang_id]
    local label = gang and gang.label or 'مجهولة'
    local now = GetGameTimer()
    local last = LastZoneNotify[zone.id] or 0

    if now - last >= (Config.ZoneNotifyCooldown * 1000) then
        LastZoneNotify[zone.id] = now
        lib.notify({
            id = 'zone_enter_' .. zone.id,
            title = 'دخلت منطقة عصابة ' .. label,
            description = 'منطقة خطرة | نسبة الحماية ' .. string.format('%.1f', zone.protection_percent) .. '٪',
            type = 'warning', duration = 6000, position = 'top',
            icon = 'triangle-exclamation', iconColor = '#ff3b3b',
        })
    end
end

function OnExitZone(zone)
    local gang = ClientGangs[zone.gang_id]
    local label = gang and gang.label or '?'
    lib.notify({
        title = 'غادرت منطقة عصابة ' .. label,
        description = 'أنت الآن خارج منطقة الخطر',
        type = 'inform', duration = 3000, position = 'top',
        icon = 'circle-check', iconColor = '#22c55e',
    })
end
