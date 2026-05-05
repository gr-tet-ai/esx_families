-- ============================================================
-- esx_families v0.7.12 — War HUD Sync Bridge
-- Single source: NUI conquest/topbar only. No DrawRect/DrawText renderer here.
-- ============================================================
local LastWarId, LastAtkScore, LastDefScore, LastSeq = nil, nil, nil, 0

local function num(v, fallback)
    local n = tonumber(v)
    if n == nil then return fallback or 0 end
    return n
end

local function fmtTime(sec)
    sec = math.max(0, math.floor(num(sec, 0)))
    return ('%02d:%02d'):format(math.floor(sec / 60), sec % 60)
end

local function sameWar(a, b)
    return tostring(a or '') == tostring(b or '')
end

local function applySnapToContext(snap)
    if not MyContext or not MyContext.gang then return false end

    local myGid = num(MyContext.gang.id, -1)
    local atkId = num(snap.attacker_id, -2)
    local defId = num(snap.defender_id, -3)
    if myGid ~= atkId and myGid ~= defId then return false end

    MyContext.myWar = MyContext.myWar or {}
    MyContext.myWar.id = snap.war_id
    MyContext.myWar.status = snap.status or 'active'
    MyContext.myWar.attacker = atkId
    MyContext.myWar.defender = defId
    MyContext.myWar.attacker_score = snap.attacker_score
    MyContext.myWar.defender_score = snap.defender_score
    MyContext.myWar.scores = {
        [atkId] = snap.attacker_score,
        [defId] = snap.defender_score,
        [tostring(atkId)] = snap.attacker_score,
        [tostring(defId)] = snap.defender_score,
    }
    MyContext.myWar.starts_at = snap.starts_at or 0
    MyContext.myWar.ends_at = snap.ends_at or 0
    MyContext.myWar.zone_id = snap.zone_id
    MyContext.myWar.zone = snap.zone_id
    MyContext.myWar.zone_name = snap.zone_name or '?'
    MyContext.myWar.attacker_label = snap.attacker_label or '?'
    MyContext.myWar.defender_label = snap.defender_label or '?'
    MyContext.myWar.my_side = (myGid == atkId) and 'attacker' or 'defender'

    TriggerEvent('esx_families:client:contextUpdated', MyContext)
    return true
end

local function pushNuiTopbar(snap)
    if not MyContext or not MyContext.gang then return end

    local myGid = num(MyContext.gang.id, -1)
    local atkId = num(snap.attacker_id, -2)
    local defId = num(snap.defender_id, -3)
    if myGid ~= atkId and myGid ~= defId then return end

    local phase = snap.status or 'active'
    local serverNow = num(snap.server_now, 0)
    local payload = {
        action = 'updateWar',
        show = true,
        attacker = snap.attacker_label or '?',
        defender = snap.defender_label or '?',
        zone = snap.zone_name or '?',
        status = phase,
        phase = phase,
        attackerScore = snap.attacker_score,
        defenderScore = snap.defender_score,
        myScore = (myGid == atkId) and snap.attacker_score or snap.defender_score,
        theirScore = (myGid == atkId) and snap.defender_score or snap.attacker_score,
        isParticipant = true,
    }

    if phase == 'preparing' and snap.starts_at then
        payload.prepTimer = fmtTime(num(snap.starts_at, 0) - serverNow)
    else
        payload.timer = fmtTime(num(snap.ends_at, 0) - serverNow) .. ' متبقي'
    end

    SendNUIMessage(payload)
end

RegisterNetEvent('esx_families:warHud:tick', function(snap)
    if type(snap) ~= 'table' or not snap.war_id then return end

    snap.attacker_score = num(snap.attacker_score, 0)
    snap.defender_score = num(snap.defender_score, 0)
    snap.hud_seq = num(snap.hud_seq or snap.server_ms, 0)

    if not sameWar(snap.war_id, LastWarId) then
        LastWarId = snap.war_id
        LastAtkScore = snap.attacker_score
        LastDefScore = snap.defender_score
        LastSeq = snap.hud_seq
    else
        if LastSeq > 0 and snap.hud_seq > 0 and snap.hud_seq < LastSeq then
            return
        end

        local oldAtk = LastAtkScore or 0
        local oldDef = LastDefScore or 0
        local oldSum = oldAtk + oldDef
        local newSum = snap.attacker_score + snap.defender_score
        if newSum < oldSum then
            return
        end

        if snap.attacker_score < oldAtk then snap.attacker_score = oldAtk end
        if snap.defender_score < oldDef then snap.defender_score = oldDef end

        LastAtkScore = snap.attacker_score
        LastDefScore = snap.defender_score
        if snap.hud_seq > LastSeq then LastSeq = snap.hud_seq end
    end

    if applySnapToContext(snap) then
        pushNuiTopbar(snap)
    end
end)

RegisterNetEvent('esx_families:warHud:end', function(wid)
    if LastWarId and sameWar(wid, LastWarId) then
        LastWarId, LastAtkScore, LastDefScore, LastSeq = nil, nil, nil, 0
    end

    if MyContext and MyContext.myWar and sameWar(MyContext.myWar.id, wid) then
        MyContext.myWar = nil
        SendNUIMessage({ action = 'updateWar', show = false })
        TriggerEvent('esx_families:client:contextUpdated', MyContext)
    end
end)

RegisterCommand('warhud_diag', function()
    print(('[warhud] v0.7.12 bridge war=%s atk=%s def=%s seq=%s'):format(
        tostring(LastWarId), tostring(LastAtkScore), tostring(LastDefScore), tostring(LastSeq)
    ))
end, false)

CreateThread(function()
    Wait(1500)
    print('[esx_families:warhud] v0.7.12 sync bridge loaded — DrawRect renderer disabled')
end)
