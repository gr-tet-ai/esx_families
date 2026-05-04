local function FamiliesUnixNow()
    if os and os.time then
        return FamiliesUnixNow()
    end
    if GetCloudTimeAsInt then
        return GetCloudTimeAsInt()
    end
    return math.floor((GetGameTimer and GetGameTimer() or 0) / 1000)
end

-- ============================================================
-- esx_families - Main Menu (F6) v0.4.0
-- قائمة موحّدة بـ ox_lib context menus (RTL Arabic-friendly)
-- لا NUI مخصصة — كل شيء عبر ox_lib (نظيف، سريع، متناسق)
-- ============================================================

-- ============================================================
-- Helpers
-- ============================================================
local function notify(t, msg, title)
    lib.notify({ type = t or 'inform', title = title, description = msg })
end

local function fmtMoney(n)
    if not n then return '$0' end
    return '$' .. tostring(n):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

local function getCtx()
    local done, result, err = false, nil, nil

    CreateThread(function()
        local ok, data = pcall(function()
            return lib.callback.await('qbx_families:server:getMyContext', false)
        end)
        if ok then
            result = data
        else
            err = tostring(data)
            print(('^1[esx_families]^7 F6 getMyContext failed: %s'):format(err))
        end
        done = true
    end)

    local deadline = GetGameTimer() + 4500
    while not done and GetGameTimer() < deadline do Wait(25) end
    if not done then
        return nil, 'timeout'
    end
    return result, err
end

-- ============================================================
-- القائمة الرئيسية
-- ============================================================
function OpenFamilyMainMenu()
    local ctx, ctxErr = getCtx()
    if not ctx then
        return notify('error', ('فشل تحميل بيانات F6 (%s) — اكتب /family_diag أو راجع Console'):format(ctxErr or 'unknown'))
    end
    -- v0.5.0: حدّث الكاش العام
    MyContext = ctx
    TriggerEvent('esx_families:client:contextUpdated', ctx)

    -- v0.5.0: F6 صراحة للقادة فقط
    if not ctx.canOpenF6 then
        return lib.alertDialog({
            header = '🏛️ نظام العوائل',
            content = 'لست في عائلة بعد.\n\n• ابحث عن **مكتب مبايعة** على الخريطة (أيقونة 🤝 برتقالية).\n• اقترب من الـ NPC واضغط [E] لتقديم طلب الانضمام.\n\n👤 لو أنت أدمن: استخدم **F9** لفتح لوحة الإدارة.',
            centered = true, size = 'md',
            labels = { confirm = 'حسناً' },
        })
    end

    local options = {}

    -- ========== لو عضو في عائلة ==========
    if ctx.gang then
        options[#options+1] = {
            title = ('🏛️  %s'):format(ctx.gang.label),
            description = ('رتبتك: %s\nالخزينة: %s | %d عضو | %d منطقة'):format(
                (ctx.rank and ctx.rank.label) or 'بدون رتبة',
                fmtMoney(ctx.vault and ctx.vault.money or 0),
                ctx.memberCount or 0,
                ctx.zoneCount or 0
            ),
            icon = 'house',
            iconColor = '#ffb000',
            readOnly = true,
        }

        options[#options+1] = {
            title = '📊 نظرة عامة',
            description = 'تفاصيل العائلة والمناطق والخزنة',
            icon = 'chart-line',
            onSelect = function() ShowFamilyOverview(ctx.gang.id) end,
        }

        options[#options+1] = {
            title = '👥 الأعضاء',
            description = 'عرض / دعوة / طرد / ترقية',
            icon = 'users',
            onSelect = function() OpenMembersMenu(ctx.gang.id) end,
        }

        -- v0.5.0: طلبات الانضمام (للقائد + من عنده can_invite)
        local canHandleRequests = ctx.isLeader or (ctx.rank and ctx.rank.can_invite == 1)
        if canHandleRequests then
            options[#options+1] = {
                title = '🤝 طلبات الانضمام',
                description = 'قبول/رفض اللاعبين الذين تقدموا للمبايعة',
                icon = 'user-plus',
                iconColor = '#22c55e',
                onSelect = function() OpenJoinRequestsMenu() end,
            }
        end

        -- v0.5.0: نقاط المبايعة (للقائد فقط — ينشئ/يحذف)
        if ctx.isLeader then
            options[#options+1] = {
                title = '📍 نقاط المبايعة',
                description = 'إنشاء/إدارة نقاط الانضمام لعائلتك',
                icon = 'map-pin',
                iconColor = '#f97316',
                onSelect = function() OpenMyRecruitmentMenu(ctx.gang.id) end,
            }
        end

        if ctx.isLeader or ctx.isAdmin then
            options[#options+1] = {
                title = '🎖️ الرتب والصلاحيات',
                description = 'إنشاء / تعديل / حذف الرتب',
                icon = 'medal',
                onSelect = function() OpenRanksMenu(ctx.gang.id) end,
            }
        end

        options[#options+1] = {
            title = '🗺️ مناطقي',
            description = 'عرض المناطق + تحديد على الخريطة',
            icon = 'map-location-dot',
            onSelect = function() ShowMyZones(ctx.gang.id) end,
        }

        if ctx.vault then
            options[#options+1] = {
                title = '🏦 الخزنة',
                description = ctx.vault.war_locked and '🔒 مقفلة (حرب)' or 'فتح / إيداع / سحب / مفاتيح',
                icon = 'vault',
                onSelect = function() OpenVaultMenu(ctx.gang.id) end,
            }
        end

        options[#options+1] = {
            title = '⚔️ الحروب',
            description = ctx.myWar
                and ('حرب نشطة: %s vs %s'):format(ctx.myWar.attacker_label, ctx.myWar.defender_label)
                or 'إعلان حرب / مجلس الحرب',
            icon = 'crossed-swords',
            iconColor = ctx.myWar and '#ff3b3b' or nil,
            onSelect = function() OpenWarsMenuFromF6() end,
        }

        -- v0.5.2: زر مباشر للقائد لإعلان حرب من F6 (shortcut)
        if ctx.isLeader and not ctx.myWar then
            options[#options+1] = {
                title = '⚡ إعلان حرب مباشر',
                description = 'اختر زون عدو لمهاجمته فوراً (للقائد فقط)',
                icon = 'bullseye',
                iconColor = '#ff6b00',
                onSelect = function()
                    if ShowAttackableZonesUI then
                        ShowAttackableZonesUI()
                    else
                        OpenWarsMenuFromF6()
                    end
                end,
            }
        end

        if not ctx.isLeader then
            options[#options+1] = {
                title = '🚪 مغادرة العائلة',
                description = 'الخروج من العضوية نهائياً',
                icon = 'door-open',
                iconColor = '#ff6b6b',
                onSelect = function()
                    local c = lib.alertDialog({
                        header = 'تأكيد المغادرة',
                        content = 'هل أنت متأكد من مغادرة العائلة؟',
                        centered = true, cancel = true,
                    })
                    if c == 'confirm' then
                        local ok, msg = lib.callback.await('qbx_families:server:leaveGang', false)
                        notify(ok and 'success' or 'error', msg)
                    end
                end,
            }
        end
    end

    -- ========== معلومات عامة ==========
    options[#options+1] = {
        title = '🌐 العائلات في السيرفر',
        description = 'قائمة بكل العائلات المسجلة',
        icon = 'globe',
        onSelect = function() ShowPublicGangsList() end,
    }

    options[#options+1] = {
        title = '📜 الحروب الجارية',
        description = 'عرض كل الحروب النشطة',
        icon = 'fire',
        onSelect = function() ShowPublicWarsList() end,
    }

    -- v0.5.0: زر تنبيه للأدمن — يقترح فتح F9
    if ctx.isAdmin then
        options[#options+1] = {
            title = '⚙️ لوحة الإدارة (F9)',
            description = 'إدارة كل العائلات والمناطق والخزائن ونقاط المبايعة',
            icon = 'screwdriver-wrench',
            iconColor = '#22c55e',
            onSelect = function() OpenAdminMenu() end,
        }
    end

    lib.registerContext({
        id = 'family_main_menu',
        title = '🏛️ ' .. (ctx.gang and ctx.gang.label or 'نظام العوائل'),
        options = options,
    })
    lib.showContext('family_main_menu')
end


-- ============================================================
-- نظرة عامة على عائلتي
-- ============================================================
function ShowFamilyOverview(gangId)
    local d = lib.callback.await('qbx_families:server:getGangDetails', false, gangId)
    if not d then return notify('error', 'تعذر تحميل التفاصيل') end

    local options = {
        { title = '🏛️ ' .. d.gang.label,
          description = 'الاسم البرمجي: ' .. d.gang.name .. ' | ID: ' .. d.gang.id, readOnly = true },
        { title = '👑 القائد', description = d.gang.leader_citizenid, readOnly = true },
    }

    if d.vault then
        options[#options+1] = {
            title = '🏦 الخزنة',
            description = ('الرصيد: %s%s'):format(
                fmtMoney(d.vault.money),
                d.vault.war_locked and ' | 🔒 مقفلة' or ''),
            icon = 'vault',
            onSelect = function() OpenVaultMenu(gangId) end,
        }
    else
        options[#options+1] = { title = '🏦 لا توجد خزنة', description = 'الأدمن يضيفها', readOnly = true }
    end

    options[#options+1] = {
        title = ('🗺️ المناطق (%d)'):format(#d.zones),
        description = 'عرض كل المناطق',
        icon = 'map',
        onSelect = function() ShowMyZones(gangId) end,
    }

    lib.registerContext({
        id = 'family_overview',
        title = '📊 ' .. d.gang.label,
        menu = 'family_main_menu',
        options = options,
    })
    lib.showContext('family_overview')
end

-- ============================================================
-- مناطق عائلتي
-- ============================================================
function ShowMyZones(gangId)
    local d = lib.callback.await('qbx_families:server:getGangDetails', false, gangId)
    if not d then return notify('error', 'فشل التحميل') end

    local options = {}
    if #d.zones == 0 then
        options[1] = { title = 'لا توجد مناطق لهذه العائلة', readOnly = true }
    else
        for _, z in ipairs(d.zones) do
            options[#options+1] = {
                title = '🗺️ ' .. z.name,
                description = ('شعاع %dم | حماية %.1f%%'):format(z.radius, z.protection_percent),
                icon = 'location-dot',
                onSelect = function()
                    SetNewWaypoint(z.center_x, z.center_y)
                    notify('inform', 'تم تحديد المنطقة على الخريطة', z.name)
                end,
            }
        end
    end

    lib.registerContext({
        id = 'family_my_zones', title = '🗺️ مناطقي',
        menu = 'family_main_menu', options = options,
    })
    lib.showContext('family_my_zones')
end

-- ============================================================
-- قائمة العائلات (عامة — للجميع)
-- ============================================================
function ShowPublicGangsList()
    local list = lib.callback.await('qbx_families:server:listGangsPublic', false)
    local options = {}
    if not list or #list == 0 then
        options[1] = { title = 'لا توجد عائلات بعد', readOnly = true }
    else
        for _, g in ipairs(list) do
            options[#options+1] = {
                title = ('🏛️ %s%s'):format(g.label, g.in_war and ' ⚔️' or ''),
                description = ('%d عضو | %d منطقة%s'):format(
                    g.member_count, g.zone_count,
                    g.in_war and ' | في حرب الآن' or ''),
                readOnly = true,
            }
        end
    end
    lib.registerContext({
        id = 'family_public_list', title = '🌐 العائلات',
        menu = 'family_main_menu', options = options,
    })
    lib.showContext('family_public_list')
end

-- ============================================================
-- قائمة الحروب (عامة)
-- ============================================================
function ShowPublicWarsList()
    local list = lib.callback.await('qbx_families:server:listActiveWars', false)
    local options = {}
    if not list or #list == 0 then
        options[1] = { title = 'لا توجد حروب نشطة حالياً', readOnly = true }
    else
        for _, w in ipairs(list) do
            local remain = math.max(0, (w.ends_at or 0) - FamiliesUnixNow())
            local mins = math.floor(remain / 60)
            options[#options+1] = {
                title = ('⚔️ %s ⚡ %s'):format(w.attacker, w.defender),
                description = ('المنطقة: %s | %d-%d | %s | %d دقيقة متبقية'):format(
                    w.zone, w.attacker_score, w.defender_score, w.status, mins),
                readOnly = true,
            }
        end
    end
    lib.registerContext({
        id = 'family_active_wars', title = '🔥 الحروب الجارية',
        menu = 'family_main_menu', options = options,
    })
    lib.showContext('family_active_wars')
end

-- ============================================================
-- Keymapping (F6)
-- ============================================================
RegisterCommand('familymenu', function()
    OpenFamilyMainMenu()
end, false)

RegisterKeyMapping('familymenu', 'فتح قائمة العوائل/العصابات', 'keyboard', 'F6')
TriggerEvent('chat:addSuggestion', '/familymenu', 'فتح قائمة العوائل والعصابات (F6)')

-- ============================================================
-- Keymapping (F9) — لوحة الإدارة المباشرة
-- ============================================================
RegisterCommand('familyadmin', function()
    -- يفحص السيرفر تلقائياً (IsAdmin) — لو OpenAdminForEveryone=true يفتح للكل
    local isAdmin = lib.callback.await('qbx_families:server:isAdmin', false)
    if not isAdmin then
        return notify('error', 'هذه اللوحة مخصصة للأدمن فقط')
    end
    OpenAdminMenu()
end, false)

RegisterKeyMapping('familyadmin', 'فتح لوحة إدارة العوائل', 'keyboard', Config.AdminKey or 'F9')
TriggerEvent('chat:addSuggestion', '/familyadmin', 'فتح لوحة إدارة العوائل (F9)')

