-- ============================================================
-- esx_families v0.7.13 — ATTACKER-SIDE Kill Detector
-- يطلق لحظياً من جهة القاتل بدون انتظار animation وفاة الضحية
-- ============================================================
local VERSION = 'v0.7.13-atk'
local lastSent = {}

local function nowMs() return GetGameTimer() end

local function isFatalArgs(args)
    if type(args) ~= 'table' then return false end
    for _, i in ipairs({4, 5, 6, 9, 10, 11, 12}) do
        local v = args[i]
        if v == true or v == 1 then return true end
    end
    return false
end

local function victimSrcFromEntity(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    if not IsEntityAPed(ent) or not IsPedAPlayer(ent) then return nil end
    local idx = NetworkGetPlayerIndexFromPed(ent)
    if not idx or idx < 0 then
        for _, p in ipairs(GetActivePlayers()) do
            if GetPlayerPed(p) == ent then idx = p; break end
        end
    end
    if not idx or idx < 0 then return nil end
    local sid = GetPlayerServerId(idx)
    if not sid or sid <= 0 then return nil end
    return sid
end

local function sendAttackerKill(victimSrc, weapon)
    local me = GetPlayerServerId(PlayerId())
    if not me or me <= 0 or not victimSrc or victimSrc <= 0 or me == victimSrc then return end
    local key = tostring(victimSrc)
    local t = nowMs()
    if lastSent[key] and (t - lastSent[key]) < 1500 then return end
    lastSent[key] = t
    -- نفس الحدث الذي يستقبله السيرفر من القاتل (server/wars.lua:700)
    TriggerServerEvent('qbx_families:server:reportKill', me, victimSrc, 'client-attacker-instant')
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    if type(args) ~= 'table' then return end
    local victimEnt   = args[1]
    local attackerEnt = args[2]
    local myPed       = PlayerPedId()
    if not attackerEnt or attackerEnt == 0 then return end
    -- لازم أكون أنا المهاجم (إما ped مباشرة أو سائق مركبة)
    local iAmAttacker = false
    if attackerEnt == myPed then
        iAmAttacker = true
    elseif IsEntityAVehicle and IsEntityAVehicle(attackerEnt) then
        local drv = GetPedInVehicleSeat(attackerEnt, -1)
        if drv == myPed then iAmAttacker = true end
    end
    if not iAmAttacker then return end
    if not victimEnt or victimEnt == 0 or victimEnt == myPed then return end
    if not isFatalArgs(args) then return end
    local victimSrc = victimSrcFromEntity(victimEnt)
    if not victimSrc then return end
    local weapon = 0
    for i = 3, 13 do
        local v = args[i]
        if type(v) == 'number' and math.abs(v) > 1000 then weapon = v; break end
    end
    sendAttackerKill(victimSrc, weapon)
end)

CreateThread(function()
    Wait(2500)
    print(('[esx_families] %s ATTACKER-side kill detector loaded ✓'):format(VERSION))
end)
