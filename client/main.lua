-- ============================================================
-- Client Main - Cache + Init  (v0.5.1)
-- ============================================================

ClientZones = {}
ClientGangs = {}
ClientBlips = {}
ClientRadiusBlips = {}

CurrentZone = nil
LastZoneNotify = {}

CurrentVaults = {}
CurrentRecruitmentPoints = {}

-- v0.5.0: my context (cache محلي) — يُستخدم في HUD + menus + recruitment blips
MyContext = nil

local function WaitForESXPlayerReady(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 10000)
    while GetGameTimer() < deadline do
        if LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn then return true end
        local ped = PlayerPedId()
        if NetworkIsPlayerActive(PlayerId()) and ped and ped ~= 0 and DoesEntityExist(ped) then return true end
        Wait(250)
    end
    print('^3[esx_families]^7 ESX player-ready wait timed out; continuing without qbox isLoggedIn state')
    return false
end

function RefreshMyContext()
    local ctx = lib.callback.await('qbx_families:server:getMyContext', false)
    MyContext = ctx
    TriggerEvent('esx_families:client:contextUpdated', ctx)
    return ctx
end

CreateThread(function()
    Wait(1500)
    WaitForESXPlayerReady(10000)
    TriggerServerEvent('qbx_families:server:requestZones')
    Wait(400)
    TriggerServerEvent('qbx_families:server:requestVaults')
    Wait(400)
    TriggerServerEvent('qbx_families:server:requestTradePoints')
    Wait(400)
    -- v0.5.1: اطلب نقاط المبايعة صراحة (لو ما وصلت من playerJoining)
    TriggerServerEvent('esx_families:server:requestRecruitmentPoints')
    Wait(400)
    RefreshMyContext()
end)

RegisterNetEvent('qbx_families:client:syncZones', function(zones, gangs)
    ClientZones = zones or {}
    ClientGangs = gangs or {}
    RebuildBlips()
end)

-- v0.5.0: إخطار اللاعب لما يُضم لعائلة (من admin أو دعوة أو قبول طلب)
RegisterNetEvent('esx_families:client:youJoinedGang', function(data)
    Wait(200)
    RefreshMyContext()
end)

-- v0.5.1: إخطار عند إخراج اللاعب من العائلة (طرد/مغادرة)
RegisterNetEvent('esx_families:client:youLeftGang', function()
    Wait(200)
    RefreshMyContext()
end)

-- v0.5.1: تحديث context فوراً عند تغيير حالة الحرب (للـ HUD المباشر)
RegisterNetEvent('qbx_families:client:warUpdate', function(war)
    if not MyContext or not MyContext.gang then return end
    if war.attacker == MyContext.gang.id or war.defender == MyContext.gang.id then
        -- حدّث context الجزئي محلياً لـ HUD (بدون round-trip للسيرفر)
        MyContext.myWar = MyContext.myWar or {}
        MyContext.myWar.id = war.id
        MyContext.myWar.status = war.status
        MyContext.myWar.attacker_score = (war.scores or {})[war.attacker] or 0
        MyContext.myWar.defender_score = (war.scores or {})[war.defender] or 0
        MyContext.myWar.ends_at = war.ends_at
        MyContext.myWar.starts_at = war.starts_at  -- v0.6.4: لعدّاد الاستعداد
        MyContext.myWar.attacker = war.attacker    -- v0.6.4: للـ war_visual HUD
        MyContext.myWar.defender = war.defender    -- v0.6.4: للـ war_visual HUD
        MyContext.myWar.scores  = war.scores or {} -- v0.6.4: للنقاط داخل الزون
        MyContext.myWar.zone_id = war.zone
        MyContext.myWar.zone_name = (ClientZones[war.zone] or {}).name
        MyContext.myWar.attacker_label = (ClientGangs[war.attacker] or {}).label
        MyContext.myWar.defender_label = (ClientGangs[war.defender] or {}).label
        MyContext.myWar.my_side = (war.attacker == MyContext.gang.id) and 'attacker' or 'defender'
    end
end)

RegisterNetEvent('qbx_families:client:warEnded', function(data)
    if MyContext and MyContext.myWar and MyContext.myWar.id == data.id then
        MyContext.myWar = nil
    end
    -- إعادة تحميل كاملة (لانتقال ملكية الزون لو فاز المهاجم)
    Wait(500)
    RefreshMyContext()
end)
