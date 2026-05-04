-- ============================================================
-- HUD ثابت داخل الزون (NUI Custom — يدعم العربية)
-- ============================================================

local hudVisible = false
local hudData = nil

local function showHUD(label, percent)
    SendNUIMessage({
        action = 'zoneHud:show',
        label = label,
        percent = percent,
    })
    hudVisible = true
    hudData = { label = label, percent = percent }
end

local function hideHUD()
    if hudVisible then
        SendNUIMessage({ action = 'zoneHud:hide' })
        hudVisible = false
        hudData = nil
    end
end

CreateThread(function()
    while true do
        if CurrentZone then
            local gang = ClientGangs[CurrentZone.gang_id]
            local label = gang and gang.label or '?'
            local percent = CurrentZone.protection_percent or 0

            if not hudVisible
                or not hudData
                or hudData.label ~= label
                or hudData.percent ~= percent then
                showHUD(label, percent)
            end
            Wait(1000)
        else
            hideHUD()
            Wait(500)
        end
    end
end)

-- لو خرج من السيرفر فجأة
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then hideHUD() end
end)
