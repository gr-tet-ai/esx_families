-- ============================================================
-- qbx_families - Admin Config (Dynamic Settings) v0.3.0
-- إعدادات key-value يقدر الآدمن يعدلها بدون إعادة تشغيل
-- مع نظام Test Mode للأدمن
-- ============================================================

AdminConfig = {}  -- [key] = value (cached)

local function loadAdminConfig()
    local rows = MySQL.query.await('SELECT config_key, config_value FROM family_admin_config') or {}
    for i = 1, #rows do
        AdminConfig[rows[i].config_key] = rows[i].config_value
    end
    print(('^2[qbx_families]^7 admin_config loaded: %d keys'):format(#rows))
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Wait(700)  -- بعد main.lua
    loadAdminConfig()
end)

-- ============================================================
-- Helpers (تُستخدم من wars.lua و trade.lua...)
-- ============================================================
---@param key string
---@param default? any
---@return any
function GetAdminConfig(key, default)
    return AdminConfig[key] or default
end

---@param key string
---@return number
function GetAdminConfigNumber(key, default)
    return tonumber(AdminConfig[key]) or default or 0
end

---@param key string
---@return table|nil
function GetAdminConfigJSON(key)
    local v = AdminConfig[key]
    if not v then return nil end
    local ok, decoded = pcall(json.decode, v)
    return ok and decoded or nil
end

---حفظ قيمة (يحدّث DB + Cache)
---@param key string
---@param value string|number|table
---@return boolean ok
function SetAdminConfig(key, value)
    if type(value) == 'table' then value = json.encode(value) end
    value = tostring(value)
    MySQL.query.await([[
        INSERT INTO family_admin_config (config_key, config_value) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE config_value = VALUES(config_value)
    ]], { key, value })
    AdminConfig[key] = value
    return true
end

-- ============================================================
-- Test Mode — للأختبار بـ عدد قليل من اللاعبين
-- ============================================================

---@return boolean enabled
function IsTestMode()
    if GetAdminConfigNumber('test_mode_enabled', 0) ~= 1 then return false end
    local expires = GetAdminConfigNumber('test_mode_expires_at', 0)
    if expires > 0 and os.time() > expires then
        -- انتهى — أطفئ تلقائياً
        SetAdminConfig('test_mode_enabled', 0)
        SetAdminConfig('test_mode_expires_at', 0)
        print('^3[qbx_families]^7 test_mode auto-disabled (expired)')
        return false
    end
    return true
end

---يفعّل test mode لمدة Config.War.testModeAutoDisableMinutes
function EnableTestMode()
    -- تحقق: لا يُفعّل لو فيه حرب حقيقية نشطة (غير test mode)
    local activeWars = MySQL.scalar.await([[
        SELECT COUNT(*) FROM family_wars
        WHERE status IN ('preparing','active','overtime') AND is_test_mode = 0
    ]]) or 0
    if activeWars > 0 then
        return false, 'لا يمكن تفعيل test mode أثناء حرب حقيقية نشطة'
    end

    local minutes = (Config.War and Config.War.testModeAutoDisableMinutes) or 120
    local expires = os.time() + (minutes * 60)
    SetAdminConfig('test_mode_enabled', 1)
    SetAdminConfig('test_mode_expires_at', expires)
    print(('^3[qbx_families]^7 test_mode ENABLED for %d minutes'):format(minutes))
    return true, ('Test Mode مُفعّل لمدة %d دقيقة'):format(minutes)
end

function DisableTestMode()
    SetAdminConfig('test_mode_enabled', 0)
    SetAdminConfig('test_mode_expires_at', 0)
    print('^3[qbx_families]^7 test_mode DISABLED')
end

-- ============================================================
-- Get effective war values (تحترم test_mode)
-- ============================================================
---يرجع قيم الحرب — في test mode بعضها يصير mocked
---@return table values
function GetWarConfig()
    local testMode = IsTestMode()
    if testMode then
        return {
            cost = 0,
            duration_minutes = 5,
            prep_minutes = 1,
            forfeit_minutes = 1,
            overtime_minutes = 2,
            cooldown_hours = 0,
            min_members = 0,
            loot_percent = GetAdminConfigNumber('war_loot_percent', 30),
            surrender_loot_percent = GetAdminConfigNumber('war_surrender_loot_percent', 50),
            is_test_mode = true,
        }
    end
    return {
        cost = GetAdminConfigNumber('war_cost', 100000),
        duration_minutes = GetAdminConfigNumber('war_duration_minutes', 60),
        prep_minutes = GetAdminConfigNumber('war_prep_minutes', 1440),
        forfeit_minutes = GetAdminConfigNumber('war_forfeit_minutes', 30),
        overtime_minutes = GetAdminConfigNumber('war_overtime_minutes', 10),
        cooldown_hours = GetAdminConfigNumber('war_cooldown_hours', 48),
        min_members = GetAdminConfigNumber('war_min_members', 3),
        loot_percent = GetAdminConfigNumber('war_loot_percent', 30),
        surrender_loot_percent = GetAdminConfigNumber('war_surrender_loot_percent', 50),
        is_test_mode = false,
    }
end

-- ============================================================
-- Callbacks للـ NUI (الآدمن editor)
-- ============================================================
lib.callback.register('qbx_families:server:getAdminConfig', function(source)
    if not IsAdmin(source) then return {} end
    return AdminConfig
end)

lib.callback.register('qbx_families:server:setAdminConfig', function(source, key, value)
    if not IsAdmin(source) then return false, 'للآدمن فقط' end
    if not key then return false, 'key مطلوب' end
    SetAdminConfig(key, value)
    return true, 'تم الحفظ'
end)

lib.callback.register('qbx_families:server:isTestMode', function(source)
    return IsTestMode()
end)

-- Exports
exports('GetAdminConfig', GetAdminConfig)
exports('GetAdminConfigNumber', GetAdminConfigNumber)
exports('SetAdminConfig', SetAdminConfig)
exports('IsTestMode', IsTestMode)
exports('GetWarConfig', GetWarConfig)
