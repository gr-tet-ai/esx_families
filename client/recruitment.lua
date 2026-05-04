-- ============================================================
-- esx_families - Recruitment Points (Client) v0.5.0
-- Hybrid: NPC للجميع، blip للأعضاء/الأدمن فقط
-- ============================================================

CurrentRecruitmentPoints = {}   -- [id] = point
RecruitmentPeds = {}            -- [id] = pedHandle
RecruitmentBlips = {}           -- [id] = blipHandle
local pendingRequest = false

local function loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(50) end
    return HasModelLoaded(hash) and hash or nil
end

local function spawnPed(point)
    local hash = loadModel(point.ped_model or 's_m_y_dealer_01')
    if not hash then return nil end
    local p = CreatePed(4, hash, point.coords_x, point.coords_y, point.coords_z - 1.0, point.heading or 0.0, false, true)
    if not p or p == 0 then return nil end
    SetEntityInvincible(p, true)
    SetBlockingOfNonTemporaryEvents(p, true)
    FreezeEntityPosition(p, true)
    SetPedDiesWhenInjured(p, false)
    SetPedCanRagdoll(p, false)
    SetPedCanBeTargetted(p, false)
    SetModelAsNoLongerNeeded(hash)
    return p
end

local function isMemberOrAdmin(pointGangId)
    if not MyContext then return false end
    if MyContext.isAdmin then return true end
    if MyContext.gang and MyContext.gang.id == pointGangId then return true end
    return false
end

local function rebuildBlips()
    for id, b in pairs(RecruitmentBlips) do RemoveBlip(b); RecruitmentBlips[id] = nil end
    for id, p in pairs(CurrentRecruitmentPoints) do
        if isMemberOrAdmin(p.gang_id) then
            local b = AddBlipForCoord(p.coords_x, p.coords_y, p.coords_z)
            SetBlipSprite(b, 480)              -- handshake-ish
            SetBlipDisplay(b, 4)
            SetBlipScale(b, 0.85)
            SetBlipColour(b, 17)               -- برتقالي
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            local g = (ClientGangs and ClientGangs[p.gang_id]) or {}
            AddTextComponentString('🤝 ' .. (p.name or 'مكتب التجنيد') .. ' (' .. (g.label or '?') .. ')')
            EndTextCommandSetBlipName(b)
            RecruitmentBlips[id] = b
        end
    end
end

local function clearAll()
    for id, ped in pairs(RecruitmentPeds) do
        if DoesEntityExist(ped) then DeletePed(ped) end
        RecruitmentPeds[id] = nil
    end
    for id, b in pairs(RecruitmentBlips) do RemoveBlip(b); RecruitmentBlips[id] = nil end
end

RegisterNetEvent('esx_families:client:syncRecruitmentPoints', function(points, gangs)
    CurrentRecruitmentPoints = points or {}
    if gangs then ClientGangs = gangs end
    clearAll()
    -- spawn peds
    CreateThread(function()
        for id, p in pairs(CurrentRecruitmentPoints) do
            local ped = spawnPed(p)
            if ped then RecruitmentPeds[id] = ped end
        end
        rebuildBlips()
    end)
end)

-- لما context يتحدث (انضم لعائلة) → أعد رسم blips
AddEventHandler('esx_families:client:contextUpdated', function()
    rebuildBlips()
end)

-- ============================================================
-- التفاعل: [E] لفتح حوار الانضمام
-- ============================================================
local function openJoinDialog(pointId, point)
    local g = (ClientGangs or {})[point.gang_id] or {}
    local already = MyContext and MyContext.gang ~= nil
    local content
    if already then
        content = ('أنت بالفعل في عائلة **%s**.\nاخرج منها أولاً قبل الانضمام لعائلة جديدة.'):format(MyContext.gang.label or '?')
    else
        content = ('هل تريد طلب الانضمام لعائلة **%s**؟\n\nسيُرسل طلبك للقيادة وسيقررون قبولك أو رفضك.'):format(g.label or 'هذه العائلة')
    end

    local accept = lib.alertDialog({
        header = '🤝 ' .. (point.name or 'مكتب المبايعة'),
        content = content,
        centered = true, cancel = true,
        size = 'md',
        labels = { confirm = already and 'حسناً' or '✓ إرسال طلب', cancel = 'إلغاء' },
    })
    if already or accept ~= 'confirm' then return end
    if pendingRequest then return end
    pendingRequest = true

    local ok, msg = lib.callback.await('esx_families:server:requestJoin', false, pointId)
    pendingRequest = false
    lib.notify({
        type = ok and 'success' or 'error',
        title = ok and '✓ تم الإرسال' or '✗ فشل',
        description = msg or '',
        duration = 6000,
    })
end

-- thread تفاعل قريب (مُحسَّن v0.5.2: sleep ذكي + 2D pre-check + textUI cache)
CreateThread(function()
    local textShown = false
    while true do
        local sleep = 2000
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        local interactNow, nearest = false, nil

        for id, p in pairs(CurrentRecruitmentPoints) do
            local dx = pcoords.x - p.coords_x
            local dy = pcoords.y - p.coords_y
            -- 2D squared (يتجنب sqrt إذا بعيد)
            if (dx*dx + dy*dy) < 225.0 then  -- 15m radius
                local d = #(pcoords - vector3(p.coords_x, p.coords_y, p.coords_z))
                if d < 15.0 then
                    if sleep > 500 then sleep = 500 end
                    if d < 2.0 then
                        sleep = 0
                        interactNow = true
                        nearest = { id = id, point = p }
                        break
                    end
                end
            end
        end

        if interactNow and nearest then
            if not textShown then
                lib.showTextUI('[E] طلب الانضمام', { position = 'right-center', icon = 'handshake' })
                textShown = true
            end
            if IsControlJustPressed(0, 38) then
                lib.hideTextUI(); textShown = false
                openJoinDialog(nearest.id, nearest.point)
                Wait(500)
            end
        elseif textShown then
            lib.hideTextUI(); textShown = false
        end

        Wait(sleep)
    end
end)

-- ============================================================
-- استقبال طلبات الانضمام (للقيادة)
-- ============================================================
RegisterNetEvent('esx_families:client:newJoinRequest', function(req)
    lib.notify({
        type = 'inform', icon = 'user-plus', duration = 10000,
        title = '🤝 طلب انضمام جديد',
        description = ('%s يطلب الانضمام لعائلة %s\nاستخدم F6 → طلبات الانضمام'):format(req.player_name or '?', req.gang_label or ''),
    })
end)

-- ============================================================
-- تنظيف
-- ============================================================
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearAll()
end)
