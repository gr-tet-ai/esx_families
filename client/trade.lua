-- ============================================================
-- esx_families v0.5.3 — Trade Points Client (ox_lib UI)
-- نقاط البيع: blip + marker + UI كامل بـ ox_lib (بدون HTML/NUI)
-- ============================================================

ClientTradePoints = {}    -- [id] = point
TradePointBlips = {}      -- [id] = blip
CurrentTradePoint = nil
CurrentTradeSession = nil -- { pointId, side, lastPayload }

local function rebuildTradeBlips()
    for _, b in pairs(TradePointBlips) do RemoveBlip(b) end
    TradePointBlips = {}
    for id, p in pairs(ClientTradePoints) do
        local blip = AddBlipForCoord(p.coords_x, p.coords_y, p.coords_z)
        SetBlipSprite(blip, Config.TradePoint.blip.sprite or 500)
        SetBlipColour(blip, Config.TradePoint.blip.color or 1)
        SetBlipScale(blip, Config.TradePoint.blip.scale or 0.9)
        SetBlipAsShortRange(blip, Config.TradePoint.blip.shortRange ~= false)
        SetBlipDisplay(blip, 4)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('💲 ' .. (p.name or 'نقطة بيع'))
        EndTextCommandSetBlipName(blip)
        TradePointBlips[id] = blip
    end
end

RegisterNetEvent('qbx_families:client:syncTradePoints', function(points)
    ClientTradePoints = points or {}
    rebuildTradeBlips()
end)

-- ===== Marker + interaction (2D pre-check) =====
CreateThread(function()
    while true do
        local sleep = 1500
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        local nearest, nearestDist = nil, 9999.0
        local drawDist = Config.TradePoint.drawDistance or 30.0
        local drawDistSq = drawDist * drawDist

        for id, p in pairs(ClientTradePoints) do
            local dx = pcoords.x - p.coords_x
            local dy = pcoords.y - p.coords_y
            if (dx*dx + dy*dy) < drawDistSq then
                local dist = #(pcoords - vector3(p.coords_x, p.coords_y, p.coords_z))
                if dist < drawDist then
                    sleep = 0
                    local m = Config.TradePoint.marker
                    DrawMarker(m.type, p.coords_x, p.coords_y, p.coords_z - 0.95,
                        0,0,0, 0,0,0,
                        m.size.x, m.size.y, m.size.z,
                        m.color.r, m.color.g, m.color.b, m.color.a,
                        false, true, 2, false, nil, nil, false)
                    if dist < nearestDist then
                        nearest, nearestDist = { id = id, point = p }, dist
                    end
                end
            end
        end

        if nearest and nearestDist < (Config.TradePoint.interactDistance or 2.0) then
            CurrentTradePoint = nearest
            if not CurrentTradeSession then
                lib.showTextUI('[E] فتح نقطة بيع: ' .. (nearest.point.name or ''),
                    { position = 'right-center' })
                if IsControlJustPressed(0, 38) then
                    OpenTradeUI(nearest.id)
                end
            end
        else
            if CurrentTradePoint and not CurrentTradeSession then
                lib.hideTextUI()
            end
            CurrentTradePoint = nil
        end

        Wait(sleep)
    end
end)

-- ============================================================
-- UI Menus (ox_lib context)
-- ============================================================

local function fmtSide(payload, mySide)
    -- يبني وصف للقائمة الرئيسية: شو في الجهتين + جاهزية
    local lines = {}
    local me = payload[mySide]
    local otherSide = mySide == 'seller' and 'buyer' or 'seller'
    local other = payload[otherSide]

    table.insert(lines, '🟦 جهتي:')
    if me and #me.items > 0 then
        for _, it in ipairs(me.items) do
            table.insert(lines, ('  • %s × %d'):format(it.label or it.name, it.count))
        end
    else
        table.insert(lines, '  (فارغة)')
    end
    table.insert(lines, '')
    table.insert(lines, '🟥 الطرف الآخر:')
    if other and #other.items > 0 then
        for _, it in ipairs(other.items) do
            table.insert(lines, ('  • %s × %d'):format(it.label or it.name, it.count))
        end
        table.insert(lines, ('  جاهزية: %s'):format(other.ready and '✅' or '⌛'))
    elseif other then
        table.insert(lines, '  انضم لكن لم يضف بعد')
    else
        table.insert(lines, '  ⏳ بانتظار طرف آخر...')
    end
    return table.concat(lines, '\n')
end

local function openMyInventoryMenu()
    if not CurrentTradeSession then return end
    local inv = lib.callback.await('qbx_families:server:getMyInventory', false) or {}
    local options = {}

    if #inv == 0 then
        options[#options+1] = { title = 'جردك فارغ', disabled = true }
    else
        for _, it in ipairs(inv) do
            options[#options+1] = {
                title = ('➕ %s × %d'):format(it.label, it.count),
                description = 'اضغط لإضافة كمية للصفقة',
                onSelect = function()
                    local input = lib.inputDialog(('عرض %s'):format(it.label), {
                        { type = 'number', label = 'الكمية', default = 1, min = 1, max = it.count, required = true },
                    })
                    if not input or not input[1] then return end
                    local ok, err = lib.callback.await('qbx_families:server:offerItem', false,
                        CurrentTradeSession.pointId, it.name, input[1])
                    lib.notify({
                        title = '💲 الصفقة',
                        description = ok and ('✅ أضيف: %s × %d'):format(it.label, input[1]) or ('❌ '..(err or '?')),
                        type = ok and 'success' or 'error'
                    })
                    Wait(150)
                    OpenTradeMenu()
                end,
            }
        end
    end

    options[#options+1] = { title='↩️ رجوع', icon='arrow-left', onSelect=function() OpenTradeMenu() end }

    lib.registerContext({
        id = 'esx_families_trade_inv',
        title = '🎒 جردي — اختر قطعة',
        menu = 'esx_families_trade_main',
        options = options,
    })
    lib.showContext('esx_families_trade_inv')
end

local function openRemoveMenu()
    if not CurrentTradeSession or not CurrentTradeSession.lastPayload then return end
    local me = CurrentTradeSession.lastPayload[CurrentTradeSession.side]
    local options = {}
    if not me or #me.items == 0 then
        options[#options+1] = { title='ما عندك قطع للحذف', disabled=true }
    else
        for idx, it in ipairs(me.items) do
            options[#options+1] = {
                title = ('🗑️ %s × %d'):format(it.label or it.name, it.count),
                onSelect = function()
                    lib.callback.await('qbx_families:server:removeItem', false,
                        CurrentTradeSession.pointId, idx)
                    lib.notify({ title='💲 الصفقة', description='تم الحذف', type='inform' })
                    Wait(150)
                    OpenTradeMenu()
                end,
            }
        end
    end
    options[#options+1] = { title='↩️ رجوع', icon='arrow-left', onSelect=function() OpenTradeMenu() end }
    lib.registerContext({
        id = 'esx_families_trade_rm',
        title = '🗑️ حذف من عرضي',
        menu = 'esx_families_trade_main',
        options = options,
    })
    lib.showContext('esx_families_trade_rm')
end

-- القائمة الرئيسية للصفقة
function OpenTradeMenu()
    if not CurrentTradeSession then return end
    local payload = CurrentTradeSession.lastPayload or { seller=nil, buyer=nil }
    local mySide = CurrentTradeSession.side
    local me = payload[mySide]
    local meReady = me and me.ready

    local options = {
        {
            title = '📋 حالة الصفقة',
            description = fmtSide(payload, mySide),
            icon = 'list',
            disabled = true,
        },
        {
            title = '➕ أضف قطعة من جردي',
            icon = 'plus',
            onSelect = openMyInventoryMenu,
        },
        {
            title = '🗑️ احذف قطعة من عرضي',
            icon = 'trash',
            onSelect = openRemoveMenu,
        },
        {
            title = meReady and '⌛ إلغاء الجاهزية' or '✅ أنا جاهز',
            description = meReady and 'انتظر الطرف الآخر' or 'يجب وجود قطعة على الأقل',
            icon = 'check',
            onSelect = function()
                local ok, err = lib.callback.await('qbx_families:server:setReady', false,
                    CurrentTradeSession.pointId, not meReady)
                if not ok then
                    lib.notify({ title='💲 الصفقة', description=err or '?', type='error' })
                    Wait(150)
                    OpenTradeMenu()
                end
            end,
        },
        {
            title = '🔄 تحديث',
            icon = 'rotate',
            onSelect = function() Wait(50); OpenTradeMenu() end,
        },
        {
            title = '🚪 مغادرة الصفقة',
            icon = 'door-open',
            onSelect = function()
                TriggerServerEvent('qbx_families:server:leaveTrade', CurrentTradeSession.pointId)
                CurrentTradeSession = nil
            end,
        },
    }

    lib.registerContext({
        id = 'esx_families_trade_main',
        title = '💲 ' .. (CurrentTradeSession.pointName or 'نقطة بيع'),
        options = options,
    })
    lib.showContext('esx_families_trade_main')
end

-- ===== فتح UI الصفقة =====
function OpenTradeUI(pointId)
    local ok, res = lib.callback.await('qbx_families:server:joinTrade', false, pointId)
    if not ok then
        return lib.notify({ type = 'error', description = res or 'فشل الانضمام' })
    end

    CurrentTradeSession = {
        pointId = pointId,
        side = res.side,
        pointName = ClientTradePoints[pointId] and ClientTradePoints[pointId].name or '',
        lastPayload = { seller=nil, buyer=nil },
    }
    lib.hideTextUI()
    OpenTradeMenu()
end

RegisterNetEvent('qbx_families:client:tradeUpdate', function(payload, mySide)
    if not CurrentTradeSession then return end
    CurrentTradeSession.lastPayload = payload
    -- نعيد فتح القائمة لو هي مفتوحة (refresh ناعم)
    if lib.getOpenContextMenu() == 'esx_families_trade_main' then
        OpenTradeMenu()
    end
end)

RegisterNetEvent('qbx_families:client:tradeClosed', function(reason)
    if CurrentTradeSession then
        CurrentTradeSession = nil
        lib.hideContext()
        lib.notify({ type = 'inform', description = reason or 'انتهت الصفقة' })
    end
end)

RegisterNetEvent('qbx_families:client:tradeCompleted', function()
    CurrentTradeSession = nil
    lib.hideContext()
end)

-- ===== Admin: إنشاء/حذف نقطة بيع =====
function AdminCreateTradePoint()
    local input = lib.inputDialog('💲 إنشاء نقطة بيع', {
        { type = 'input', label = 'اسم النقطة', placeholder = 'سوق الميرفي', required = true },
    })
    if not input then return end
    local ok, msg = lib.callback.await('qbx_families:server:adminCreateTradePoint', false, input[1])
    lib.notify({ type = ok and 'success' or 'error', description = msg })
end

function AdminListTradePoints()
    local pts = lib.callback.await('qbx_families:server:getAllTradePoints', false) or {}
    local options = {}
    for _, p in ipairs(pts) do
        options[#options+1] = {
            title = '💲 ' .. p.name,
            description = ('ID: %d'):format(p.id),
            onSelect = function()
                SetNewWaypoint(p.coords_x, p.coords_y)
                lib.notify({ type='inform', description='تم وضع نقطة على الخريطة' })
            end,
        }
    end
    if #options == 0 then options[1] = { title = 'لا توجد نقاط بيع', disabled = true } end
    lib.registerContext({ id='admin_trade_list', title='💲 نقاط البيع', options = options })
    lib.showContext('admin_trade_list')
end

function AdminDeleteTradePoint()
    local pts = lib.callback.await('qbx_families:server:getAllTradePoints', false) or {}
    local options = {}
    for _, p in ipairs(pts) do
        options[#options+1] = {
            title = '❌ ' .. p.name,
            description = ('ID: %d'):format(p.id),
            onSelect = function()
                local c = lib.alertDialog({
                    header='تأكيد الحذف',
                    content=('متأكد تبي تحذف نقطة "%s"؟'):format(p.name),
                    centered=true, cancel=true,
                })
                if c == 'confirm' then
                    local ok, msg = lib.callback.await('qbx_families:server:adminDeleteTradePoint', false, p.id)
                    lib.notify({ type = ok and 'success' or 'error', description = msg })
                end
            end,
        }
    end
    if #options == 0 then options[1] = { title = 'لا توجد نقاط بيع', disabled = true } end
    lib.registerContext({ id='admin_trade_del', title='🗑️ حذف نقطة بيع', options = options })
    lib.showContext('admin_trade_del')
end
