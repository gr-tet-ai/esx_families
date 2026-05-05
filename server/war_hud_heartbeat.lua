-- ============================================================
-- esx_families v0.7.8 — War HUD Heartbeat (single source)
-- ============================================================
local TICK_MS, TAG = 1000, '[esx_families:warhud]'
local LastSentWarId = {}
local function safeGangs() return _G.GangsCache or _G.Gangs or {} end
local function safeZones() return _G.ZonesCache or _G.Zones or {} end
local function safeWars() return _G.ActiveWars or _G.WarsCache or _G.Wars or {} end
local function getOnlineGangMembers(gangId)
    local out = {}
    if not gangId then return out end
    if MembersCache and ESXBridge and ESXBridge.GetPlayerByCitizenId then
        for cid, m in pairs(MembersCache) do
            if tonumber(m.gang_id) == tonumber(gangId) then
                local p = ESXBridge.GetPlayerByCitizenId(cid)
                if p and p.PlayerData and p.PlayerData.source then out[#out+1] = p.PlayerData.source end
            end
        end
    end
    if #out == 0 and ESX and ESX.GetExtendedPlayers then
        for _, xp in ipairs(ESX.GetExtendedPlayers()) do
            local meta = xp.getMeta and xp.getMeta('esx_families') or nil
            if meta and tonumber(meta.gang_id) == tonumber(gangId) then out[#out+1] = xp.source end
        end
    end
    return out
end
local function scoreOf(scores, id) return tonumber(scores and (scores[id] or scores[tostring(id)])) or 0 end
local function buildSnapshot(w)
    if not w or w.status ~= 'active' then return nil end
    local gangs, zones = safeGangs(), safeZones()
    local atk, def, zone = gangs[w.attacker_gang_id] or {}, gangs[w.defender_gang_id] or {}, zones[w.zone_id] or {}
    return { war_id=w.id, status=w.status, attacker_id=w.attacker_gang_id, defender_id=w.defender_gang_id, zone_id=w.zone_id, zone_name=zone.name or '?', attacker_label=atk.label or '?', defender_label=def.label or '?', attacker_score=scoreOf(w.scores, w.attacker_gang_id), defender_score=scoreOf(w.scores, w.defender_gang_id), starts_at=w.starts_at or 0, ends_at=w.ends_at or 0, server_now=os.time() }
end
CreateThread(function()
    Wait(3000); print(('%s heartbeat started (%dms tick) v0.7.8'):format(TAG, TICK_MS))
    while true do
        local active = {}
        for _, w in pairs(safeWars()) do
            local snap = buildSnapshot(w)
            if snap then
                for _, src in ipairs(getOnlineGangMembers(w.attacker_gang_id)) do snap.my_side='attacker'; TriggerClientEvent('esx_families:warHud:tick', src, snap); active[src]=w.id end
                for _, src in ipairs(getOnlineGangMembers(w.defender_gang_id)) do snap.my_side='defender'; TriggerClientEvent('esx_families:warHud:tick', src, snap); active[src]=w.id end
            end
        end
        for src, wid in pairs(LastSentWarId) do if active[src] ~= wid then TriggerClientEvent('esx_families:warHud:end', src, wid) end end
        LastSentWarId = active
        Wait(TICK_MS)
    end
end)
AddEventHandler('playerDropped', function() LastSentWarId[source] = nil end)

-- v0.7.11: instant push helper
function _G.PushWarHudNow(war)
    if not war or war.status ~= 'active' then return end
    local gangs = _G.GangsCache or _G.Gangs or {}
    local zones = _G.ZonesCache or _G.Zones or {}
    local atk, def, zone = gangs[war.attacker_gang_id] or {}, gangs[war.defender_gang_id] or {}, zones[war.zone_id] or {}
    local function sc(s,id) return tonumber(s and (s[id] or s[tostring(id)])) or 0 end
    local snap = {
        war_id=war.id, status=war.status,
        attacker_id=war.attacker_gang_id, defender_id=war.defender_gang_id,
        zone_id=war.zone_id, zone_name=zone.name or '?',
        attacker_label=atk.label or '?', defender_label=def.label or '?',
        attacker_score=sc(war.scores, war.attacker_gang_id),
        defender_score=sc(war.scores, war.defender_gang_id),
        starts_at=war.starts_at or 0, ends_at=war.ends_at or 0,
        server_now=os.time(), server_ms=GetGameTimer(),  -- v0.7.11b: ms للترتيب الدقيق
    }
    for _, pid in ipairs(GetPlayers()) do
        TriggerClientEvent('esx_families:warHud:tick', tonumber(pid), snap)
    end
end
print('[esx_families:warhud] v0.7.11 PushWarHudNow ready')
