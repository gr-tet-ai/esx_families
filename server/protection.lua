-- ============================================================
-- نظام خصم نسبة الحماية على البيع داخل الزون v0.3.0
-- ApplyTradeProtectionTax: يُستدعى من trade.lua بعد كل صفقة ناجحة
-- يطبق الضريبة فقط على الـ illegal items (Set lookup O(1))
-- ============================================================

---يحسب القيمة الإجمالية (تقريبية) لقائمة عناصر illegal فقط
---نحن لا نملك أسعار → نطبق ضريبة على عدد العناصر illegal × قيمة افتراضية
---لكن في النسخة العملية: ضريبة percent من أي مبلغ نقدي يتدفق + ضريبة slot
---@param items table list of {name, count}
---@return number illegalCount
local function countIllegal(items)
    local n = 0
    for _, it in ipairs(items or {}) do
        if Shared.IsIllegalItem(it.name) then n = n + (it.count or 1) end
    end
    return n
end

---يطبق ضريبة الحماية على صفقة كاملة (يُستدعى من trade.lua executeTrade)
---المنطق: لو نقطة البيع داخل زون عصابة → نخصم نسبة من قيمة العناصر illegal
---نحن نخصم من البائع (الأكثر منطقية)
---@param sellerData table { src, cid, items }
---@param buyerData table  { src, cid, items }
---@param point table  trade point row
---@return number taxTaken
function ApplyTradeProtectionTax(sellerData, buyerData, point)
    if not point or not point.zone_id then return 0 end
    local zone = ZonesCache[point.zone_id]
    if not zone then return 0 end

    -- لا ضريبة لو الزون نفسه في حرب (war_locked)
    if zone.war_locked == 1 then return 0 end

    local illegalCount = countIllegal(sellerData.items) + countIllegal(buyerData.items)
    if illegalCount <= 0 then return 0 end  -- شيء نظامي → بدون ضريبة

    -- قيمة افتراضية لكل قطعة illegal (admin config)
    local valuePerIllegal = GetAdminConfigNumber('illegal_item_estimated_value', 500)
    local totalValue = illegalCount * valuePerIllegal
    local pct = zone.protection_percent or 10.0
    local tax = math.floor(totalValue * pct / 100.0)
    if tax <= 0 then return 0 end

    -- نخصم من كاش البائع — لو ما عنده، نسجل عجز فقط
    local player = ESXBridge.GetPlayer(sellerData.src)
    if player and (player.PlayerData.money.cash or 0) >= tax then
        player.Functions.RemoveMoney('cash', tax, 'family-protection-tax')
        AddMoneyToVault(zone.gang_id, tax,
            ('ضريبة بيع: %d قطع illegal من %s'):format(illegalCount, sellerData.cid or '?'))

        TriggerClientEvent('ox_lib:notify', sellerData.src, {
            type = 'inform', title = 'ضريبة حماية',
            description = ('خُصم %s لعصابة %s'):format(
                Shared.FormatMoney(tax), (GangsCache[zone.gang_id] or {}).label or '?'),
        })
        -- update trade log row (آخر صف للنقطة)
        MySQL.update(
            'UPDATE family_trade_logs SET tax_amount = ?, tax_to_gang_id = ? WHERE point_id = ? ORDER BY id DESC LIMIT 1',
            { tax, zone.gang_id, point.id })
    end
    return tax
end

-- النسخة القديمة (item-by-item) — تبقى للـ backward compat
function ApplyProtectionTax(sellerSrc, buyerSrc, itemName, itemCount, totalPrice)
    if not totalPrice or totalPrice <= 0 then return totalPrice, 0, nil end
    if not Shared.IsIllegalItem(itemName) then return totalPrice, 0, nil end

    local sellerCoords = GetEntityCoords(GetPlayerPed(sellerSrc))
    local zone = FindZoneAt(sellerCoords.x, sellerCoords.y)
    if not zone then return totalPrice, 0, nil end
    if zone.war_locked == 1 then return totalPrice, 0, zone end

    local taxPercent = zone.protection_percent or 10.0
    local tax = math.floor(totalPrice * (taxPercent / 100.0))
    if tax <= 0 then return totalPrice, 0, zone end

    AddMoneyToVault(zone.gang_id, tax,
        ('بيع %s x%d بـ %d - من %s'):format(itemName, itemCount, totalPrice, GetCitizenId(sellerSrc) or '?'))

    return totalPrice - tax, tax, zone
end

exports('ApplyProtectionTax', ApplyProtectionTax)
exports('ApplyTradeProtectionTax', ApplyTradeProtectionTax)

RegisterNetEvent('qbx_families:server:reportSale', function(buyerSrc, itemName, count, price)
    local sellerSrc = source
    local final, tax, zone = ApplyProtectionTax(sellerSrc, buyerSrc, itemName, count, price)
    if tax > 0 and zone then
        local gang = GangsCache[zone.gang_id]
        TriggerClientEvent('ox_lib:notify', sellerSrc, {
            type = 'inform', title = 'ضريبة حماية',
            description = ('تم خصم %s (%.1f%%) لعصابة %s'):format(
                Shared.FormatMoney(tax), zone.protection_percent, gang and gang.label or '?'),
        })
    end
end)
