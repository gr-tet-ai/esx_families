-- ============================================================
-- esx_families v0.5.3 — Custom DB Stash (esx_inventory compatible)
-- ============================================================
-- بديل لـ ox_inventory:RegisterStash
-- يستخدم جدول family_stash + esx items table للأوزان
-- ============================================================

local StashCache = {} -- [gangId] = { [itemName] = count }
local ItemsMeta  = {} -- [itemName] = { label, weight, max, ... } من ESX Items

-- تحميل metadata من ESX
CreateThread(function()
    while not ESX do Wait(100) end
    while not ESX.Items or next(ESX.Items) == nil do Wait(500) end
    for name, data in pairs(ESX.Items) do
        ItemsMeta[name] = {
            label  = data.label or name,
            weight = tonumber(data.weight) or 0,
        }
    end
    print(('[esx_families/stash] Loaded %d ESX item definitions'):format(table.count(ItemsMeta) or 0))
end)

local function getItemMeta(itemName)
    return ItemsMeta[itemName] or { label = itemName, weight = 100 }
end

-- حد الوزن الافتراضي
local DEFAULT_MAX_WEIGHT = (Config.StashMaxWeight or 200000) -- 200kg

-- ============================================================
-- Cache loader
-- ============================================================
local function loadStash(gangId)
    if StashCache[gangId] then return StashCache[gangId] end
    local rows = MySQL.query.await('SELECT item_name, count FROM family_stash WHERE gang_id = ?', { gangId })
    local map = {}
    for _, r in ipairs(rows or {}) do
        map[r.item_name] = (map[r.item_name] or 0) + tonumber(r.count or 0)
    end
    StashCache[gangId] = map
    return map
end

local function saveItem(gangId, itemName, count)
    if count <= 0 then
        MySQL.query.await('DELETE FROM family_stash WHERE gang_id = ? AND item_name = ?', { gangId, itemName })
        StashCache[gangId][itemName] = nil
    else
        MySQL.query.await(
            'INSERT INTO family_stash (gang_id, item_name, count) VALUES (?, ?, ?) ' ..
            'ON DUPLICATE KEY UPDATE count = VALUES(count)',
            { gangId, itemName, count }
        )
        StashCache[gangId][itemName] = count
    end
end

local function calcStashWeight(gangId)
    local total = 0
    for name, cnt in pairs(StashCache[gangId] or {}) do
        total = total + (getItemMeta(name).weight * cnt)
    end
    return total
end

-- ============================================================
-- Permissions
-- ============================================================
local function canAccessStash(src, gangId)
    local cid = GetCitizenId(src)
    if not cid then return false, 'لا يوجد لاعب' end
    if not GangsCache[gangId] then return false, 'العائلة غير موجودة' end
    if GangsCache[gangId].leader_citizenid == cid then return true end
    local row = MySQL.single.await(
        'SELECT 1 FROM family_members WHERE gang_id = ? AND citizenid = ? LIMIT 1',
        { gangId, cid }
    )
    if not row then return false, 'لست عضواً في هذه العائلة' end
    return true
end

local function logStashAction(src, action, gangId, itemName, count)
    local vault = VaultsCache and VaultsCache[gangId]
    if vault and LogVaultAction then
        LogVaultAction(vault.id, GetCitizenId(src), action, itemName, count, ('stash:gang%d'):format(gangId))
    end
end

-- ============================================================
-- Callbacks
-- ============================================================

-- جلب محتوى stash + جرد اللاعب
lib.callback.register('esx_families:server:stashGetContents', function(source, gangId)
    local ok, err = canAccessStash(source, gangId)
    if not ok then return nil, err end

    loadStash(gangId)
    local stashList = {}
    for name, cnt in pairs(StashCache[gangId]) do
        local meta = getItemMeta(name)
        stashList[#stashList+1] = {
            name = name, label = meta.label, count = cnt, weight = meta.weight,
        }
    end
    table.sort(stashList, function(a,b) return a.label < b.label end)

    -- جرد اللاعب
    local xPlayer = ESX.GetPlayerFromId(source)
    local myInv = {}
    if xPlayer then
        for _, it in ipairs(xPlayer.inventory or {}) do
            if it.count and it.count > 0 then
                myInv[#myInv+1] = {
                    name = it.name, label = it.label or it.name,
                    count = it.count, weight = it.weight or 0,
                }
            end
        end
        table.sort(myInv, function(a,b) return a.label < b.label end)
    end

    return {
        stash       = stashList,
        myInventory = myInv,
        currentWeight = calcStashWeight(gangId),
        maxWeight   = DEFAULT_MAX_WEIGHT,
    }
end)

-- إيداع
lib.callback.register('esx_families:server:stashDeposit', function(source, gangId, itemName, count)
    local ok, err = canAccessStash(source, gangId)
    if not ok then return false, err end

    count = math.floor(tonumber(count) or 0)
    if count < 1 then return false, 'الكمية غير صحيحة' end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'خطأ في اللاعب' end

    local item = xPlayer.getInventoryItem(itemName)
    if not item or (item.count or 0) < count then
        return false, 'لا تملك هذه الكمية'
    end

    loadStash(gangId)
    local meta = getItemMeta(itemName)
    local newWeight = calcStashWeight(gangId) + (meta.weight * count)
    if newWeight > DEFAULT_MAX_WEIGHT then
        return false, ('وزن الصندوق ممتلئ (الحد %s)'):format(Shared.FormatMoney(DEFAULT_MAX_WEIGHT))
    end

    xPlayer.removeInventoryItem(itemName, count)
    local newCount = (StashCache[gangId][itemName] or 0) + count
    saveItem(gangId, itemName, newCount)

    logStashAction(source, "stash_deposit", gangId, itemName, count)
    return true, ('تم إيداع %d × %s'):format(count, meta.label)
end)

-- سحب
lib.callback.register('esx_families:server:stashWithdraw', function(source, gangId, itemName, count)
    local ok, err = canAccessStash(source, gangId)
    if not ok then return false, err end

    count = math.floor(tonumber(count) or 0)
    if count < 1 then return false, 'الكمية غير صحيحة' end

    loadStash(gangId)
    local available = StashCache[gangId][itemName] or 0
    if available < count then
        return false, 'الكمية غير متوفرة في الصندوق'
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'خطأ في اللاعب' end

    local meta = getItemMeta(itemName)
    if not xPlayer.canCarryItem(itemName, count) then
        return false, 'لا يوجد مساحة في جردك'
    end

    xPlayer.addInventoryItem(itemName, count)
    saveItem(gangId, itemName, available - count)

    logStashAction(source, "stash_withdraw", gangId, itemName, count)
    return true, ('تم سحب %d × %s'):format(count, meta.label)
end)

-- helper count items in table
function table.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
