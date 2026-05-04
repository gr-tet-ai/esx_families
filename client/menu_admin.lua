-- ============================================================
-- esx_families - Admin Menu v0.4.0
-- لوحة الإدارة الشاملة (إنشاء/إدارة/حذف)
-- ============================================================

local function notify(t, msg, title)
    lib.notify({ type = t or 'inform', title = title, description = msg })
end

local BLIP_COLORS = {
    { value = 1,  label = '🔴 أحمر' },
    { value = 2,  label = '🟢 أخضر' },
    { value = 3,  label = '🔵 أزرق' },
    { value = 5,  label = '🟡 أصفر' },
    { value = 17, label = '🟠 برتقالي' },
    { value = 27, label = '🩷 وردي' },
    { value = 38, label = '🟣 بنفسجي' },
    { value = 40, label = '🩵 سماوي' },
    { value = 46, label = '⚪ أبيض' },
    { value = 81, label = '🟤 بني' },
}

-- ============================================================
-- لوحة الأدمن الرئيسية
-- ============================================================
function OpenAdminMenu()
    lib.registerContext({
        id = 'family_admin_menu',
        title = '⚙️ لوحة الإدارة (F9)',
        options = {
            { title = '🏛️ العائلات', description = 'إنشاء / تعديل / حذف',
              icon = 'house', onSelect = function() OpenAdminGangsMenu() end },
            { title = '🗺️ المناطق', description = 'إنشاء عند موقعي / حذف',
              icon = 'map', onSelect = function() OpenAdminZonesMenu() end },
            { title = '🏦 الخزائن', description = 'إنشاء / حذف',
              icon = 'vault', onSelect = function() OpenAdminVaultsMenu() end },
            { title = '💲 نقاط البيع', description = 'إنشاء / تعيين عائلة / حذف',
              icon = 'dollar-sign', onSelect = function() OpenAdminTradeMenu() end },
            { title = '🤝 نقاط المبايعة', description = 'إنشاء/حذف نقاط الانضمام لأي عائلة',
              icon = 'handshake', iconColor = '#f97316',
              onSelect = function() OpenAdminRecruitmentMenu() end },
            { title = '📨 طلبات الانضمام (الكل)', description = 'مراجعة كل الطلبات في السيرفر',
              icon = 'envelope', iconColor = '#22c55e',
              onSelect = function() OpenAdminAllRequestsMenu() end },
            { title = '⚔️ إدارة الحروب', description = 'إنهاء / إلغاء / فرض / Test Mode',
              icon = 'crossed-swords', onSelect = function() OpenAdminWarsMenu() end },
            { title = '📍 War Council', description = 'تحديد إحداثيات هنا',
              icon = 'flag', onSelect = function() AdminSetWarCouncil() end },
        },
    })
    lib.showContext('family_admin_menu')
end

-- ============================================================
-- إدارة العائلات
-- ============================================================
function OpenAdminGangsMenu()
    local gangs = lib.callback.await('qbx_families:server:getAllGangs', false)
    local options = {
        { title = '➕ إنشاء عائلة جديدة', icon = 'plus', iconColor = '#22c55e',
          onSelect = function() AdminCreateGangFlow() end },
        { title = ('🏛️ إجمالي: %d عائلة'):format(#(gangs or {})), readOnly = true },
    }
    for _, g in ipairs(gangs or {}) do
        options[#options+1] = {
            title = '🏛️ ' .. g.label,
            description = ('ID: %d | الاسم: %s | القائد: %s'):format(g.id, g.name, g.leader_citizenid),
            onSelect = function() OpenAdminGangActions(g) end,
        }
    end
    lib.registerContext({
        id = 'family_admin_gangs', title = '🏛️ العائلات',
        menu = 'family_admin_menu', options = options,
    })
    lib.showContext('family_admin_gangs')
end

function OpenAdminGangActions(g)
    lib.registerContext({
        id = 'family_admin_gang_actions',
        title = '⚙️ ' .. g.label,
        menu = 'family_admin_gangs',
        options = {
            { title = 'ID: ' .. g.id .. ' | الاسم: ' .. g.name, readOnly = true },
            { title = 'القائد الحالي: ' .. g.leader_citizenid, readOnly = true },
            { title = '👑 تغيير القائد', icon = 'crown',
              onSelect = function() AdminChangeLeaderFlow(g) end },
            { title = '👥 إدارة الأعضاء', icon = 'users',
              onSelect = function() OpenMembersMenu(g.id) end },
            { title = '🎖️ إدارة الرتب', icon = 'medal',
              onSelect = function() OpenRanksMenu(g.id) end },
            { title = '🗑️ حذف العائلة كاملة',
              description = 'يحذف الأعضاء + المناطق + الخزنة + الرتب',
              icon = 'trash', iconColor = '#ff3b3b',
              onSelect = function() AdminDeleteGangFlow(g) end },
        },
    })
    lib.showContext('family_admin_gang_actions')
end

function AdminCreateGangFlow()
    local online = lib.callback.await('qbx_families:server:getOnlinePlayers', false) or {}
    if #online == 0 then return notify('error', 'لا يوجد لاعبون أونلاين لاختيار قائد') end
    local input = lib.inputDialog('➕ إنشاء عائلة جديدة', {
        { type = 'input',  label = 'الاسم البرمجي (إنجليزي)', placeholder = 'lacosa',
          required = true, min = 2, max = 30 },
        { type = 'input',  label = 'الاسم الظاهر', placeholder = 'La Cosa Nostra',
          required = true, min = 2, max = 50 },
        { type = 'select', label = 'القائد (لاعب أونلاين)',
          required = true, options = online, searchable = true },
        { type = 'select', label = 'لون البليب', options = BLIP_COLORS, default = 1 },
    })
    if not input then return end
    local ok, msg = lib.callback.await('qbx_families:server:adminCreateGang', false,
        input[1], input[2], input[3], tonumber(input[4]) or 1)
    notify(ok and 'success' or 'error', msg)
    if ok then Wait(300); OpenAdminGangsMenu() end
end

function AdminChangeLeaderFlow(g)
    local online = lib.callback.await('qbx_families:server:getOnlinePlayers', false) or {}
    if #online == 0 then return notify('error', 'لا يوجد لاعبون أونلاين') end
    local input = lib.inputDialog('👑 تغيير قائد ' .. g.label, {
        { type = 'select', label = 'القائد الجديد (لاعب أونلاين)',
          required = true, options = online, searchable = true },
    })
    if not input then return end
    local c = lib.alertDialog({
        header = 'تأكيد تغيير القائد',
        content = ('سيصبح %s قائداً لعائلة %s. القائد القديم يبقى عضواً.'):format(input[1], g.label),
        centered = true, cancel = true,
    })
    if c ~= 'confirm' then return end
    local ok, msg = lib.callback.await('qbx_families:server:adminChangeLeader', false, g.id, input[1])
    notify(ok and 'success' or 'error', msg)
    if ok then Wait(300); OpenAdminGangsMenu() end
end

function AdminDeleteGangFlow(g)
    local c = lib.alertDialog({
        header = '⚠️ حذف العائلة نهائياً',
        content = ('هل أنت متأكد من حذف "%s"؟\nسيتم حذف:\n• كل الأعضاء\n• كل المناطق\n• الخزنة وأموالها\n• كل الرتب\nلا يمكن التراجع!'):format(g.label),
        centered = true, cancel = true,
    })
    if c ~= 'confirm' then return end
    local ok, msg = lib.callback.await('qbx_families:server:adminDeleteGang', false, g.id)
    notify(ok and 'success' or 'error', msg)
    if ok then Wait(300); OpenAdminGangsMenu() end
end

-- ============================================================
-- إدارة المناطق
-- ============================================================
function OpenAdminZonesMenu()
    local zones = lib.callback.await('qbx_families:server:getAllZonesAdmin', false)
    local options = {
        { title = '➕ إنشاء منطقة عند موقعي', icon = 'plus', iconColor = '#22c55e',
          onSelect = function() AdminCreateZoneFlow() end },
        { title = ('🗺️ إجمالي: %d منطقة'):format(#(zones or {})), readOnly = true },
    }
    for _, z in ipairs(zones or {}) do
        options[#options+1] = {
            title = ('🗺️ %s%s'):format(z.name, z.in_war and ' ⚔️' or ''),
            description = ('ID:%d | %s | شعاع %dم | حماية %.1f%%%s'):format(
                z.id, z.gang_label, z.radius, z.protection_percent,
                z.in_war and ' | في حرب' or ''),
            onSelect = function() OpenAdminZoneActions(z) end,
        }
    end
    lib.registerContext({
        id = 'family_admin_zones', title = '🗺️ المناطق',
        menu = 'family_admin_menu', options = options,
    })
    lib.showContext('family_admin_zones')
end

function OpenAdminZoneActions(z)
    lib.registerContext({
        id = 'family_admin_zone_actions',
        title = '🗺️ ' .. z.name,
        menu = 'family_admin_zones',
        options = {
            { title = 'ID: ' .. z.id, readOnly = true },
            { title = 'العائلة: ' .. (z.gang_label or '?'), readOnly = true },
            { title = ('شعاع: %dم | حماية: %.1f%%'):format(z.radius, z.protection_percent), readOnly = true },
            { title = '📍 وضع علامة على الخريطة', icon = 'location-dot',
              onSelect = function()
                  SetNewWaypoint(z.center_x, z.center_y)
                  notify('inform', 'تم تحديد المنطقة', z.name)
              end },
            { title = '🗑️ حذف المنطقة', icon = 'trash', iconColor = '#ff3b3b',
              onSelect = function()
                  if z.in_war then return notify('error', 'لا يمكن حذف منطقة في حرب') end
                  local c = lib.alertDialog({
                      header = 'تأكيد الحذف',
                      content = 'متأكد من حذف "' .. z.name .. '"؟',
                      centered = true, cancel = true,
                  })
                  if c == 'confirm' then
                      local ok, msg = lib.callback.await('qbx_families:server:adminDeleteZone', false, z.id)
                      notify(ok and 'success' or 'error', msg)
                      if ok then Wait(300); OpenAdminZonesMenu() end
                  end
              end },
        },
    })
    lib.showContext('family_admin_zone_actions')
end

function AdminCreateZoneFlow()
    local gangs = lib.callback.await('qbx_families:server:getAllGangs', false)
    if not gangs or #gangs == 0 then
        return notify('error', 'أنشئ عائلة أولاً قبل إضافة منطقة')
    end
    local opts = {}
    for _, g in ipairs(gangs) do
        opts[#opts+1] = { value = g.id, label = ('%s (ID:%d)'):format(g.label, g.id) }
    end
    local input = lib.inputDialog('➕ منطقة جديدة عند موقعك', {
        { type = 'select', label = 'العائلة المالكة', options = opts, required = true },
        { type = 'input',  label = 'اسم المنطقة', placeholder = 'Vinewood Hills', required = true, max = 50 },
        { type = 'slider', label = 'الشعاع (متر)', min = 20, max = 500, default = 80, step = 10 },
        { type = 'slider', label = 'نسبة الحماية %', min = 1, max = 30, default = 10, step = 1 },
    })
    if not input then return end
    local ok, msg = lib.callback.await('qbx_families:server:adminCreateZone', false,
        tonumber(input[1]), input[2], tonumber(input[3]), tonumber(input[4]))
    notify(ok and 'success' or 'error', msg)
    if ok then Wait(300); OpenAdminZonesMenu() end
end

-- ============================================================
-- إدارة الخزائن
-- ============================================================
function OpenAdminVaultsMenu()
    local gangs = lib.callback.await('qbx_families:server:getAllGangs', false)
    local options = {
        { title = '➕ إنشاء خزنة عند موقعي', icon = 'plus', iconColor = '#22c55e',
          onSelect = function() AdminCreateVaultFlow() end },
    }
    for _, g in ipairs(gangs or {}) do
        local hasVault = CurrentVaults and CurrentVaults[g.id] ~= nil
        options[#options+1] = {
            title = ('🏦 %s'):format(g.label),
            description = hasVault and 'لديها خزنة — اضغط للحذف' or 'بدون خزنة',
            iconColor = hasVault and '#ff3b3b' or '#888',
            onSelect = function()
                if not hasVault then return notify('inform', 'هذه العائلة بدون خزنة') end
                local c = lib.alertDialog({
                    header = 'تأكيد حذف الخزنة',
                    content = ('متأكد من حذف خزنة %s؟ المفاتيح ستُحذف معها.'):format(g.label),
                    centered = true, cancel = true,
                })
                if c == 'confirm' then
                    local ok, msg = lib.callback.await('qbx_families:server:adminDeleteVault', false, g.id)
                    notify(ok and 'success' or 'error', msg)
                    if ok then Wait(300); OpenAdminVaultsMenu() end
                end
            end,
        }
    end
    lib.registerContext({
        id = 'family_admin_vaults', title = '🏦 الخزائن',
        menu = 'family_admin_menu', options = options,
    })
    lib.showContext('family_admin_vaults')
end

function AdminCreateVaultFlow()
    local gangs = lib.callback.await('qbx_families:server:getAllGangs', false)
    if not gangs or #gangs == 0 then return notify('error', 'لا توجد عائلات') end
    local opts = {}
    for _, g in ipairs(gangs) do
        opts[#opts+1] = { value = g.id, label = ('%s (ID:%d)'):format(g.label, g.id) }
    end
    local input = lib.inputDialog('🏦 إنشاء خزنة عند موقعك', {
        { type = 'select', label = 'العائلة', options = opts, required = true },
    })
    if not input then return end
    local ok, msg = lib.callback.await('qbx_families:server:adminCreateVault', false, tonumber(input[1]))
    notify(ok and 'success' or 'error', msg)
    if ok then Wait(300); OpenAdminVaultsMenu() end
end

-- ============================================================
-- نقاط البيع (Trade Points)
-- ============================================================
function OpenAdminTradeMenu()
    local list = lib.callback.await('qbx_families:server:getAllTradePoints', false)
    local options = {
        { title = '➕ إنشاء نقطة بيع عند موقعي', icon = 'plus', iconColor = '#22c55e',
          onSelect = function() AdminCreateTradeFlow() end },
        { title = ('💲 إجمالي: %d نقطة'):format(#(list or {})), readOnly = true },
    }
    for _, p in ipairs(list or {}) do
        options[#options+1] = {
            title = '💲 ' .. p.name,
            description = ('ID:%d | %s%s'):format(
                p.id,
                p.zone_id and 'داخل زون' or 'خارج زون (ممنوعات معطّلة)',
                p.war_disabled == 1 and ' | 🔒 حرب' or ''),
            onSelect = function()
                local actions = {
                    { title = 'ID: ' .. p.id, readOnly = true },
                    { title = '📍 وضع علامة', icon = 'location-dot',
                      onSelect = function()
                          SetNewWaypoint(p.coords_x, p.coords_y)
                          notify('inform', 'تم التحديد', p.name)
                      end },
                    { title = '🗑️ حذف', icon = 'trash', iconColor = '#ff3b3b',
                      onSelect = function()
                          local c = lib.alertDialog({
                              header = 'تأكيد', content = 'حذف نقطة البيع "' .. p.name .. '"؟',
                              centered = true, cancel = true })
                          if c == 'confirm' then
                              local ok, msg = lib.callback.await('qbx_families:server:adminDeleteTradePoint', false, p.id)
                              notify(ok and 'success' or 'error', msg)
                              if ok then Wait(300); OpenAdminTradeMenu() end
                          end
                      end },
                }
                lib.registerContext({
                    id = 'family_admin_trade_actions',
                    title = '💲 ' .. p.name,
                    menu = 'family_admin_trade',
                    options = actions,
                })
                lib.showContext('family_admin_trade_actions')
            end,
        }
    end
    lib.registerContext({
        id = 'family_admin_trade', title = '💲 نقاط البيع',
        menu = 'family_admin_menu', options = options,
    })
    lib.showContext('family_admin_trade')
end

function AdminCreateTradeFlow()
    local gangs = lib.callback.await('qbx_families:server:getAllGangs', false) or {}
    local opts = { { value = 0, label = '— بدون عائلة (تُربط تلقائياً بالزون) —' } }
    for _, g in ipairs(gangs) do
        opts[#opts+1] = { value = g.id, label = ('%s (ID:%d)'):format(g.label, g.id) }
    end
    local input = lib.inputDialog('➕ نقطة بيع جديدة عند موقعك', {
        { type = 'input', label = 'اسم النقطة', placeholder = 'Sandy Trade Spot',
          required = true, max = 50 },
        { type = 'select', label = 'العائلة المالكة (اختياري)', options = opts, default = 0 },
    })
    if not input then return end
    local gid = tonumber(input[2])
    if gid == 0 then gid = nil end
    local ok, msg = lib.callback.await('qbx_families:server:adminCreateTradePoint', false, input[1], gid)
    notify(ok and 'success' or 'error', msg)
    if ok then Wait(300); OpenAdminTradeMenu() end
end

-- ============================================================
-- إدارة الحروب (Admin)
-- ============================================================
function OpenAdminWarsMenu()
    local list = lib.callback.await('qbx_families:server:listActiveWars', false)
    local options = {
        { title = '⚡ فرض حرب فورية', description = 'اختر مهاجم/مدافع/زون — يتجاوز كل القيود',
          icon = 'bolt', iconColor = '#ff3b3b',
          onSelect = function() AdminForceWarFlow() end },
        { title = '🧪 وضع الاختبار',
          description = 'تفعيل/تعطيل Test Mode للحروب',
          icon = 'flask',
          onSelect = function() AdminTestModeToggle() end },
        { title = ('⚔️ حروب نشطة: %d'):format(#(list or {})), readOnly = true },
    }
    for _, w in ipairs(list or {}) do
        options[#options+1] = {
            title = ('⚔️ #%d %s vs %s'):format(w.id, w.attacker, w.defender),
            description = ('%s | %d-%d | %s'):format(w.zone, w.attacker_score, w.defender_score, w.status),
            onSelect = function() OpenAdminWarActions(w) end,
        }
    end
    lib.registerContext({
        id = 'family_admin_wars', title = '⚔️ الحروب',
        menu = 'family_admin_menu', options = options,
    })
    lib.showContext('family_admin_wars')
end

function OpenAdminWarActions(w)
    lib.registerContext({
        id = 'family_admin_war_actions',
        title = '⚔️ حرب #' .. w.id,
        menu = 'family_admin_wars',
        options = {
            { title = 'المهاجم: ' .. w.attacker .. ' (' .. w.attacker_score .. ')', readOnly = true },
            { title = 'المدافع: ' .. w.defender .. ' (' .. w.defender_score .. ')', readOnly = true },
            { title = 'المنطقة: ' .. w.zone .. ' | الحالة: ' .. w.status, readOnly = true },
            { title = '🏁 إنهاء الحرب — المهاجم يفوز', icon = 'flag-checkered',
              onSelect = function() AdminEndWarFlow(w, 'attacker') end },
            { title = '🏁 إنهاء الحرب — المدافع يفوز', icon = 'flag-checkered',
              onSelect = function() AdminEndWarFlow(w, 'defender') end },
            { title = '↩️ إلغاء الحرب واسترجاع التكلفة', icon = 'rotate-left', iconColor = '#ff8800',
              onSelect = function() AdminRefundWarFlow(w) end },
        },
    })
    lib.showContext('family_admin_war_actions')
end

function AdminEndWarFlow(w, winnerSide)
    local winnerLabel = winnerSide == 'attacker' and w.attacker or w.defender
    local c = lib.alertDialog({
        header = 'تأكيد الإنهاء',
        content = ('إنهاء الحرب #%d — الفائز: %s'):format(w.id, winnerLabel),
        centered = true, cancel = true,
    })
    if c ~= 'confirm' then return end
    -- نستخدم event على السيرفر — نضيف callback للأمر
    TriggerServerEvent('qbx_families:server:adminEndWar', w.id, winnerSide)
    notify('inform', 'تم إرسال طلب الإنهاء')
    Wait(800); OpenAdminWarsMenu()
end

function AdminRefundWarFlow(w)
    local c = lib.alertDialog({
        header = 'تأكيد الإلغاء',
        content = ('إلغاء الحرب #%d واسترجاع التكلفة للمهاجم؟'):format(w.id),
        centered = true, cancel = true,
    })
    if c ~= 'confirm' then return end
    TriggerServerEvent('qbx_families:server:adminRefundWar', w.id)
    notify('inform', 'تم إرسال طلب الإلغاء')
    Wait(800); OpenAdminWarsMenu()
end

function AdminTestModeToggle()
    local input = lib.inputDialog('🧪 وضع الاختبار', {
        { type = 'select', label = 'الحالة', required = true,
          options = {
              { value = 'on',  label = '✅ تفعيل (تكلفة 0، مدد قصيرة)' },
              { value = 'off', label = '❌ تعطيل (وضع طبيعي)' },
          } },
    })
    if not input then return end
    TriggerServerEvent('qbx_families:server:adminToggleTestMode', input[1])
    notify('inform', 'تم إرسال الطلب')
end

-- ============================================================
-- v0.5.2: Force War Flow (آدمن)
-- ============================================================
function AdminForceWarFlow()
    local gangs = lib.callback.await('qbx_families:server:adminListGangsForWar', false) or {}
    if #gangs < 2 then return notify('error', 'تحتاج عائلتين على الأقل') end

    local gangOpts = {}
    for _, g in ipairs(gangs) do
        gangOpts[#gangOpts+1] = {
            value = g.id,
            label = ('%s%s'):format(g.label, g.in_war and ' ⚔️ (في حرب)' or ''),
        }
    end

    local zones = lib.callback.await('qbx_families:server:adminListZonesForWar', false) or {}
    if #zones == 0 then return notify('error', 'لا توجد زونات') end

    local zoneOpts = {}
    for _, z in ipairs(zones) do
        zoneOpts[#zoneOpts+1] = {
            value = z.id,
            label = ('%s — %s%s'):format(z.name, z.gang_label or 'بدون مالك',
                z.in_war and ' ⚔️' or ''),
        }
    end

    local input = lib.inputDialog('⚡ فرض حرب فورية', {
        { type = 'select', label = 'العصابة المهاجمة', required = true, options = gangOpts },
        { type = 'select', label = 'العصابة المدافعة', required = true, options = gangOpts },
        { type = 'select', label = 'الزون', required = true, options = zoneOpts },
        { type = 'checkbox', label = 'بدء فوري (بدون مرحلة تحضير)', checked = false },
    })
    if not input then return end

    local atk, def, zone, instant = input[1], input[2], input[3], input[4]
    if atk == def then return notify('error', 'نفس العصابة!') end

    local c = lib.alertDialog({
        header = '⚡ تأكيد فرض الحرب',
        content = ('سيتم بدء حرب فوراً بدون قيود (cooldown، تكلفة، أعضاء).%s'):format(
            instant and '\n\n⚠️ بدء فوري — بدون تحضير' or ''),
        centered = true, cancel = true,
    })
    if c ~= 'confirm' then return end

    local ok, msg = lib.callback.await('qbx_families:server:adminForceDeclareWar', false,
        atk, def, zone, instant or false)
    notify(ok and 'success' or 'error', msg, '⚡ Force War')
    Wait(800); OpenAdminWarsMenu()
end

-- ============================================================
-- War Council Coords
-- ============================================================
function AdminSetWarCouncil()
    local c = lib.alertDialog({
        header = '📍 تحديد War Council',
        content = 'سيتم وضع War Council Ped في موقعك الحالي. متأكد؟',
        centered = true, cancel = true,
    })
    if c ~= 'confirm' then return end
    TriggerServerEvent('qbx_families:server:adminSetWarCouncil')
    notify('success', 'تم تحديث موقع War Council')
end

-- ============================================================
-- v0.5.1: Admin Recruitment Manager
-- ============================================================
function OpenAdminRecruitmentMenu()
    local list = lib.callback.await('esx_families:server:adminListAllRecruitment', false) or {}
    local options = {
        { title = '➕ إنشاء نقطة هنا لأي عائلة', icon = 'plus', iconColor = '#22c55e',
          onSelect = function() AdminCreateRecruitmentFlow() end },
        { title = ('🤝 إجمالي: %d نقطة'):format(#list), readOnly = true },
    }
    for _, p in ipairs(list) do
        options[#options+1] = {
            title = '📍 ' .. p.name,
            description = ('عائلة: %s | اضغط للحذف/تحديد على الخريطة'):format(p.gang_label),
            onSelect = function()
                local c = lib.alertDialog({
                    header = p.name, content = 'حذف النقطة أو تحديدها على الخريطة؟',
                    centered = true, cancel = true,
                    labels = { confirm = '🗑️ حذف', cancel = '🗺️ تحديد' },
                })
                if c == 'confirm' then
                    local ok, msg = lib.callback.await('esx_families:server:deleteRecruitmentPoint', false, p.id)
                    notify(ok and 'success' or 'error', msg)
                    if ok then Wait(300); OpenAdminRecruitmentMenu() end
                else
                    SetNewWaypoint(p.coords_x, p.coords_y); notify('inform', 'تم التحديد')
                end
            end,
        }
    end
    lib.registerContext({
        id = 'family_admin_recruit', title = '🤝 نقاط المبايعة',
        menu = 'family_admin_menu', options = options,
    })
    lib.showContext('family_admin_recruit')
end

function AdminCreateRecruitmentFlow()
    local gangs = lib.callback.await('qbx_families:server:getAllGangs', false) or {}
    if #gangs == 0 then return notify('error', 'أنشئ عائلة أولاً') end
    local opts = {}
    for _, g in ipairs(gangs) do
        opts[#opts+1] = { value = g.id, label = ('%s (ID:%d)'):format(g.label, g.id) }
    end
    local input = lib.inputDialog('🤝 نقطة مبايعة جديدة عند موقعك', {
        { type = 'select', label = 'العائلة المالكة', options = opts, required = true },
        { type = 'input',  label = 'اسم النقطة', default = 'مكتب التجنيد', max = 60 },
        { type = 'input',  label = 'موديل NPC', default = 's_m_y_dealer_01' },
    })
    if not input then return end
    local ok, msg = lib.callback.await('esx_families:server:adminCreateRecruitment', false,
        tonumber(input[1]), input[2], input[3])
    notify(ok and 'success' or 'error', msg)
    if ok then Wait(300); OpenAdminRecruitmentMenu() end
end

-- ============================================================
-- v0.5.1: Admin All Join Requests
-- ============================================================
function OpenAdminAllRequestsMenu()
    local list = lib.callback.await('esx_families:server:adminListAllRequests', false) or {}
    local options = {}
    if #list == 0 then
        options[1] = { title = 'لا توجد طلبات معلقة في السيرفر', readOnly = true }
    else
        for _, r in ipairs(list) do
            options[#options+1] = {
                title = '👤 ' .. r.player_name,
                description = ('طلب الانضمام لعائلة %s | %s'):format(r.gang_label, r.citizenid),
                icon = 'user-clock',
                onSelect = function()
                    local c = lib.alertDialog({
                        header = '🤝 ' .. r.player_name,
                        content = ('قبول/رفض ضم اللاعب لعائلة %s؟'):format(r.gang_label),
                        centered = true, cancel = true,
                        labels = { confirm = '✓ قبول', cancel = '✗ رفض' },
                    })
                    local ok, msg = lib.callback.await('esx_families:server:respondJoinRequest',
                        false, r.id, (c == 'confirm'))
                    notify(ok and 'success' or 'error', msg)
                    Wait(300); OpenAdminAllRequestsMenu()
                end,
            }
        end
    end
    lib.registerContext({
        id = 'family_admin_requests', title = '📨 طلبات الانضمام',
        menu = 'family_admin_menu', options = options,
    })
    lib.showContext('family_admin_requests')
end
