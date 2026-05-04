
-- ============================================================
-- v0.6.3: Canonical player identifier resolver
-- ESX Legacy multichar stores gameplay ownership as charN:<license hash>.
-- license:<hash> is only the account identifier and will NOT match family tables.
-- ============================================================
local function NormalizeFamilyIdentifier(value)
    if not value or value == '' then return nil end
    value = tostring(value)
    if value:match('^char%d+:') then return value end
    if value:match('^license:') then return value end
    return value
end

function GetCanonicalFamilyIdentifier(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end

    local xPlayer = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(src) or nil
    if xPlayer then
        -- ESX Legacy multichar: this is the character identifier, e.g. char1:xxxx.
        if xPlayer.identifier and tostring(xPlayer.identifier):match('^char%d+:') then
            return NormalizeFamilyIdentifier(xPlayer.identifier)
        end

        -- Compatibility for custom ESX forks that expose identifier through variables.
        if xPlayer.getIdentifier then
            local ok, ident = pcall(function() return xPlayer.getIdentifier() end)
            if ok and ident and tostring(ident):match('^char%d+:') then
                return NormalizeFamilyIdentifier(ident)
            end
        end
    end

    -- Fallback only. This is not preferred when charN exists.
    for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
        if tostring(identifier):match('^char%d+:') then
            return NormalizeFamilyIdentifier(identifier)
        end
    end
    for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
        if tostring(identifier):match('^license:') then
            return NormalizeFamilyIdentifier(identifier)
        end
    end

    return nil
end

-- ============================================================
-- qbx_families - Main Server (Init + Caches) v0.3.0
-- مُحسَّن: load batch واحد، spatial grid، batch writes
-- ============================================================

GangsCache       = {}
ZonesCache       = {}
VaultsCache      = {}
VaultKeysCache   = {}
TradePointsCache = {}

-- Pending writes (batch flush كل Config.Performance.batchWriteInterval)
PendingVaultMoneyWrites = {}  -- [vaultId] = newMoney

local function loadCache()
    local gangs = MySQL.query.await('SELECT * FROM family_gangs') or {}
    for i = 1, #gangs do GangsCache[gangs[i].id] = gangs[i] end

    local zones = MySQL.query.await('SELECT * FROM family_zones') or {}
    for i = 1, #zones do ZonesCache[zones[i].id] = zones[i] end

    -- بناء الـ spatial grid مرة واحدة
    Shared.RebuildSpatialGrid(ZonesCache)

    local vaults = MySQL.query.await('SELECT * FROM family_vaults') or {}
    for i = 1, #vaults do
        local v = vaults[i]
        VaultsCache[v.gang_id] = v
        VaultKeysCache[v.id] = {}
    end

    local keys = MySQL.query.await('SELECT * FROM family_vault_keys') or {}
    for i = 1, #keys do
        local k = keys[i]
        VaultKeysCache[k.vault_id] = VaultKeysCache[k.vault_id] or {}
        VaultKeysCache[k.vault_id][k.citizenid] = true
    end

    local tps = MySQL.query.await('SELECT * FROM family_trade_points') or {}
    for i = 1, #tps do TradePointsCache[tps[i].id] = tps[i] end

    print(('^2[qbx_families]^7 v0.3.0 loaded: %d gang | %d zone | %d vault | %d trade-point'):format(
        #gangs, #zones, #vaults, #tps))
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Wait(500)
    loadCache()
    -- بث أولي للجميع
    TriggerClientEvent('qbx_families:client:syncZones', -1, ZonesCache, GangsCache)
    TriggerClientEvent('qbx_families:client:syncTradePoints', -1, TradePointsCache)
end)

AddEventHandler('playerJoining', function()
    local src = source
    Wait(2000)
    TriggerClientEvent('qbx_families:client:syncZones', src, ZonesCache, GangsCache)
    TriggerClientEvent('qbx_families:client:syncTradePoints', src, TradePointsCache)
end)

-- ============================================================
-- IsAdmin (4 طرق)
-- ============================================================
function IsAdmin(src)
    if not src or src == 0 then return false end

    -- 🧪 وضع الاختبار: الكل أدمن
    if Config.OpenAdminForEveryone then return true end

    for _, group in ipairs(Config.AdminGroups or {}) do
        if IsPlayerAceAllowed(src, 'group.' .. group) or IsPlayerAceAllowed(src, group) then
            return true
        end
    end

    local ok, player = pcall(function() return ESXBridge.GetPlayer(src) end)
    if ok and player and player.PlayerData then
        local pgroup = player.PlayerData.group
            or (player.PlayerData.metadata and player.PlayerData.metadata.group)
            or (player.PlayerData.permission)
        if pgroup then
            for _, g in ipairs(Config.AdminGroups or {}) do
                if pgroup == g then return true end
            end
        end
        local cid = player.PlayerData.citizenid
        if cid then
            for _, c in ipairs(Config.AdminCitizenIds or {}) do
                if c == cid then return true end
            end
        end
    end

    local idents = GetPlayerIdentifiers(src) or {}
    for _, ident in ipairs(idents) do
        for _, allowed in ipairs(Config.AdminIdentifiers or {}) do
            if ident == allowed then return true end
        end
    end

    return false
end

function GetCitizenId(src)
    return GetCanonicalFamilyIdentifier(src)
end

function SyncZonesToAll()
    TriggerClientEvent('qbx_families:client:syncZones', -1, ZonesCache, GangsCache)
end

function SyncTradePointsToAll()
    TriggerClientEvent('qbx_families:client:syncTradePoints', -1, TradePointsCache)
end

---ربط نقطة البيع بأقرب زون يحتوي إحداثياتها (يُستدعى عند إنشاء/تعديل)
---@param point table
function AttachTradePointToZone(point)
    local zone = Shared.FindZoneAt(point.coords_x, point.coords_y, ZonesCache)
    if zone then
        point.zone_id = zone.id
        point.created_by_gang_id = zone.gang_id
        MySQL.update('UPDATE family_trade_points SET zone_id = ?, created_by_gang_id = ? WHERE id = ?',
            { zone.id, zone.gang_id, point.id })
    else
        point.zone_id = nil
        point.created_by_gang_id = nil
        MySQL.update('UPDATE family_trade_points SET zone_id = NULL, created_by_gang_id = NULL WHERE id = ?',
            { point.id })
    end
end

-- ============================================================
-- Vault helpers (مشتركة) — تُستخدم من vault.lua و protection.lua
-- ============================================================

---إضافة فلوس لخزنة عصابة (دالة مركزية — كانت "شبح" في v0.2.0)
---@param gangId number
---@param amount number
---@param note? string
---@return boolean ok
function AddMoneyToVault(gangId, amount, note)
    if not gangId or not amount or amount <= 0 then return false end
    local vault = VaultsCache[gangId]
    if not vault then return false end

    -- لو الخزنة مقفلة بسبب حرب → نسجل لكن ما نضيف (تجمد الإيرادات)
    if vault.war_locked == 1 then
        Shared.Debug(('AddMoneyToVault skipped (war_locked): gang=%d amount=%d'):format(gangId, amount))
        return false
    end

    vault.money = (vault.money or 0) + math.floor(amount)
    -- Batch write (مو فوري) — يطلع كل 30 ثانية
    PendingVaultMoneyWrites[vault.id] = vault.money

    -- log فوري
    if LogVaultAction then
        LogVaultAction(vault.id, nil, 'income', nil, amount, note or 'auto')
    end
    return true
end

-- ============================================================
-- Batch Writer Thread — كل Config.Performance.batchWriteInterval
-- يطبق التحديثات المعلقة دفعة واحدة على DB
-- ============================================================
CreateThread(function()
    local interval = (Config.Performance and Config.Performance.batchWriteInterval or 30) * 1000
    while true do
        Wait(interval)
        -- vault money batch
        if next(PendingVaultMoneyWrites) then
            for vaultId, money in pairs(PendingVaultMoneyWrites) do
                MySQL.update('UPDATE family_vaults SET money = ? WHERE id = ?', { money, vaultId })
            end
            PendingVaultMoneyWrites = {}
        end
    end
end)

-- ============================================================
-- Force flush عند توقف السكربت (ما نضيع بيانات)
-- ============================================================
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if next(PendingVaultMoneyWrites) then
        for vaultId, money in pairs(PendingVaultMoneyWrites) do
            MySQL.update.await('UPDATE family_vaults SET money = ? WHERE id = ?', { money, vaultId })
        end
    end
    print('^2[qbx_families]^7 batch writes flushed on stop')
end)
