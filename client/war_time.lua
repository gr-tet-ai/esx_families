-- ============================================================
-- esx_families — client safe unix time
-- السبب: FiveM client قد لا يوفّر os.time()، وهذا يكسر HUD الحرب.
-- ============================================================

FamilyTimeOffset = FamilyTimeOffset or 0

function FamilyUnixTime()
    if type(GetCloudTimeAsInt) == 'function' then
        local ok, t = pcall(GetCloudTimeAsInt)
        t = tonumber(t)
        if ok and t and t > 1000000000 then
            return math.floor(t)
        end
    end

    local gameSeconds = 0
    if type(GetGameTimer) == 'function' then
        gameSeconds = math.floor((GetGameTimer() or 0) / 1000)
    end

    if FamilyTimeOffset and FamilyTimeOffset > 1000000000 then
        return gameSeconds + FamilyTimeOffset
    end

    return gameSeconds
end

RegisterNetEvent('esx_families:client:timeSync', function(serverNow)
    serverNow = tonumber(serverNow)
    if not serverNow or serverNow < 1000000000 or type(GetGameTimer) ~= 'function' then return end
    FamilyTimeOffset = math.floor(serverNow - math.floor((GetGameTimer() or 0) / 1000))
end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('esx_families:server:requestTimeSync')
    while true do
        Wait(60000)
        TriggerServerEvent('esx_families:server:requestTimeSync')
    end
end)
