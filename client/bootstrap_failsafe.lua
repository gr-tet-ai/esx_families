-- ============================================================
-- esx_families — ESX bootstrap failsafe
-- يعالج حالة أن LocalPlayer.state.isLoggedIn لا تتغير في ESX Legacy.
-- ============================================================

local booting = false

local function SafeBootRefresh(reason)
    if booting then return end
    booting = true
    CreateThread(function()
        Wait(1200)
        for _ = 1, 6 do
            pcall(function() TriggerServerEvent('qbx_families:server:requestZones') end)
            Wait(150)
            pcall(function() TriggerServerEvent('qbx_families:server:requestVaults') end)
            Wait(150)
            pcall(function() TriggerServerEvent('qbx_families:server:requestTradePoints') end)
            Wait(150)
            pcall(function() TriggerServerEvent('esx_families:server:requestRecruitmentPoints') end)
            Wait(250)
            if type(RefreshMyContext) == 'function' then
                pcall(RefreshMyContext)
            end
            if MyContext ~= nil then break end
            Wait(2500)
        end
        booting = false
    end)
end

RegisterNetEvent('esx:playerLoaded', function()
    SafeBootRefresh('esx:playerLoaded')
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == GetCurrentResourceName() then
        SafeBootRefresh('resourceStart')
    end
end)

CreateThread(function()
    Wait(6000)
    if MyContext == nil then
        SafeBootRefresh('lateFallback')
    end
end)
