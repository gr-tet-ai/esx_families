-- ============================================================
-- esx_families v0.5.3 — Trade Points (esx_inventory)
-- نقاط البيع: مواطنين/عصابات. الممنوعات داخل زونات العصابات فقط
-- ============================================================
-- ملاحظة v0.5.3: مفتاح القطعة = item_name (esx_inventory ما يدعم slots)
-- ============================================================

ActiveTrades = {}

local function getPlayerInventory(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return {} end
    local list = {}
    for _, it in ipairs(xPlayer.inventory or {}) do
        if it.count and it.count > 0 then
            list[#list+1] = {
                name  = it.name,
                count = it.count,
                label = it.label or it.name,
            }
        end
    end
    table.sort(list, function(a,b) return (a.label or a.name) < (b.label or b.name) end)
    return list
end

local function getPlayerItem(src, itemName)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end
    local item = xPlayer.getInventoryItem(itemName)
    if not item then return nil end
    return { name = item.name, count = item.count or 0, label = item.label or item.name }
end

-- ============= Admin: إضافة نقطة =============
lib.callback.register('qbx_families:server:adminCreateTradePoint', function(source, name, gangId)
    if not IsAdmin(source) then return false, 'للآدمن فقط' end
    if not name or name == '' then return false, 'الاسم مطلوب' end

    local count = 0
    for _ in pairs(TradePointsCache) do count = count + 1 end
    if count >= (Config.TradePoint.maxPoints or 50) then
        return false, ('وصلت للحد الأقصى من نقاط البيع (%d)'):format(Config.TradePoint.maxPoints)
    end

    if gangId and not GangsCache[gangId] then
        return false, 'العصابة المحددة غير موجودة'
    end

    local cid = GetCitizenId(source) or 'admin'
    local coords = GetEntityCoords(GetPlayerPed(source))

    local id = MySQL.insert.await(
        'INSERT INTO family_trade_points (name, coords_x, coords_y, coords_z, created_by) VALUES (?, ?, ?, ?, ?)',
        { name, coords.x, coords.y, coords.z, cid }
    )
    if not id then return false, 'فشل الإنشاء' end

    local newPoint = {
        id = id, name = name,
        coords_x = coords.x, coords_y = coords.y, coords_z = coords.z,
        zone_id = nil, created_by_gang_id = gangId, war_disabled = 0,
    }
    TradePointsCache[id] = newPoint

    if gangId then
        MySQL.update('UPDATE family_trade_points SET created_by_gang_id = ? WHERE id = ?', { gangId, id })
    end

    AttachTradePointToZone(newPoint)
    SyncTradePointsToAll()

    local info = ''
    if gangId then
        info = (' | منسوبة صراحةً لعائلة %s'):format(GangsCache[gangId].label)
    elseif newPoint.zone_id then
        info = (' | داخل زون %s'):format((ZonesCache[newPoint.zone_id] or {}).name or '?')
    else
        info = ' | مستقلة (خارج الزونات)'
    end
    return true, ('تم إنشاء نقطة بيع "%s"%s'):format(name, info)
end)

lib.callback.register('qbx_families:server:adminDeleteTradePoint', function(source, pointId)
    if not IsAdmin(source) then return false, 'للآدمن فقط' end
    if not TradePointsCache[pointId] then return false, 'النقطة غير موجودة' end

    if ActiveTrades[pointId] then
        local t = ActiveTrades[pointId]
        if t.seller and t.seller.src then
            TriggerClientEvent('qbx_families:client:tradeClosed', t.seller.src, 'تم حذف نقطة البيع')
        end
        if t.buyer and t.buyer.src then
            TriggerClientEvent('qbx_families:client:tradeClosed', t.buyer.src, 'تم حذف نقطة البيع')
        end
        ActiveTrades[pointId] = nil
    end

    MySQL.query.await('DELETE FROM family_trade_points WHERE id = ?', { pointId })
    TradePointsCache[pointId] = nil
    SyncTradePointsToAll()
    return true, 'تم الحذف'
end)

lib.callback.register('qbx_families:server:getAllTradePoints', function(source)
    local list = {}
    for _, p in pairs(TradePointsCache) do list[#list+1] = p end
    table.sort(list, function(a,b) return a.id < b.id end)
    return list
end)

-- ============= انضمام لصفقة =============
lib.callback.register('qbx_families:server:joinTrade', function(source, pointId)
    local point = TradePointsCache[pointId]
    if not point then return false, 'النقطة غير موجودة' end
    if point.war_disabled == 1 then return false, '⚔️ النقطة مقفلة أثناء الحرب' end

    -- v0.6.1: 2D + z tolerance (الجذر #2 — marker قد يكون منحفر تحت الأرض)
    local coords = GetEntityCoords(GetPlayerPed(source))
    local maxDist = (Config.TradePoint.interactDistance or 2.0) + 1.5
    local dist2D = #(vector2(coords.x, coords.y) - vector2(point.coords_x, point.coords_y))
    local distZ  = math.abs(coords.z - point.coords_z)
    if dist2D > maxDist or distZ > 2.5 then
        return false, 'بعيد عن نقطة البيع'
    end

    local cid = GetCitizenId(source)
    if not cid then return false end

    ActiveTrades[pointId] = ActiveTrades[pointId] or { started_at = os.time() }
    local trade = ActiveTrades[pointId]

    if trade.seller and trade.seller.src == source then return true, { side = 'seller' } end
    if trade.buyer  and trade.buyer.src  == source then return true, { side = 'buyer'  } end

    if not trade.seller then
        trade.seller = { src = source, cid = cid, items = {}, ready = false }
        broadcastTrade(pointId)
        return true, { side = 'seller' }
    elseif not trade.buyer then
        trade.buyer = { src = source, cid = cid, items = {}, ready = false }
        broadcastTrade(pointId)
        return true, { side = 'buyer' }
    else
        return false, 'الصفقة ممتلئة (شخصين فقط)'
    end
end)

RegisterNetEvent('qbx_families:server:leaveTrade', function(pointId)
    local src = source
    local trade = ActiveTrades[pointId]
    if not trade then return end

    if trade.seller and trade.seller.src == src then
        TriggerClientEvent('qbx_families:client:tradeClosed', src, 'غادرت الصفقة')
        if trade.buyer then
            TriggerClientEvent('qbx_families:client:tradeClosed', trade.buyer.src, 'غادر الطرف الثاني')
        end
        ActiveTrades[pointId] = nil
    elseif trade.buyer and trade.buyer.src == src then
        TriggerClientEvent('qbx_families:client:tradeClosed', src, 'غادرت الصفقة')
        if trade.seller then
            TriggerClientEvent('qbx_families:client:tradeClosed', trade.seller.src, 'غادر الطرف الثاني')
        end
        ActiveTrades[pointId] = nil
    end
end)

-- ============= جلب جرد اللاعب =============
lib.callback.register('qbx_families:server:getMyInventory', function(source)
    return getPlayerInventory(source)
end)

-- ============= عرض / إضافة قطعة للصفقة =============
-- v0.5.3: المفتاح = item_name (مو slot)
lib.callback.register('qbx_families:server:offerItem', function(source, pointId, itemName, count)
    local trade = ActiveTrades[pointId]
    if not trade then return false, 'الصفقة منتهية' end

    local side
    if trade.seller and trade.seller.src == source then side = 'seller'
    elseif trade.buyer and trade.buyer.src == source then side = 'buyer'
    else return false, 'لست في الصفقة' end

    local mySide = trade[side]
    if #mySide.items >= (Config.TradePoint.maxItemsPerSide or 4) then
        return false, ('الحد الأقصى %d قطع'):format(Config.TradePoint.maxItemsPerSide)
    end

    local invItem = getPlayerItem(source, itemName)
    if not invItem or invItem.count < 1 then return false, 'لا تملك هذه القطعة' end

    local point = TradePointsCache[pointId]
    if point and not point.zone_id and Shared.IsIllegalItem(invItem.name) then
        return false, '⛔ الممنوعات تُباع داخل زونات العصابات فقط'
    end

    count = math.floor(tonumber(count) or 1)
    if count < 1 then count = 1 end
    if count > invItem.count then count = invItem.count end

    -- لا تكرر نفس القطعة
    for _, it in ipairs(mySide.items) do
        if it.name == itemName then return false, 'هذي القطعة مضافة بالفعل (احذفها وأضفها بكمية أخرى)' end
    end

    mySide.items[#mySide.items+1] = {
        name = invItem.name, count = count, label = invItem.label,
    }
    if trade.seller then trade.seller.ready = false end
    if trade.buyer  then trade.buyer.ready  = false end
    broadcastTrade(pointId)
    return true
end)

-- ============= إزالة قطعة =============
lib.callback.register('qbx_families:server:removeItem', function(source, pointId, idx)
    local trade = ActiveTrades[pointId]
    if not trade then return false end
    local side
    if trade.seller and trade.seller.src == source then side = 'seller'
    elseif trade.buyer and trade.buyer.src == source then side = 'buyer'
    else return false end

    local mySide = trade[side]
    if mySide.items[idx] then
        table.remove(mySide.items, idx)
        if trade.seller then trade.seller.ready = false end
        if trade.buyer  then trade.buyer.ready  = false end
        broadcastTrade(pointId)
    end
    return true
end)

-- ============= جاهز =============
lib.callback.register('qbx_families:server:setReady', function(source, pointId, ready)
    local trade = ActiveTrades[pointId]
    if not trade then return false end
    local side
    if trade.seller and trade.seller.src == source then side = 'seller'
    elseif trade.buyer and trade.buyer.src == source then side = 'buyer'
    else return false end

    if #trade[side].items == 0 then
        return false, 'يجب إضافة قطعة على الأقل'
    end

    trade[side].ready = ready and true or false
    broadcastTrade(pointId)

    if trade.seller and trade.buyer and trade.seller.ready and trade.buyer.ready then
        executeTrade(pointId)
    end
    return true
end)

-- ============= تنفيذ الصفقة =============
function executeTrade(pointId)
    local trade = ActiveTrades[pointId]
    if not trade or not trade.seller or not trade.buyer then return end

    local s, b = trade.seller, trade.buyer

    -- تحقق نهائي: كل عنصر موجود فعلياً عند صاحبه
    local function verify(side)
        for _, it in ipairs(side.items) do
            local cur = getPlayerItem(side.src, it.name)
            if not cur or (cur.count or 0) < it.count then
                return false, it.label or it.name
            end
        end
        return true
    end

    -- تحقق سعة الجرد المستقبل
    local function canReceive(receiver, items)
        local xPlayer = ESX.GetPlayerFromId(receiver.src)
        if not xPlayer then return false end
        for _, it in ipairs(items) do
            if not xPlayer.canCarryItem(it.name, it.count) then
                return false, it.label or it.name
            end
        end
        return true
    end

    local ok1, missing1 = verify(s)
    local ok2, missing2 = verify(b)
    if not ok1 then
        TriggerClientEvent('ox_lib:notify', s.src, { type='error', description='قطعة ناقصة: '..missing1 })
        TriggerClientEvent('ox_lib:notify', b.src, { type='error', description='الطرف الآخر فقد قطعة' })
        s.ready = false; b.ready = false
        broadcastTrade(pointId); return
    end
    if not ok2 then
        TriggerClientEvent('ox_lib:notify', b.src, { type='error', description='قطعة ناقصة: '..missing2 })
        TriggerClientEvent('ox_lib:notify', s.src, { type='error', description='الطرف الآخر فقد قطعة' })
        s.ready = false; b.ready = false
        broadcastTrade(pointId); return
    end

    local okR1, fullItem1 = canReceive(b, s.items)
    local okR2, fullItem2 = canReceive(s, b.items)
    if not okR1 then
        TriggerClientEvent('ox_lib:notify', b.src, { type='error', description='جردك ممتلئ ('..fullItem1..')' })
        TriggerClientEvent('ox_lib:notify', s.src, { type='error', description='جرد الطرف الآخر ممتلئ' })
        s.ready=false; b.ready=false; broadcastTrade(pointId); return
    end
    if not okR2 then
        TriggerClientEvent('ox_lib:notify', s.src, { type='error', description='جردك ممتلئ ('..fullItem2..')' })
        TriggerClientEvent('ox_lib:notify', b.src, { type='error', description='جرد الطرف الآخر ممتلئ' })
        s.ready=false; b.ready=false; broadcastTrade(pointId); return
    end

    -- نقل
    local function transfer(from, to)
        local xFrom = ESX.GetPlayerFromId(from.src)
        local xTo   = ESX.GetPlayerFromId(to.src)
        if not xFrom or not xTo then return end
        for _, it in ipairs(from.items) do
            xFrom.removeInventoryItem(it.name, it.count)
            xTo.addInventoryItem(it.name, it.count)
        end
    end
    transfer(s, b)
    transfer(b, s)

    -- ضريبة الحماية لو داخل زون عصابة
    local point = TradePointsCache[pointId]
    if point and ApplyTradeProtectionTax then
        ApplyTradeProtectionTax(s, b, point)
    end

    -- تسجيل
    local sJson = json.encode(s.items)
    local bJson = json.encode(b.items)
    MySQL.insert('INSERT INTO family_trade_logs (point_id, seller_cid, buyer_cid, seller_items, buyer_items) VALUES (?, ?, ?, ?, ?)',
        { pointId, s.cid, b.cid, sJson, bJson })

    TriggerClientEvent('qbx_families:client:tradeCompleted', s.src)
    TriggerClientEvent('qbx_families:client:tradeCompleted', b.src)
    TriggerClientEvent('ox_lib:notify', s.src, { type='success', description='✅ تمت المبايعة بنجاح' })
    TriggerClientEvent('ox_lib:notify', b.src, { type='success', description='✅ تمت المبايعة بنجاح' })

    ActiveTrades[pointId] = nil
end

function broadcastTrade(pointId)
    local trade = ActiveTrades[pointId]
    if not trade then return end
    local payload = {
        pointId = pointId,
        seller = trade.seller and {
            cid = trade.seller.cid, items = trade.seller.items, ready = trade.seller.ready,
        } or nil,
        buyer = trade.buyer and {
            cid = trade.buyer.cid, items = trade.buyer.items, ready = trade.buyer.ready,
        } or nil,
    }
    if trade.seller then TriggerClientEvent('qbx_families:client:tradeUpdate', trade.seller.src, payload, 'seller') end
    if trade.buyer  then TriggerClientEvent('qbx_families:client:tradeUpdate', trade.buyer.src,  payload, 'buyer')  end
end

AddEventHandler('playerDropped', function()
    local src = source
    for pid, trade in pairs(ActiveTrades) do
        if (trade.seller and trade.seller.src == src) or (trade.buyer and trade.buyer.src == src) then
            local other = (trade.seller and trade.seller.src ~= src) and trade.seller
                       or (trade.buyer  and trade.buyer.src  ~= src) and trade.buyer
            if other then
                TriggerClientEvent('qbx_families:client:tradeClosed', other.src, 'غادر الطرف الثاني')
            end
            ActiveTrades[pid] = nil
        end
    end
end)

RegisterNetEvent('qbx_families:server:requestTradePoints', function()
    TriggerClientEvent('qbx_families:client:syncTradePoints', source, TradePointsCache)
end)
