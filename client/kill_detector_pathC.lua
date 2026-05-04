-- v0.7.0d Path C — client kill detector via gameEventTriggered
-- يلتقط CEventNetworkEntityDamage مع isFatal=true ويرسل victim serverId للسيرفر
local lastSentAt = 0

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    -- args: {victim, attacker, ?, ?, ?, ?, weaponHash, ?, ?, ?, isFatal}
    local victimEnt   = args[1]
    local attackerEnt = args[2]
    local isFatal     = args[6] == 1 or args[6] == true
    if not isFatal then return end
    if not victimEnt or victimEnt == 0 then return end
    if not IsEntityAPed(victimEnt) then return end
    if not IsPedAPlayer(victimEnt) then return end

    local victimPlayer = NetworkGetEntityOwner(victimEnt) -- not reliable for serverId, use below
    -- map ped → player index → serverId
    local victimPlayerIdx = NetworkGetPlayerIndexFromPed(victimEnt)
    if not victimPlayerIdx or victimPlayerIdx < 0 then return end
    local victimServerId = GetPlayerServerId(victimPlayerIdx)
    if not victimServerId or victimServerId <= 0 then return end

    local attackerServerId = nil
    if attackerEnt and attackerEnt ~= 0 and DoesEntityExist(attackerEnt) and IsEntityAPed(attackerEnt) and IsPedAPlayer(attackerEnt) then
        local aIdx = NetworkGetPlayerIndexFromPed(attackerEnt)
        if aIdx and aIdx >= 0 then
            attackerServerId = GetPlayerServerId(aIdx)
        end
    end

    -- نرسل فقط لو الـ victim هو اللاعب المحلي (يضمن مصدر واحد لكل قتل)
    local me = PlayerId()
    if victimPlayerIdx ~= me then return end

    local now = GetGameTimer()
    if now - lastSentAt < 500 then return end
    lastSentAt = now

    TriggerServerEvent('__qbx_families_internal:clientKillReport', {
        victimSrc   = victimServerId,
        attackerSrc = attackerServerId,
        weapon      = args[7],
        ts          = now,
        source      = 'pathC'
    })
end)

CreateThread(function()
    Wait(2000)
    print('[esx_families] v0.7.0d Path C kill detector loaded ✓')
end)
