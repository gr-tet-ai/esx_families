local function FamiliesUnixNow()
    if os and os.time then
        return FamiliesUnixNow()
    end
    if GetCloudTimeAsInt then
        return GetCloudTimeAsInt()
    end
    return math.floor((GetGameTimer and GetGameTimer() or 0) / 1000)
end

-- ============================================================
-- esx_families v0.6.6 — NUI HUD + Announcements + Countdown
-- ============================================================
HUDVisible = true
local lastFamilyState = nil
local lastWarState = nil
local lastPhase = nil
local countdownFired = false

local function fmtTime(sec)
    sec = math.max(0, math.floor(sec or 0))
    return ('%02d:%02d'):format(math.floor(sec/60), sec%60)
end

local function buildFamilyPayload()
    if not MyContext or not MyContext.gang then
        return { action='updateFamily', show=false }
    end
    local g = MyContext.gang
    local v = MyContext.vault or {}
    return {
        action='updateFamily', show=true,
        title    = g.label or 'العائلة',
        rank     = (MyContext.rank and MyContext.rank.label) or 'بدون',
        members  = MyContext.memberCount or 0,
        zones    = MyContext.zoneCount or 0,
        vault    = v.money or 0,
        vaultLocked = (v.war_locked == 1 or v.war_locked == true),
    }
end

local function buildWarPayload()
    if not MyContext or not MyContext.myWar then
        return { action='updateWar', show=false }, nil
    end
    local w = MyContext.myWar
    local now = FamiliesUnixNow()
    local atk = w.attacker_score or 0
    local def = w.defender_score or 0
    local mine, theirs
    if w.my_side == 'attacker' then mine, theirs = atk, def
    else mine, theirs = def, atk end

    local phase = w.status or 'active'
    local payload = {
        action='updateWar', show=true,
        attacker = w.attacker_label or '?',
        defender = w.defender_label or '?',
        zone     = w.zone_name or '?',
        status   = phase, phase = phase,
        myScore = mine, theirScore = theirs,
        attackerScore = atk, defenderScore = def,
        isParticipant = true,  -- لو وصلنا هنا فاللاعب مشارك
    }
    if phase == 'preparing' and w.starts_at then
        local remain = (w.starts_at or 0) - now
        payload.prepTimer = fmtTime(remain)
        payload._prepRemain = remain
    elseif w.ends_at then
        payload.timer = fmtTime((w.ends_at or 0) - now) .. ' متبقي'
    end
    return payload, phase
end

CreateThread(function()
    Wait(2000)
    while true do
        if HUDVisible then
            local fp = buildFamilyPayload()
            local fh = tostring(fp.show) .. (fp.title or '') .. (fp.rank or '') ..
                       tostring(fp.members) .. tostring(fp.zones) .. tostring(fp.vault) ..
                       tostring(fp.vaultLocked)
            if fh ~= lastFamilyState then
                SendNUIMessage(fp); lastFamilyState = fh
            end

            local wp, phase = buildWarPayload()
            if wp.show then
                -- نرسل كل ثانية لتحديث التايمر/النقاط
                SendNUIMessage(wp)

                -- تغيير phase → announcement
                if phase ~= lastPhase then
                    if phase == 'active' and lastPhase == 'preparing' then
                        SendNUIMessage({
                            action='announce',
                            sub='WAR STARTED',
                            title='بدأت المعركة',
                            extra=(wp.attacker .. ' ضد ' .. wp.defender),
                            duration=5000,
                        })
                    elseif phase == 'overtime' then
                        SendNUIMessage({
                            action='announce',
                            sub='OVERTIME',
                            title='وقت إضافي',
                            extra='النتيجة متعادلة!', duration=4000,
                        })
                    end
                    lastPhase = phase
                    countdownFired = false
                end

                -- countdown آخر 10 ثواني من التحضير
                if phase == 'preparing' and wp._prepRemain then
                    if wp._prepRemain <= 10 and wp._prepRemain > 0 and not countdownFired then
                        SendNUIMessage({ action='countdown', seconds = wp._prepRemain })
                        countdownFired = true
                    end
                end
            else
                if lastWarState ~= 'hidden' then
                    SendNUIMessage(wp); lastWarState = 'hidden'
                    lastPhase = nil; countdownFired = false
                end
            end
            if wp.show then lastWarState = 'shown' end
        else
            if lastFamilyState ~= 'hidden' then
                SendNUIMessage({ action='hideAll' })
                lastFamilyState = 'hidden'; lastWarState = 'hidden'
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('esx_families:client:contextUpdated', function() lastFamilyState = nil end)
RegisterNetEvent('qbx_families:client:warUpdate', function() lastWarState = nil end)

RegisterNetEvent('qbx_families:client:warEnded', function(data)
    -- نعرض announcement للنهاية
    local title = 'انتهت المعركة'
    local extra = ''
    if data and data.winner and MyContext and MyContext.gang then
        if data.winner == MyContext.gang.id then
            title = 'النصر لنا!'; extra = '🏆 عائلتك فازت'
        else
            title = 'الهزيمة'; extra = '💀 عائلتك خسرت'
        end
    end
    SendNUIMessage({
        action='announce', sub='WAR ENDED',
        title=title, extra=extra, duration=7000,
    })
    lastPhase = nil; countdownFired = false
    lastWarState = nil
end)

CreateThread(function()
    Wait(15000)
    while true do
        if HUDVisible and MyContext and MyContext.gang then RefreshMyContext() end
        Wait(60000)
    end
end)

RegisterCommand('familyhud', function()
    HUDVisible = not HUDVisible
    lastFamilyState = nil; lastWarState = nil
    lib.notify({ type='inform',
        description='HUD العائلة: ' .. (HUDVisible and 'مفعّل' or 'معطّل') })
end, false)
