-- ============================================================
-- esx_families - ESX Bridge v0.3.0 (Hardened)
-- يُحمَّل قبل باقي ملفات السيرفر (راجع fxmanifest)
-- يوفّر API موحّد بنفس شكل qbx_core للتوافق مع باقي الكود
--
-- يدعم: ESX Legacy (1.10+) و ESX 1.x القديم
-- ============================================================

-- ============================================================
-- (1) الحصول على ESX object (يدعم كلا الطريقتين القديم والجديد)
-- ============================================================
ESX = nil

local function initESX()
    -- ESX Legacy (الجديد): exports
    local ok, obj = pcall(function()
        return exports['es_extended']:getSharedObject()
    end)
    if ok and obj then
        ESX = obj
        return true
    end

    -- ESX 1.x القديم: TriggerEvent
    TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
    if ESX then return true end

    return false
end

if not initESX() then
    print('^1[esx_families] ERROR:^7 لم يتم العثور على es_extended! تأكد إنه يبدأ قبل esx_families.')
    return
end

ESXBridge = {}

-- ============================================================
-- (2) Helper آمن: استدعاء method قد يكون موجود أو لا
-- ============================================================
local function safeCall(obj, methodName, ...)
    if not obj or type(obj[methodName]) ~= 'function' then return nil end
    local ok, result = pcall(obj[methodName], obj, ...)
    if ok then return result end
    -- جرب بدون self (بعض ESX versions تستخدم functions مو methods)
    local ok2, result2 = pcall(obj[methodName], ...)
    if ok2 then return result2 end
    return nil
end

-- ============================================================
-- (3) WrapPlayer: يحوّل xPlayer (ESX) إلى object يشبه Qbox
--   - PlayerData هي metatable (lazy) — money.cash تُقرأ live من xPlayer
--   - Functions.RemoveMoney/AddMoney تستخدم ESX APIs مع رجوع boolean صريح
-- ============================================================
local function wrapPlayer(xPlayer)
    if not xPlayer then return nil end

    -- محاولة استخراج identifier — ESX legacy يستخدم .identifier مباشرة
    local identifier = xPlayer.identifier or xPlayer.getIdentifier and xPlayer.getIdentifier() or nil
    if not identifier then return nil end

    local function getCash()
        if type(xPlayer.getMoney) == 'function' then
            return xPlayer.getMoney() or 0
        end
        -- fallback: account 'money' أو 'cash'
        local acc = xPlayer.getAccount and (xPlayer.getAccount('money') or xPlayer.getAccount('cash'))
        return (acc and acc.money) or 0
    end

    local function getBank()
        local acc = xPlayer.getAccount and xPlayer.getAccount('bank')
        return (acc and acc.money) or 0
    end

    local function getGroup()
        if type(xPlayer.getGroup) == 'function' then
            return xPlayer.getGroup() or 'user'
        end
        return xPlayer.group or 'user'
    end

    local wrapped = {}

    -- PlayerData كـ metatable لقراءة live values
    local pd = {}
    setmetatable(pd, {
        __index = function(_, key)
            if key == 'source' then return xPlayer.source end
            if key == 'citizenid' then return identifier end
            if key == 'license' then return identifier end
            if key == 'group' then return getGroup() end
            if key == 'permission' then return getGroup() end
            if key == 'money' then
                return setmetatable({}, {
                    __index = function(_, k)
                        if k == 'cash' then return getCash() end
                        if k == 'bank' then return getBank() end
                        return 0
                    end
                })
            end
            if key == 'metadata' then
                return { group = getGroup() }
            end
            if key == 'charinfo' then
                local first = xPlayer.get and xPlayer.get('firstName') or ''
                local last  = xPlayer.get and xPlayer.get('lastName') or ''
                if first == '' and xPlayer.getName then first = xPlayer.getName() end
                return { firstname = first, lastname = last }
            end
            if key == 'job' then
                if type(xPlayer.getJob) == 'function' then return xPlayer.getJob() end
                return xPlayer.job or { name = 'unemployed', grade = 0 }
            end
            return nil
        end
    })
    wrapped.PlayerData = pd

    -- Functions: ترجع boolean صريح (success/fail) — نتحقق يدوياً
    wrapped.Functions = {
        RemoveMoney = function(account, amount, reason)
            amount = tonumber(amount)
            if not amount or amount <= 0 then return false end
            account = account or 'cash'
            reason = reason or 'esx_families'

            if account == 'cash' or account == 'money' then
                local cur = getCash()
                if cur < amount then return false end
                if type(xPlayer.removeMoney) == 'function' then
                    local ok = pcall(xPlayer.removeMoney, amount, reason)
                    if not ok then
                        -- بعض ESX versions ما تقبل reason
                        ok = pcall(xPlayer.removeMoney, amount)
                    end
                    return ok
                end
                return false
            else
                if type(xPlayer.removeAccountMoney) ~= 'function' then return false end
                local acc = xPlayer.getAccount and xPlayer.getAccount(account)
                if not acc or (acc.money or 0) < amount then return false end
                local ok = pcall(xPlayer.removeAccountMoney, account, amount, reason)
                if not ok then
                    ok = pcall(xPlayer.removeAccountMoney, account, amount)
                end
                return ok
            end
        end,

        AddMoney = function(account, amount, reason)
            amount = tonumber(amount)
            if not amount or amount <= 0 then return false end
            account = account or 'cash'
            reason = reason or 'esx_families'

            if account == 'cash' or account == 'money' then
                if type(xPlayer.addMoney) == 'function' then
                    local ok = pcall(xPlayer.addMoney, amount, reason)
                    if not ok then ok = pcall(xPlayer.addMoney, amount) end
                    return ok
                end
                return false
            else
                if type(xPlayer.addAccountMoney) ~= 'function' then return false end
                local ok = pcall(xPlayer.addAccountMoney, account, amount, reason)
                if not ok then ok = pcall(xPlayer.addAccountMoney, account, amount) end
                return ok
            end
        end,
    }

    -- مرجع للـ xPlayer الأصلي (للحالات المتقدمة)
    wrapped._xPlayer = xPlayer

    return wrapped
end

-- ============================================================
-- (4) API public — تستخدمه باقي ملفات السيرفر
-- ============================================================

---@param src number
---@return table|nil player (Qbox-like wrapped player)
function ESXBridge.GetPlayer(src)
    src = tonumber(src)
    if not src or src == 0 then return nil end
    if not ESX or type(ESX.GetPlayerFromId) ~= 'function' then return nil end
    local xPlayer = ESX.GetPlayerFromId(src)
    return wrapPlayer(xPlayer)
end

---@param identifier string ESX identifier (= citizenid)
---@return table|nil player
function ESXBridge.GetPlayerByCitizenId(identifier)
    if not identifier or identifier == '' then return nil end
    if not ESX or type(ESX.GetPlayerFromIdentifier) ~= 'function' then return nil end
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    return wrapPlayer(xPlayer)
end

-- ============================================================
-- (5) Citizen ID Normalization & Validation (v0.5.0)
-- ============================================================
-- يقبل أشكال متعددة من المُدخل ويرجّع identifier موحّد
-- مدخلات صحيحة: "license:abc..." | "abc..." (يضيف license: تلقائياً) | "char1:abc..."
---@param raw string|nil
---@return string|nil normalized
function ESXBridge.NormalizeCitizenId(raw)
    if not raw or type(raw) ~= 'string' then return nil end
    raw = raw:gsub('^%s+', ''):gsub('%s+$', '')  -- trim
    if raw == '' then return nil end

    -- لو فيه ':' افترض إنه identifier كامل
    if raw:find(':') then return raw end

    -- لو نص hex خام (مثل license بدون البادئة) — أضف license:
    if raw:match('^[%w]+$') and #raw >= 16 then
        return 'license:' .. raw
    end
    return raw
end

---يتحقق إن citizenid موجود في DB (عبر بحث في users) أو حالياً أونلاين
---@param cid string
---@return boolean exists, number|nil src
function ESXBridge.CitizenExists(cid)
    if not cid then return false end
    -- تحقق أونلاين
    local xp = ESX.GetPlayerFromIdentifier(cid)
    if xp then return true, xp.source end
    -- تحقق DB (ESX users table)
    local row = MySQL.scalar.await('SELECT identifier FROM users WHERE identifier = ? LIMIT 1', { cid })
    return row ~= nil, nil
end

---يجد source لـ citizenid لو أونلاين
---@param cid string
---@return number|nil src
function ESXBridge.GetSourceByCitizenId(cid)
    if not cid then return nil end
    local xp = ESX.GetPlayerFromIdentifier(cid)
    return xp and xp.source or nil
end

print('^2[esx_families]^7 ESX Bridge v0.5.0 loaded ✓ (ESX object: ' .. tostring(ESX ~= nil) .. ')')
