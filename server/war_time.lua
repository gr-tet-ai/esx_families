-- ============================================================
-- esx_families — server time sync for client HUD timers
-- ============================================================

RegisterNetEvent('esx_families:server:requestTimeSync', function()
    local src = source
    TriggerClientEvent('esx_families:client:timeSync', src, os.time())
end)
