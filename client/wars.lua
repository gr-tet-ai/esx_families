-- ============================================================
-- qbx_families - Wars Client v0.3.0
-- War Council ped + HUD + kill detection
-- مُحسَّن: thread واحد للـ ped (lazy)، kill detection خفيف
-- ============================================================

local CouncilPedHandle = nil
local CouncilBlip = nil
CurrentWar = nil  -- v0.6.4: global ليصل إلى war_visual.lua  -- cache من server
local WarHudVisible = false

-- ============================================================
-- War Council Spawn (يقرأ الإحداثيات من admin_config)
-- ============================================================
local function spawnCouncilPed()
    if CouncilPedHandle and DoesEntityExist(CouncilPedHandle) then return end

    -- نطلب الإحداثيات من السيرفر (يقرأها من admin_config)
    lib.callback('qbx_families:server:getCouncilCoords', false, function(coords)
        if not coords or not coords.x then return end

        local model = Config.War.councilPed
        lib.requestModel(model, 5000)

        CouncilPedHandle = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, 0.0, false, true)
        SetEntityAsMissionEntity(CouncilPedHandle, true, true)
        SetEntityInvincible(CouncilPedHandle, true)
        SetBlockingOfNonTemporaryEvents(CouncilPedHandle, true)
        FreezeEntityPosition(CouncilPedHandle, true)
        TaskStartScenarioInPlace(CouncilPedHandle, 'WORLD_HUMAN_CLIPBOARD', 0, true)

        SetModelAsNoLongerNeeded(model)

        -- بليب
        if CouncilBlip then RemoveBlip(CouncilBlip) end
        CouncilBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(CouncilBlip, Config.War.councilBlip.sprite or 487)
        SetBlipColour(CouncilBlip, Config.War.councilBlip.color or 1)
        SetBlipScale(CouncilBlip, Config.War.councilBlip.scale or 1.0)
        SetBlipAsShortRange(CouncilBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(Config.War.councilBlip.label or 'War Council')
        EndTextCommandSetBlipName(CouncilBlip)

        -- ox_target / qb-target / textUI
        if GetResourceState('ox_target') == 'started' then
            exports.ox_target:addLocalEntity(CouncilPedHandle, {
                {
                    name = 'family_war_council',
                    label = '⚔️ War Council',
                    icon = 'fa-solid fa-crown',
                    onSelect = function() OpenWarCouncilUI() end,
                },
            })
        else
            -- fallback: text UI ثقيل أقل
            CreateThread(function()
                while CouncilPedHandle and DoesEntityExist(CouncilPedHandle) do
                    local sleep = 1500
                    local pc = GetEntityCoords(PlayerPedId())
                    local pec = GetEntityCoords(CouncilPedHandle)
                    local d = #(pc - pec)
                    if d < 3.0 then
                        sleep = 5
                        lib.showTextUI('[E] فتح War Council', { position = 'right-center' })
                        if IsControlJustReleased(0, 38) then
                            lib.hideTextUI()
                            OpenWarCouncilUI()
                            Wait(500)
                        end
                    elseif d < 15.0 then
                        sleep = 500
                        lib.hideTextUI()
                    else
                        lib.hideTextUI()
                    end
                    Wait(sleep)
                end
            end)
        end
    end)
end

local function despawnCouncilPed()
    if CouncilPedHandle and DoesEntityExist(CouncilPedHandle) then
        if GetResourceState('ox_target') == 'started' then
            pcall(function() exports.ox_target:removeLocalEntity(CouncilPedHandle) end)
        end
        DeleteEntity(CouncilPedHandle)
    end
    CouncilPedHandle = nil
    if CouncilBlip then RemoveBlip(CouncilBlip); CouncilBlip = nil end
end


local function WaitForESXPlayerReady(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 10000)
    while GetGameTimer() < deadline do
        if LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn then return true end
        local ped = PlayerPedId()
        if NetworkIsPlayerActive(PlayerId()) and ped and ped ~= 0 and DoesEntityExist(ped) then return true end
        Wait(250)
    end
    return false
end

CreateThread(function()
    Wait(5000)
    WaitForESXPlayerReady(10000)
    spawnCouncilPed()
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then despawnCouncilPed() end
end)

-- ============================================================
-- War Council UI
-- ============================================================
function OpenWarCouncilUI()
    lib.callback('qbx_families:server:getMyWar', false, function(myWar)
        local options = {}

        if myWar then
            options[#options+1] = {
                title = '⚔️ حربك الحالية: ' .. (myWar.attacker.label or '?') .. ' vs ' .. (myWar.defender.label or '?'),
                description = ('الزون: %s | الحالة: %s'):format(myWar.zone or '?', myWar.status),
                icon = 'fire',
                onSelect = function() ShowMyWarDetails(myWar) end,
            }
            options[#options+1] = {
                title = '🏳️ استسلام',
                description = 'القائد فقط — تفقد 50% من الخزنة + الزون',
                icon = 'flag',
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = 'تأكيد الاستسلام',
                        content = 'متأكد؟ ستفقد 50% من خزنتك + ملكية الزون',
                        centered = true, cancel = true,
                    })
                    if confirm == 'confirm' then
                        lib.callback('qbx_families:server:surrenderWar', false, function(ok, msg)
                            lib.notify({ type = ok and 'success' or 'error', description = msg })
                        end, myWar.id)
                    end
                end,
            }
        else
            options[#options+1] = {
                title = '🎯 إعلان حرب',
                description = 'اختر زون عصابة عدوة لمهاجمته',
                icon = 'crosshairs',
                onSelect = function() ShowAttackableZonesUI() end,
            }
        end

        options[#options+1] = {
            title = '📜 سجل الحروب',
            icon = 'scroll',
            onSelect = function() ShowWarHistoryUI() end,
        }

        lib.registerContext({
            id = 'family_war_council',
            title = '⚔️ War Council',
            options = options,
        })
        lib.showContext('family_war_council')
    end)
end

function ShowAttackableZonesUI()
    lib.callback('qbx_families:server:getAttackableZones', false, function(zones)
        if not zones or #zones == 0 then
            return lib.notify({ type = 'inform', description = 'لا توجد زونات قابلة للهجوم' })
        end
        local opts = {}
        for _, z in ipairs(zones) do
            opts[#opts+1] = {
                title = ('🎯 %s'):format(z.name),
                description = ('عصابة: %s'):format(z.gang_label or '?'),
                icon = 'bullseye',
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = 'تأكيد إعلان الحرب على ' .. z.name,
                        content = 'سيتم خصم تكلفة الحرب من خزنتك. متأكد؟',
                        centered = true, cancel = true,
                    })
                    if confirm == 'confirm' then
                        lib.callback('qbx_families:server:declareWar', false, function(ok, msg)
                            lib.notify({ type = ok and 'success' or 'error', description = msg, duration = 8000 })
                        end, z.id)
                    end
                end,
            }
        end
        lib.registerContext({ id = 'family_attackable_zones', title = '🎯 زونات للهجوم',
            menu = 'family_war_council', options = opts })
        lib.showContext('family_attackable_zones')
    end)
end

function ShowMyWarDetails(war)
    lib.registerContext({
        id = 'family_war_details',
        title = '⚔️ تفاصيل الحرب',
        menu = 'family_war_council',
        options = {
            { title = 'المهاجم: ' .. (war.attacker.label or '?'),
              description = 'النقاط: ' .. (war.attacker.score or 0), readOnly = true },
            { title = 'المدافع: ' .. (war.defender.label or '?'),
              description = 'النقاط: ' .. (war.defender.score or 0), readOnly = true },
            { title = 'الزون: ' .. (war.zone or '?'), readOnly = true },
            { title = 'الحالة: ' .. war.status, readOnly = true },
        },
    })
    lib.showContext('family_war_details')
end

function ShowWarHistoryUI()
    lib.callback('qbx_families:server:getWarHistory', false, function(rows)
        if not rows or #rows == 0 then
            return lib.notify({ type = 'inform', description = 'لا يوجد سجل حروب' })
        end
        local opts = {}
        for _, r in ipairs(rows) do
            opts[#opts+1] = {
                title = ('🏆 %s'):format(r.winner_label or '?'),
                description = ('%s vs %s | %s | %d-%d'):format(
                    r.attacker_label or '?', r.defender_label or '?',
                    r.zone_name or '?', r.attacker_score or 0, r.defender_score or 0),
                readOnly = true,
            }
        end
        lib.registerContext({ id = 'family_war_history', title = '📜 سجل الحروب',
            menu = 'family_war_council', options = opts })
        lib.showContext('family_war_history')
    end)
end

-- ============================================================
-- War HUD (مبسّط — يستخدم lib.showTextUI أو NUI خفيف)
-- ============================================================
RegisterNetEvent('qbx_families:client:warUpdate', function(war)
    -- نهتم فقط لو لاعبنا ضمن المشاركين (نتحقق من server-side getMyWar)
    -- للسرعة: نخزن آخر حرب ونحدّث HUD لو اللاعب في زون الحرب
    CurrentWar = war
end)

RegisterNetEvent('qbx_families:client:warEnded', function(data)
    if CurrentWar and CurrentWar.id == data.id then CurrentWar = nil end
end)

-- v0.6.6: HUD انتقل بالكامل إلى client/hud.lua (NUI) — تم حذف الـ thread القديم
-- ============================================================
-- Kill detection v0.7.4
-- لا نربط حساب القتل بـ CurrentWar/CurrentZone في الكلاينت؛ السيرفر هو اللي يتحقق.
-- ============================================================
local LastWarKillReport = {}

local function reportWarKillAsAttacker(victimSrc, sourceTag)
    victimSrc = tonumber(victimSrc)
    if not victimSrc or victimSrc <= 0 then return end
    local mySrc = GetPlayerServerId(PlayerId())
    if victimSrc == mySrc then return end
    local now = GetGameTimer()
    if (LastWarKillReport[victimSrc] or 0) + 1500 > now then return end
    LastWarKillReport[victimSrc] = now
    TriggerServerEvent('qbx_families:server:reportKill', mySrc, victimSrc, sourceTag or 'damage-event')
end

local function resolveKillerServerId(killerId)
    if type(killerId) ~= 'number' then return nil end

    -- baseevents client غالباً يعطي player index، وليس server id.
    if killerId >= 0 and NetworkIsPlayerActive(killerId) then
        local src = GetPlayerServerId(killerId)
        if src and src > 0 then return src end
    end

    -- احتياط: لو وصل أصلاً كـ server id.
    local idx = GetPlayerFromServerId(killerId)
    if idx and idx ~= -1 then return killerId end
    return nil
end

RegisterNetEvent('baseevents:onPlayerKilled', function(killerId, data)
    local killerSrc = resolveKillerServerId(killerId)
    local mySrc = GetPlayerServerId(PlayerId())
    if killerSrc and killerSrc > 0 and killerSrc ~= mySrc then
        TriggerServerEvent('qbx_families:server:reportKillByVictim', killerSrc, data and data.deathCause or 0)
    end
end)

AddEventHandler('gameEventTriggered', function(name, args)
    
    -- FAM76C_TRACE start
    if name == 'CEventNetworkEntityDamage' then
        local v = args and args[1] or 0
        local k = args and args[2] or 0
        local died = args and args[6] or 0
        local myPed = PlayerPedId()
        local vIsPlayer = (v ~= 0 and DoesEntityExist(v) and IsPedAPlayer(v)) and 'YES' or 'NO'
        local kIsMe = (k == myPed) and 'YES' or 'NO'
        local vIsPed = (v ~= 0 and DoesEntityExist(v) and IsEntityAPed(v)) and 'YES' or 'NO'
        print(('[esx_families:TRACE] dmg victim=%s killer=%s died=%s vIsPed=%s vIsPlayer=%s killerIsMe=%s'):format(tostring(v), tostring(k), tostring(died), vIsPed, vIsPlayer, kIsMe))
    end
    -- FAM76C_TRACE end
if name ~= 'CEventNetworkEntityDamage' then return end

    local victim = args[1]
    local attacker = args[2]
    if not victim or not attacker or victim == attacker then return end
    if not IsPedAPlayer(victim) or not IsPedAPlayer(attacker) then return end

    local myPed = PlayerPedId()
    if attacker ~= myPed then return end

    local victimPlayer = NetworkGetPlayerIndexFromPed(victim)
    if victimPlayer == -1 then return end
    local victimSrc = GetPlayerServerId(victimPlayer)
    if not victimSrc or victimSrc <= 0 then return end

    CreateThread(function()
        Wait(650)
        if DoesEntityExist(victim) and IsPedDeadOrDying(victim, true) then
            reportWarKillAsAttacker(victimSrc, 'damage-confirmed')
        end
    end)
end)

-- ============================================================
-- Server event: re-spawn ped لو الإحداثيات تغيرت من الآدمن
-- ============================================================
RegisterNetEvent('qbx_families:client:respawnCouncilPed', function()
    despawnCouncilPed()
    Wait(500)
    spawnCouncilPed()
end)

-- ============================================================
-- v0.4.0: نقطة دخول من القائمة الرئيسية (F6)
-- نفس War Council UI لكن نقدر نُستدعى من أي مكان
-- ============================================================
function OpenWarsMenuFromF6()
    OpenWarCouncilUI()
end

-- ============================================================
-- v0.7.6 Diagnostics — simkill + force-enable trace
-- ============================================================
--[[ DISABLED v0.7.7 (replaced by war_hud_clean.lua)
CreateThread(function()
    Wait(2500)
    if FAM75_TRACE ~= nil then
        FAM75_TRACE = true
        print('[esx_families:client-kill] trace AUTO-ON (v0.7.6 diag)')
    end
end)

RegisterCommand('familywar_simkill', function(_, args)
    local victimSrc = tonumber(args[1])
    if not victimSrc or victimSrc <= 0 then
        print('Usage: /familywar_simkill <victimServerId>')
        return
    end
    local mySrc = GetPlayerServerId(PlayerId())
    if victimSrc == mySrc then
        print('[esx_families:client-kill] simkill rejected: cannot kill self')
        return
    end
    print(('[esx_families:client-kill] SIMKILL fired mySrc=%d -> victim=%d'):format(mySrc, victimSrc))
    TriggerServerEvent('qbx_families:server:reportKill', mySrc, victimSrc)
end, false)

RegisterCommand('familywar_simctx', function()
    local cw  = CurrentWar
    local cz  = CurrentZone
    print(('[esx_families:client-kill] CTX CurrentWar=%s CurrentZone=%s zoneMatch=%s'):format(
        cw and (cw.id or '?') or 'nil',
        cz and (cz.id or '?') or 'nil',
        (cw and cz and cw.zone == cz.id) and 'YES' or 'NO'
    ))
    if MyContext and MyContext.myWar then
        local mw = MyContext.myWar
        print(('[esx_families:client-kill] MyContext.myWar id=%s status=%s side=%s scores=%s:%s'):format(
            tostring(mw.id), tostring(mw.status), tostring(mw.my_side),
            tostring(mw.attacker_score), tostring(mw.defender_score)
        ))
    else
        print('[esx_families:client-kill] MyContext.myWar = nil')
    end
end, false)



-- ═══ v0.7.7 KILL FIX (victim-side reporting) ═══
RegisterNetEvent('baseevents:onPlayerDied')
AddEventHandler('baseevents:onPlayerDied', function(killerType, coords)
    -- لما الضحية تموت بدون قاتل لاعب
end)

--]]
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local victim, attacker, _, _, _, _, _, weapon, _, _, _, isFatal = table.unpack(args)
    if not isFatal or isFatal == 0 then return end

    local myPed = PlayerPedId()
    if victim ~= myPed then return end -- بس الضحية تبلّغ
    if not attacker or attacker == 0 or attacker == victim then return end

    -- حوّل attacker entity → serverId
    local attackerPlayerId = NetworkGetEntityOwner(attacker)
    local killerSrv = -1
    if attackerPlayerId and attackerPlayerId ~= -1 then
        killerSrv = GetPlayerServerId(attackerPlayerId)
    end
    -- fallback: لو الـ attacker ped لاعب
    if killerSrv == -1 and IsPedAPlayer(attacker) then
        local pid = NetworkGetPlayerIndexFromPed(attacker)
        if pid ~= -1 then killerSrv = GetPlayerServerId(pid) end
    end

    print(('[esx_families:KILLFIX] victim=ME killerEntity=%s killerSrv=%s weapon=%s')
        :format(attacker, killerSrv, weapon))

    if killerSrv and killerSrv > 0 then
        TriggerServerEvent('esx_families:reportWarKill', killerSrv, weapon)
    end
end)


-- ═══ v0.7.7 KILL FIX (victim-side reporting) ═══
RegisterNetEvent('baseevents:onPlayerDied')
AddEventHandler('baseevents:onPlayerDied', function(killerType, coords)
    -- لما الضحية تموت بدون قاتل لاعب
end)

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local victim, attacker, _, _, _, _, _, weapon, _, _, _, isFatal = table.unpack(args)
    if not isFatal or isFatal == 0 then return end

    local myPed = PlayerPedId()
    if victim ~= myPed then return end -- بس الضحية تبلّغ
    if not attacker or attacker == 0 or attacker == victim then return end

    -- حوّل attacker entity → serverId
    local attackerPlayerId = NetworkGetEntityOwner(attacker)
    local killerSrv = -1
    if attackerPlayerId and attackerPlayerId ~= -1 then
        killerSrv = GetPlayerServerId(attackerPlayerId)
    end
    -- fallback: لو الـ attacker ped لاعب
    if killerSrv == -1 and IsPedAPlayer(attacker) then
        local pid = NetworkGetPlayerIndexFromPed(attacker)
        if pid ~= -1 then killerSrv = GetPlayerServerId(pid) end
    end

    print(('[esx_families:KILLFIX] victim=ME killerEntity=%s killerSrv=%s weapon=%s')
        :format(attacker, killerSrv, weapon))

    if killerSrv and killerSrv > 0 then
        TriggerServerEvent('esx_families:reportWarKill', killerSrv, weapon)
    end
end)
