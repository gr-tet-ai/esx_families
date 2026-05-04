-- ============================================================
-- esx_families v0.7.8 — War Visual CLEAN
-- Blips + entry warning + killfeed only. No DrawText/NUI war HUD here.
-- ============================================================
local WarBlips, PulseAlpha, PulseDir, LastEnterWarId = {}, 80, 1, nil
local function clearWarBlips(warId)
    local e = WarBlips[warId]; if not e then return end
    if e.main and DoesBlipExist(e.main) then RemoveBlip(e.main) end
    if e.ring and DoesBlipExist(e.ring) then RemoveBlip(e.ring) end
    WarBlips[warId] = nil
end
local function createWarBlips(warId, zone)
    if not warId or not zone then return end
    clearWarBlips(warId)
    local ring = AddBlipForRadius(zone.center_x, zone.center_y, zone.center_z, zone.radius)
    SetBlipColour(ring, 1); SetBlipAlpha(ring, 180); SetBlipHighDetail(ring, true)
    local main = AddBlipForCoord(zone.center_x, zone.center_y, zone.center_z)
    SetBlipSprite(main, 310); SetBlipColour(main, 1); SetBlipScale(main, 1.0)
    SetBlipAsShortRange(main, false); SetBlipFlashes(main, true); SetBlipFlashInterval(main, 600)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('WAR ZONE'); EndTextCommandSetBlipName(main)
    WarBlips[warId] = { main = main, ring = ring }
end
CreateThread(function()
    while true do
        if next(WarBlips) then
            PulseAlpha = PulseAlpha + (PulseDir * 12)
            if PulseAlpha >= 200 then PulseAlpha = 200; PulseDir = -1 end
            if PulseAlpha <= 80 then PulseAlpha = 80; PulseDir = 1 end
            for _, e in pairs(WarBlips) do if e.ring and DoesBlipExist(e.ring) then SetBlipAlpha(e.ring, PulseAlpha) end end
            Wait(120)
        else Wait(2000) end
    end
end)
RegisterNetEvent('esx_families:client:warStarted', function(warId, zone) createWarBlips(warId, zone) end)
RegisterNetEvent('esx_families:client:warEndedVisual', function(warId) clearWarBlips(warId); if LastEnterWarId == warId then LastEnterWarId = nil end end)
RegisterNetEvent('esx_families:client:syncActiveWars', function(list) for _, w in ipairs(list or {}) do createWarBlips(w.id, w.zone) end end)
local function getMySideForWar(war)
    local gid = MyContext and MyContext.gang and MyContext.gang.id or nil
    if not gid or not war then return 'civilian' end
    return (gid == war.attacker or gid == war.defender or gid == war.attacker_gang_id or gid == war.defender_gang_id) and 'participant' or 'thirdparty'
end
local function showEntryWarning(war, side)
    if not lib or not lib.notify then return end
    if side == 'participant' then
        lib.notify({ id='war_enter_'..war.id, title='⚔ دخلت ساحة المعركة', description='أنت داخل منطقة حرب نشطة', type='warning', duration=3500, position='top' })
    else
        lib.notify({ id='war_enter_civ_'..war.id, title='⚠ منطقة حرب عصابات', description='احذر، المنطقة تحت حرب نشطة', type='error', duration=4500, position='top' })
        AnimpostfxPlay('RaceTurbo', 600, false)
    end
end
local _origOnEnterZone = OnEnterZone
function OnEnterZone(zone)
    if _origOnEnterZone then _origOnEnterZone(zone) end
    local war = CurrentWar or (MyContext and MyContext.myWar)
    local wz = war and (war.zone or war.zone_id)
    if not zone or not war or zone.id ~= wz or LastEnterWarId == war.id then return end
    LastEnterWarId = war.id; showEntryWarning(war, getMySideForWar(war))
end
local _origOnExitZone = OnExitZone
function OnExitZone(zone) if _origOnExitZone then _origOnExitZone(zone) end; LastEnterWarId = nil end
RegisterNetEvent('esx_families:client:warKillfeed', function(data)
    if data and lib and lib.notify then
        lib.notify({ id='wkf_'..GetGameTimer(), title=('⚔ %s'):format(data.killerGang or ''), description=('%s ▶ %s (+%d)'):format(data.killer or '?', data.victim or '?', data.points or 0), type='inform', duration=3500, position='bottom-right' })
    end
end)
