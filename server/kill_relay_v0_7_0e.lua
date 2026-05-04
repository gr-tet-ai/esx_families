-- ============================================================
-- esx_families v0.7.0e — HARD Kill Relay
-- يمرر للـ v0.7.0b engine بالصيغة الصحيحة: killerSrc, victimSrc
-- ============================================================
local VERSION = 'v0.7.0e'
local recent = {}
local reports = {}
local drops = {}
local pongs = {}
local lastProbeToken = nil

local function push(buf, row, max)
    max = max or 20
    table.insert(buf, 1, row)
    while #buf > max do table.remove(buf) end
end

local function canRun(src)
    return src == 0 or (IsAdmin and IsAdmin(src))
end

local function reply(src, msg)
    msg = tostring(msg or '')
    print('[esx_families:killrelay] ' .. msg)
    if src and src ~= 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { '^3esx_families', msg } })
    end
end

local function cleanupRecent()
    local t = os.time()
    for k, v in pairs(recent) do
        if (t - v) > 4 then recent[k] = nil end
    end
end

local function relayKill(victimSrc, payload, compatSource)
    cleanupRecent()
    victimSrc = tonumber(victimSrc)
    payload = type(payload) == 'table' and payload or {}

    local attackerSrc = tonumber(payload.attackerSrc)
    local weapon = payload.weapon or 0
    local detector = tostring(payload.detector or payload.source or compatSource or 'unknown')
    local version = tostring(payload.version or 'unknown')

    if not victimSrc or victimSrc <= 0 then
        push(drops, { t = os.date('%H:%M:%S'), reason = 'victim source invalid', attacker = attackerSrc, victim = victimSrc, detector = detector })
        return
    end

    if not attackerSrc or attackerSrc <= 0 then
        push(drops, { t = os.date('%H:%M:%S'), reason = 'attackerSrc nil/invalid', attacker = attackerSrc, victim = victimSrc, detector = detector, weapon = weapon })
        print(('[KillRelay %s][DROP] detector=%s victim=%s attacker=nil weapon=%s'):format(VERSION, detector, victimSrc, tostring(weapon)))
        return
    end

    if attackerSrc == victimSrc then
        push(drops, { t = os.date('%H:%M:%S'), reason = 'self kill ignored', attacker = attackerSrc, victim = victimSrc, detector = detector, weapon = weapon })
        print(('[KillRelay %s][DROP] detector=%s self-kill src=%s weapon=%s'):format(VERSION, detector, victimSrc, tostring(weapon)))
        return
    end

    local key = tostring(attackerSrc) .. ':' .. tostring(victimSrc) .. ':' .. tostring(math.floor(os.time() / 2))
    if recent[key] then
        push(drops, { t = os.date('%H:%M:%S'), reason = 'duplicate relay', attacker = attackerSrc, victim = victimSrc, detector = detector, weapon = weapon })
        return
    end
    recent[key] = os.time()

    push(reports, {
        t = os.date('%H:%M:%S'), attacker = attackerSrc, victim = victimSrc,
        detector = detector, version = version, weapon = weapon,
    })

    print(('[KillRelay %s][REPORT] detector=%s client=%s killer=%s victim=%s weapon=%s'):format(
        VERSION, detector, version, attackerSrc, victimSrc, tostring(weapon)
    ))

    -- هذا هو الربط الصحيح مع v0.7.0b:
    -- handler القديم معرف كـ AddEventHandler('__qbx_families_internal:reportKill', function(killerSrc, victimSrc)
    TriggerEvent('__qbx_families_internal:reportKill', attackerSrc, victimSrc)
end

RegisterNetEvent('__qbx_families_internal:clientKillReportV2', function(payload)
    relayKill(source, payload, 'pathE')
end)

-- Compatibility مع v0.7.0d القديم: لو client القديم أرسل هنا، هذا handler يصحح التمرير.
RegisterNetEvent('__qbx_families_internal:clientKillReport', function(payload)
    relayKill(source, payload, 'pathC-compat')
end)

RegisterNetEvent('__qbx_families_internal:killProbePong', function(payload)
    payload = type(payload) == 'table' and payload or {}
    local src = source
    if lastProbeToken and payload.token ~= lastProbeToken then return end
    pongs[src] = {
        t = os.date('%H:%M:%S'),
        version = tostring(payload.version or '?'),
        dead = payload.dead and true or false,
        x = tonumber(payload.x) or 0,
        y = tonumber(payload.y) or 0,
        z = tonumber(payload.z) or 0,
    }
    print(('[KillRelay %s][PONG] src=%s version=%s dead=%s coords=%.1f %.1f %.1f'):format(
        VERSION, src, pongs[src].version, tostring(pongs[src].dead), pongs[src].x, pongs[src].y, pongs[src].z
    ))
end)

RegisterCommand('familywar_killprobe', function(src)
    if not canRun(src) then return end
    pongs = {}
    lastProbeToken = tostring(os.time()) .. ':' .. tostring(math.random(1000, 9999))

    local players = GetPlayers()
    reply(src, ('sending client probe to %d online player(s)...'):format(#players))
    TriggerClientEvent('__qbx_families_internal:killProbe', -1, lastProbeToken)

    SetTimeout(1500, function()
        local count = 0
        for _ in pairs(pongs) do count = count + 1 end
        print(('========== [KillRelay Probe %s] =========='):format(VERSION))
        print(('online=%d pongs=%d'):format(#players, count))
        for _, pid in ipairs(players) do
            local n = tonumber(pid)
            local p = pongs[n]
            if p then
                print((' src=%s OK version=%s dead=%s coords=%.1f %.1f %.1f name=%s'):format(pid, p.version, tostring(p.dead), p.x, p.y, p.z, GetPlayerName(pid) or '?'))
            else
                print((' src=%s NO_PONG name=%s'):format(pid, GetPlayerName(pid) or '?'))
            end
        end
        print('=========================================')
    end)
end, true)

RegisterCommand('familywar_killrelay_diag', function(src)
    if not canRun(src) then return end
    print(('========== [KillRelay DIAG %s] =========='):format(VERSION))
    print('-- Last Reports وصلت للـ relay --')
    if #reports == 0 then print(' (none)') end
    for _, r in ipairs(reports) do
        print((' [%s] killer=%s victim=%s detector=%s client=%s weapon=%s'):format(r.t, r.attacker, r.victim, r.detector, r.version, tostring(r.weapon)))
    end

    print('-- Last Drops من relay --')
    if #drops == 0 then print(' (none)') end
    for _, d in ipairs(drops) do
        print((' [%s] attacker=%s victim=%s detector=%s reason=%s weapon=%s'):format(d.t, tostring(d.attacker), tostring(d.victim), tostring(d.detector), tostring(d.reason), tostring(d.weapon)))
    end

    print('-- Last Probe Pongs --')
    local any = false
    for srcId, p in pairs(pongs) do
        any = true
        print((' src=%s version=%s dead=%s coords=%.1f %.1f %.1f'):format(srcId, p.version, tostring(p.dead), p.x, p.y, p.z))
    end
    if not any then print(' (none)') end
    print('=========================================')
end, true)

RegisterCommand('familywar_fakekill', function(src, args)
    if not canRun(src) then return end
    local killerSrc = tonumber(args and args[1])
    local victimSrc = tonumber(args and args[2])
    if not killerSrc or not victimSrc then
        return reply(src, 'usage: familywar_fakekill <killerSrc> <victimSrc>   مثال: familywar_fakekill 1 2')
    end
    reply(src, ('fake kill → killer=%s victim=%s'):format(killerSrc, victimSrc))
    TriggerEvent('__qbx_families_internal:reportKill', killerSrc, victimSrc)
end, true)

RegisterCommand('familywar_killdebug', function(src, args)
    if not canRun(src) then return end
    local value = tostring((args and args[1]) or '1')
    if value ~= '0' then value = '1' end
    SetConvarReplicated('esx_families_killdebug', value)
    reply(src, 'replicated convar esx_families_killdebug=' .. value .. ' — restart/ensure may be needed for clean client state')
end, true)

CreateThread(function()
    Wait(1200)
    print(('[esx_families] %s HARD kill relay loaded ✓ commands: familywar_killprobe / familywar_killrelay_diag / familywar_fakekill'):format(VERSION))
end)
