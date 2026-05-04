-- v0.7.0d Path C — server relay for client kill reports
-- يستقبل من client/kill_detector_pathC.lua ويمرر لـ KE_accept/KE_reject
-- مع dedup ضد Path A/B (نفس KE_dedupKey إذا موجود)

local function safe(f, ...) local ok, err = pcall(f, ...); if not ok then print('[killrelay] ERR: '..tostring(err)) end end

RegisterNetEvent('__qbx_families_internal:clientKillReport', function(payload)
    local victimSrc = source -- نأخذ من source لمنع spoofing
    if type(payload) ~= 'table' then return end
    local attackerSrc = tonumber(payload.attackerSrc)
    local weapon      = payload.weapon

    -- استدعاء API من v0.7.0b kill engine لو موجود
    if type(_G.KillEngine) ~= 'table' then
        print(('[killrelay] KillEngine missing — drop kill victim=%s'):format(victimSrc))
        return
    end

    -- dedup
    if type(_G.KE_dedupKey) == 'function' then
        local key = _G.KE_dedupKey(victimSrc, attackerSrc, payload.ts or 0)
        _G.KillEngine._seen = _G.KillEngine._seen or {}
        if key and _G.KillEngine._seen[key] then return end
        if key then
            _G.KillEngine._seen[key] = os.time()
        end
    end

    -- نمرر للـ engine بنفس صيغة Path B (تفترض onPlayerKilled style)
    if type(_G.KE_handleKill) == 'function' then
        safe(_G.KE_handleKill, victimSrc, attackerSrc, weapon, 'pathC')
    else
        -- fallback: نقلد baseevents:onPlayerKilled على السيرفر بحيث Path B handler يتعامل
        TriggerEvent('baseevents:onPlayerKilled', victimSrc, {
            killerinveh    = false,
            weaponhash     = weapon,
            distance       = 0.0,
            killerpos      = vector3(0,0,0),
            killertype     = 28,
            attackerSrc    = attackerSrc,
            __relayedFrom  = 'pathC',
        })
        -- ولو ما عنده handler يقرأ attackerSrc من الجدول، نطلق حدث مخصص
        TriggerEvent('__qbx_families_internal:reportKill', {
            victimSrc   = victimSrc,
            attackerSrc = attackerSrc,
            weapon      = weapon,
            source      = 'pathC',
        })
    end
end)

CreateThread(function()
    Wait(1500)
    print('[esx_families] v0.7.0d Path C server relay loaded ✓')
end)
