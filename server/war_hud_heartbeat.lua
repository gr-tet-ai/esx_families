-- ============================================================
-- esx_families v0.7.12 — War HUD Heartbeat + instant push
-- Sends authoritative snapshots to war participants only.
-- ============================================================
local TICK_MS, TAG = 500, '[esx_families:warhud]'
local LastSentWarId = {}

local function safeGangs() return _G.GangsCache or _G.Gangs or {} end
local function safeZones() return _G.ZonesCache or _G.Zones or {} end
local function safeWars() return _G.ActiveWars or _G.WarsCache or _G.Wars or {} end

local function scoreOf(scores, id)
    return tonumber(scores and (scores[id] or scores[tostring(id)])) or 0
end

local function addSrc(out, seen, src)
    src = tonumber(src)
    if src and src > 0 and not seen[src] then
        seen[src] = true
        out[#out + 1] = src
    end
end

local function playerSourceFromBridgePlayer(p)
    if not p then return nil end
    if type(p) == 'number' then return p end
    if p.PlayerData and p.PlayerData.source then return p.PlayerData.source end
    if p.source then return p.source end
    return nil
end

local function getOnlineWarMembers(war, gangId)
    local out, seen = {}, {}
    gangId = tonumber(gangId)
    if not war or not gangId then return out end

    if war.participants and ESXBridge and ESXBridge.GetPlayerByCitizenId then
        for cid, gid in pairs(war.participants) do
            if tonumber(gid) == gangId then
                addSrc(out, seen, playerSourceFromBridgePlayer(ESXBridge.GetPlayerByCitizenId(cid)))
            end
        end
    end

    if MembersCache and ESXBridge and ESXBridge.GetPlayerByCitizenId then
        for cid, m in pairs(MembersCache) do
            if tonumber(m.gang_id) == gangId then
                addSrc(out, seen, playerSourceFromBridgePlayer(ESXBridge.GetPlayerByCitizenId(cid)))
            end
        end
    end

    if #out == 0 and ESX and ESX.GetExtendedPlayers then
        for _, xp in ipairs(ESX.GetExtendedPlayers()) do
            local meta = xp.getMeta and xp.getMeta('esx_families') or nil
            if meta and tonumber(meta.gang_id) == gangId then addSrc(out, seen, xp.source) end
        end
    end

    return out
end

local function cloneSnap(snap, side)
    local c = {}
    for k, v in pairs(snap) do c[k] = v end
    c.my_side = side
    return c
end

local function buildSnapshot(w)
    if not w or (w.status ~= 'active' and w.status ~= 'overtime' and w.status ~= 'preparing') then return nil end

    local gangs, zones = safeGangs(), safeZones()
    local atk = gangs[w.attacker_gang_id] or {}
    local def = gangs[w.defender_gang_id] or {}
    local zone = zones[w.zone_id] or {}

    w._hud_seq = (tonumber(w._hud_seq) or 0) + 1

    return {
        war_id = w.id,
        hud_seq = w._hud_seq,
        status = w.status,
        attacker_id = w.attacker_gang_id,
        defender_id = w.defender_gang_id,
        zone_id = w.zone_id,
        zone_name = zone.name or '?',
        attacker_label = atk.label or '?',
        defender_label = def.label or '?',
        attacker_score = scoreOf(w.scores, w.attacker_gang_id),
        defender_score = scoreOf(w.scores, w.defender_gang_id),
        starts_at = w.starts_at or 0,
        ends_at = w.ends_at or 0,
        server_now = os.time(),
        server_ms = GetGameTimer(),
    }
end

local function sendSnapshotToParticipants(war, snap)
    local active = {}
    for _, src in ipairs(getOnlineWarMembers(war, war.attacker_gang_id)) do
        TriggerClientEvent('esx_families:warHud:tick', src, cloneSnap(snap, 'attacker'))
        active[src] = war.id
    end
    for _, src in ipairs(getOnlineWarMembers(war, war.defender_gang_id)) do
        TriggerClientEvent('esx_families:warHud:tick', src, cloneSnap(snap, 'defender'))
        active[src] = war.id
    end
    return active
end

function _G.PushWarHudNow(war)
    local snap = buildSnapshot(war)
    if not snap then return end
    sendSnapshotToParticipants(war, snap)
end

CreateThread(function()
    Wait(3000)
    print(('%s heartbeat started (%dms tick) v0.7.12 single-source'):format(TAG, TICK_MS))
    while true do
        local active = {}
        for _, war in pairs(safeWars()) do
            local snap = buildSnapshot(war)
            if snap then
                local sent = sendSnapshotToParticipants(war, snap)
                for src, wid in pairs(sent) do active[src] = wid end
            end
        end
        for src, wid in pairs(LastSentWarId) do
            if active[src] ~= wid then TriggerClientEvent('esx_families:warHud:end', src, wid) end
        end
        LastSentWarId = active
        Wait(TICK_MS)
    end
end)

AddEventHandler('playerDropped', function()
    LastSentWarId[source] = nil
end)

print('[esx_families:warhud] v0.7.12 PushWarHudNow ready')
