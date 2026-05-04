Config = {}

-- ============================================================
-- الإعدادات العامة
-- ============================================================
Config.Debug = false
Config.Locale = 'ar'

-- ============================================================
-- صلاحيات الآدمن
-- ============================================================
-- (1) جروبات QBox/ACE
Config.AdminGroups = { 'admin', 'god' }

-- (2) قائمة CitizenIDs ثابتة
Config.AdminCitizenIds = {
    -- 'ABC12345',
}

-- (3) قائمة Steam/License Identifiers
Config.AdminIdentifiers = {
    -- 'steam:110000100000000',
}

-- ============================================================
-- 🧪 وضع الاختبار (Testing Mode)
-- ============================================================
-- لو true → كل لاعب يصير "أدمن" تلقائياً (يفتح F9 لوحة الإدارة كاملة)
-- استخدمها فقط أثناء التجربة مع الأصدقاء، ثم رجّعها false قبل الإطلاق
Config.OpenAdminForEveryone = true  -- 🧪 TEST MODE: كل لاعب أدمن — رجّعها false قبل الإطلاق

-- مفتاح فتح لوحة الإدارة مباشرة (افتراضي F9)
Config.AdminKey = 'F9'

-- ============================================================
-- الخزنة
-- ============================================================
Config.MaxVaultKeys = 5
Config.VaultMarker = {
    type = 1,                                                  -- v0.5.0: cylinder (أوضح من النوع 27)
    size = vec3(1.6, 1.6, 1.0),                                -- v0.5.0: أكبر
    color = { r = 255, g = 215, b = 0, a = 180 },              -- ذهبي ساطع
    rotate = false,
}
Config.VaultInteractDistance = 2.0                             -- v0.5.0: من 1.5 → 2.0 (أسهل)

-- ============================================================
-- 🆕 v0.5.3: حد وزن صندوق العائلة (esx_inventory)
-- ============================================================
-- بالـ grams. كل قطعة لها وزن من ESX.Items. الافتراضي 200kg.
Config.StashMaxWeight = 200000

-- ============================================================
-- الزون
-- ============================================================
Config.ZoneNotifyCooldown = 60
Config.ZoneCheckInterval = 2000  -- 2 ثانية (كان 1500) — أخف على الـ client

-- ============================================================
-- نسبة الحماية
-- ============================================================
Config.MinProtectionPercent = 1.0
Config.MaxProtectionPercent = 30.0

-- ============================================================
-- المواد غير القانونية
-- (تُحوَّل إلى Set في Shared.IllegalItemsSet لـ O(1) lookup)
-- ============================================================
Config.IllegalItems = {
    'weed', 'weed_brick', 'cocaine', 'cocaine_brick',
    'meth', 'heroin', 'oxy', 'lsd',
    'weapon_pistol', 'weapon_smg', 'weapon_assaultrifle',
    'weapon_pumpshotgun', 'weapon_microsmg', 'weapon_combatpistol',
    'pistol_ammo', 'smg_ammo', 'rifle_ammo', 'shotgun_ammo',
}

-- ============================================================
-- بليبس الخريطة
-- ============================================================
Config.BlipSettings = {
    sprite = 84,
    display = 4,
    scale = 1.0,
    alpha = 180,
}

Config.RadiusBlip = {
    color = 1,
    alpha = 140,
    flashes = true,
    flashInterval = 600,
    highDetail = true,
}

Config.AvailableBlipColors = {
    [1] = 'أحمر', [2] = 'أخضر', [3] = 'أزرق', [5] = 'أصفر',
    [17] = 'برتقالي', [27] = 'وردي', [38] = 'بنفسجي', [40] = 'سماوي',
}

-- ============================================================
-- نقطة البيع
-- ============================================================
Config.TradePoint = {
    interactDistance = 2.0,
    drawDistance = 30.0,
    blip = {
        sprite = 500,
        color = 1,
        scale = 0.9,
        shortRange = true,
    },
    marker = {
        type = 1,
        size = vec3(2.0, 2.0, 1.0),
        color = { r = 255, g = 0, b = 0, a = 150 },
    },
    maxItemsPerSide = 4,
    maxPoints = 50,
}

-- ============================================================
-- الحرب (v0.3.0) — الافتراضيات هنا تُحدَّث ديناميكياً من family_admin_config
-- ============================================================
Config.War = {
    -- الـ ped في War Council (شكل الشخصية)
    councilPed = `s_m_m_highsec_01`,

    -- البليب على الخريطة
    councilBlip = {
        sprite = 487,    -- raid icon
        color = 1,
        scale = 1.0,
        label = 'War Council',
    },

    -- نسبة الكشف عن العضو في الزون (presence check)
    presenceCheckInterval = 60,  -- ثانية

    -- شعاع تأكيد القتل
    killConfirmRadius = 50.0,

    -- v0.6.0: نقاط حسب رتبة القتيل
    points = {
        boss = 5,        -- قائد / tier 1
        underboss = 3,   -- نائب / tier 2
        member = 1,      -- عضو / tier 3+
    },

    -- v0.6.0: anti-farm — نفس القتيل ما يحتسب عليه قتل ثاني خلال هذه المدة (ثواني)
    -- القاتل بدون cooldown (يقدر يقتل عدة لاعبين بتتابع)
    victimCooldownSec = 30,


    -- Cleanup للـ logs (قديم من X يوم)
    cleanupOlderThanDays = 30,

    -- Cleanup interval (دقائق)
    cleanupIntervalMinutes = 60,

    -- Test mode auto-disable (دقائق)
    testModeAutoDisableMinutes = 120,
}

-- ============================================================
-- الأداء (Performance tuning)
-- ============================================================
Config.Performance = {
    -- Batch write للـ vault money / war scores (ثوانٍ)
    batchWriteInterval = 30,

    -- Throttle للأحداث المتكررة (ms)
    killEventThrottle = 1000,

    -- Sleep في client zone-check threads
    clientIdleSleep = 2000,
    clientActiveSleep = 250,

    -- Max distance لرسم الـ markers
    markerDrawDistance = 30.0,
}
