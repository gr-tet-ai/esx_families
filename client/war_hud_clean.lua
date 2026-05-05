-- ============================================================
-- esx_families v0.7.11b — War HUD CLEAN (renderer + strict anti-rollback)
-- ============================================================
local WarHudState, LastTickAt, ServerTimeAtTick, LocalMsAtTick = nil, 0, 0, 0
local STALE_MS = 10000  -- v0.7.11: كان 4000
local LastAtkScore, LastDefScore, LastEventText, LastEventUntil, LastWarId = nil, nil, '', 0, nil
local LastSnapMs = 0  -- آخر server_ms مقبول

RegisterNetEvent('esx_families:warHud:tick', function(snap)
    if type(snap) ~= 'table' or not snap.war_id then return end
    snap.attacker_score = tonumber(snap.attacker_score) or 0
    snap.defender_score = tonumber(snap.defender_score) or 0

    -- حرب جديدة → reset كامل
    if snap.war_id ~= LastWarId then
        LastWarId = snap.war_id
        LastAtkScore, LastDefScore = snap.attacker_score, snap.defender_score
        LastEventText, LastEventUntil = '', 0
        LastSnapMs = tonumber(snap.server_ms) or 0
        WarHudState = snap
        LastTickAt = GetGameTimer()
        ServerTimeAtTick = snap.server_now or 0
        LocalMsAtTick = LastTickAt
        return
    end

    -- v0.7.11b: anti-rollback صارم على مستوى الـ snap كاملاً
    -- لو مجموع النقاط أقل من المسجَّل → snap قديم/تالف، نرفضه كلياً
    if LastAtkScore and LastDefScore then
        local sumNew = snap.attacker_score + snap.defender_score
        local sumOld = LastAtkScore + LastDefScore
        if sumNew < sumOld then
            -- snap قديم — نتجاهله تماماً (لا نعرض، لا نحدّث وقت)
            return
        end
        -- لو أحد القيم أقل لكن المجموع ≥ (نادر): clamp
        if snap.attacker_score < LastAtkScore then snap.attacker_score = LastAtkScore end
        if snap.defender_score < LastDefScore then snap.defender_score = LastDefScore end
    end

    -- killfeed event
    local who, delta
    if LastAtkScore and snap.attacker_score > LastAtkScore then
        who, delta = snap.attacker_label, snap.attacker_score - LastAtkScore
    elseif LastDefScore and snap.defender_score > LastDefScore then
        who, delta = snap.defender_label, snap.defender_score - LastDefScore
    end
    if who then
        LastEventText = ('%s +%d'):format(who, delta)
        LastEventUntil = GetGameTimer() + 4000
    end

    LastAtkScore, LastDefScore = snap.attacker_score, snap.defender_score
    LastSnapMs = tonumber(snap.server_ms) or LastSnapMs
    WarHudState = snap
    LastTickAt = GetGameTimer()
    ServerTimeAtTick = snap.server_now or ServerTimeAtTick
    LocalMsAtTick = LastTickAt
end)

RegisterNetEvent('esx_families:warHud:end', function(wid)
    if WarHudState and WarHudState.war_id == wid then
        WarHudState = nil; LastWarId = nil; LastAtkScore = nil; LastDefScore = nil
        LastEventText = ''; LastEventUntil = 0; LastSnapMs = 0
    end
end)

local function drawText(txt,x,y,scale,r,g,b,a,center)
    SetTextFont(4); SetTextScale(0.0,scale); SetTextColour(r,g,b,a or 255)
    SetTextDropshadow(2,0,0,0,220); SetTextEdge(1,0,0,0,220)
    if center then SetTextCentre(true) end
    SetTextEntry('STRING'); AddTextComponentString(tostring(txt or '')); DrawText(x,y)
end
local function drawRect(x,y,w,h,r,g,b,a) DrawRect(x+w/2,y+h/2,w,h,r,g,b,a) end
local function colorFor(label)
    local p={{220,50,50},{50,130,240},{60,200,100},{240,160,40},{180,90,220},{240,220,60},{40,200,200},{240,100,170}}
    local h=2166136261; label=tostring(label or '?')
    for i=1,#label do h=((h ~ string.byte(label,i))*16777619)%4294967296 end
    local c=p[(h%#p)+1]; return c[1],c[2],c[3]
end

CreateThread(function()
    while true do
        local s, now = WarHudState, GetGameTimer()
        if s and (now - LastTickAt) > STALE_MS then s = nil end
        if not s then Wait(500) else
            local remain = math.max(0, (s.ends_at or 0) - (ServerTimeAtTick + math.floor((now-LocalMsAtTick)/1000)))
            local timer = ('%02d:%02d'):format(math.floor(remain/60), remain%60)
            local cx,y,w,h = 0.5,0.018,0.34,0.052; local left = cx-w/2
            local ar,ag,ab = colorFor(s.attacker_label); local dr,dg,db = colorFor(s.defender_label)
            drawRect(left,y,w/2,h,ar,ag,ab,215); drawRect(left+w/2,y,w/2,h,dr,dg,db,215)
            drawRect(cx-0.0008,y,0.0016,h,255,255,255,230); drawRect(left,y+h-0.003,w,0.003,255,200,60,255)
            drawText(('%s   %d  X  %d   %s'):format(s.attacker_label or '?', s.attacker_score or 0, s.defender_score or 0, s.defender_label or '?'), cx, y+0.006, 0.43, 255,255,255,255, true)
            drawText(('TIME %s  |  %s'):format(timer, s.zone_name or '?'), cx, y+0.030, 0.31, 255,240,200,245, true)
            if LastEventText ~= '' and now < LastEventUntil then
                drawRect(left+w*0.25,y+h+0.004,w*0.50,0.024,0,0,0,200)
                drawText(LastEventText,cx,y+h+0.007,0.34,255,230,100,255,true)
            end
            Wait(0)
        end
    end
end)

RegisterCommand('warhud_diag', function()
    if not WarHudState then print('[warhud] state=nil'); return end
    print(('[warhud] v0.7.11b war=%s atk=%s(%d) def=%s(%d) zone=%s last_tick=%dms last_ms=%d'):format(
        tostring(WarHudState.war_id), WarHudState.attacker_label, WarHudState.attacker_score,
        WarHudState.defender_label, WarHudState.defender_score, WarHudState.zone_name,
        GetGameTimer()-LastTickAt, LastSnapMs))
end, false)
