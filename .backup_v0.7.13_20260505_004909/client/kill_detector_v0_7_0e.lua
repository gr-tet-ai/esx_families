-- ============================================================
-- esx_families v0.7.0e — HARD Kill Detector
-- Path E = gameEventTriggered + death polling fallback
-- ============================================================
local VERSION = 'v0.7.0e'
local lastSent = {}
local wasDead = false
local lastProbeAt = 0

local function dbg(msg)
    if GetConvarInt('esx_families_killdebug', 0) == 1 then
        print(('[esx_families:%s][client] %s'):format(VERSION, tostring(msg)))
    end
end

local function nowMs()
    return GetGameTimer()
end

local function playerIndexFromPed(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local idx = NetworkGetPlayerIndexFromPed(ped)
    if idx and idx >= 0 then return idx end

    for _, player in ipairs(GetActivePlayers()) do
        if GetPlayerPed(player) == ped then
            return player
        end
    end
    return nil
end

local function serverIdFromPed(ped)
    local idx = playerIndexFromPed(ped)
    if not idx then return nil end
    local sid = GetPlayerServerId(idx)
    if sid and sid > 0 then return sid end
    return nil
end

local function attackerServerIdFromEntity(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end

    if IsEntityAPed(ent) then
        if IsPedAPlayer(ent) then
            return serverIdFromPed(ent)
        end
        return nil
    end

    if IsEntityAVehicle(ent) then
        local driver = GetPedInVehicleSeat(ent, -1)
        if driver and driver ~= 0 and IsPedAPlayer(driver) then
            return serverIdFromPed(driver)
        end
    end

    return nil
end

local function weaponFromArgs(args)
    if type(args) == 'table' then
        for i = 3, 13 do
            local v = args[i]
            if type(v) == 'number' and v ~= 0 then
                -- weapon hash غالباً رقم كبير؛ لو غلط ما يضر التسجيل
                if math.abs(v) > 1000 then return v end
            end
        end
    end
    local ped = PlayerPedId()
    if ped and ped ~= 0 then
        local cause = GetPedCauseOfDeath(ped)
        if cause and cause ~= 0 then return cause end
    end
    return 0
end

local function fatalFlag(args)
    if type(args) ~= 'table' then return false end
    -- FiveM غيّر ترتيب CEventNetworkEntityDamage بين artifacts/gamebuilds.
    -- نفحص أكثر من index بدل الاعتماد على args[6] فقط.
    for _, i in ipairs({4, 5, 6, 9, 10, 11, 12}) do
        local v = args[i]
        if v == true or v == 1 then return true end
    end
    return false
end

local function sendKill(attackerSrc, weapon, detector, extra)
    local victimSrc = GetPlayerServerId(PlayerId())
    attackerSrc = tonumber(attackerSrc)
    if not victimSrc or victimSrc <= 0 then return end

    local t = nowMs()
    local key = tostring(attackerSrc or 'nil') .. ':' .. tostring(weapon or 0) .. ':' .. tostring(detector or '?')
    if lastSent[key] and (t - lastSent[key]) < 1500 then return end
    lastSent[key] = t

    dbg(('send detector=%s attacker=%s victim=%s weapon=%s'):format(detector, tostring(attackerSrc), tostring(victimSrc), tostring(weapon)))

    TriggerServerEvent('__qbx_families_internal:clientKillReportV2', {
        attackerSrc = attackerSrc,
        weapon = weapon or 0,
        detector = detector or 'unknown',
        version = VERSION,
        extra = extra or '',
        ts = t,
    })
end

local function reportFromCurrentDeath(detector, args, attackerEnt)
    local ped = PlayerPedId()
    if not ped or ped == 0 then return end

    local attackerSrc = attackerServerIdFromEntity(attackerEnt)
    if not attackerSrc then
        local killerEnt = GetPedSourceOfDeath(ped)
        attackerSrc = attackerServerIdFromEntity(killerEnt)
        attackerEnt = killerEnt
    end

    local weapon = weaponFromArgs(args)
    sendKill(attackerSrc, weapon, detector, ('attackerEnt=%s'):format(tostring(attackerEnt)))
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    if type(args) ~= 'table' then return end

    local victimEnt = args[1]
    local attackerEnt = args[2]
    local ped = PlayerPedId()

    if not victimEnt or victimEnt == 0 or victimEnt ~= ped then return end

    -- لا نعتمد على flag فقط؛ أحياناً الـ ped يصير dead بعد frame أو frameين.
    if fatalFlag(args) or IsEntityDead(ped) or IsPedFatallyInjured(ped) then
        SetTimeout(0, function()
            reportFromCurrentDeath('gameEvent', args, attackerEnt)
        end)
        SetTimeout(250, function()
            if IsEntityDead(PlayerPedId()) or IsPedFatallyInjured(PlayerPedId()) then
                reportFromCurrentDeath('gameEvent+250ms', args, attackerEnt)
            end
        end)
    end
end)

CreateThread(function()
    while true do
        Wait(250)
        local ped = PlayerPedId()
        if ped and ped ~= 0 then
            local dead = IsEntityDead(ped) or IsPedFatallyInjured(ped)
            if dead and not wasDead then
                wasDead = true
                SetTimeout(150, function()
                    reportFromCurrentDeath('pollingDeath', nil, GetPedSourceOfDeath(PlayerPedId()))
                end)
            elseif not dead and wasDead then
                wasDead = false
            end
        end
    end
end)

RegisterNetEvent('__qbx_families_internal:killProbe', function(token)
    lastProbeAt = nowMs()
    local ped = PlayerPedId()
    local coords = ped and ped ~= 0 and GetEntityCoords(ped) or vector3(0, 0, 0)
    TriggerServerEvent('__qbx_families_internal:killProbePong', {
        token = token,
        version = VERSION,
        serverId = GetPlayerServerId(PlayerId()),
        dead = ped and ped ~= 0 and (IsEntityDead(ped) or IsPedFatallyInjured(ped)) or false,
        x = coords.x,
        y = coords.y,
        z = coords.z,
    })
end)

RegisterCommand('familywar_clientdiag', function()
    local ped = PlayerPedId()
    print(('======== esx_families %s clientdiag ========'):format(VERSION))
    print(('serverId=%s ped=%s dead=%s lastProbeAt=%s'):format(
        tostring(GetPlayerServerId(PlayerId())),
        tostring(ped),
        tostring(ped and ped ~= 0 and (IsEntityDead(ped) or IsPedFatallyInjured(ped)) or false),
        tostring(lastProbeAt)
    ))
    print('===========================================')
end, false)

CreateThread(function()
    Wait(2000)
    print(('[esx_families] %s HARD kill detector loaded ✓'):format(VERSION))
end)
