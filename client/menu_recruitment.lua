-- ============================================================
-- esx_families - Recruitment Menus (Client) v0.5.0
-- قوائم: نقاط مبايعتي + طلبات الانضمام
-- ============================================================

local function notify(t, msg) lib.notify({ type = t or 'inform', description = msg }) end

-- ========== F6: نقاط مبايعتي (للقائد) ==========
function OpenMyRecruitmentMenu(gangId)
    local list = lib.callback.await('esx_families:server:listRecruitmentPoints', false, gangId) or {}
    local options = {
        {
            title = '➕ إنشاء نقطة هنا',
            description = 'تنشأ نقطة مبايعة في موقعك الحالي مع NPC',
            icon = 'plus', iconColor = '#22c55e',
            onSelect = function()
                local input = lib.inputDialog('نقطة مبايعة جديدة', {
                    { type = 'input', label = 'الاسم', default = 'مكتب التجنيد', max = 60 },
                    { type = 'input', label = 'موديل الـ NPC (اختياري)', default = 's_m_y_dealer_01' },
                })
                if not input then return end
                local ok, msg = lib.callback.await('esx_families:server:createRecruitmentPoint',
                    false, gangId, input[1], input[2])
                notify(ok and 'success' or 'error', msg)
                if ok then Wait(400); OpenMyRecruitmentMenu(gangId) end
            end,
        },
    }
    if #list == 0 then
        options[#options+1] = { title = 'لا توجد نقاط حالياً', readOnly = true }
    end
    for _, p in ipairs(list) do
        options[#options+1] = {
            title = '📍 ' .. p.name,
            description = ('عائلة: %s | اضغط للحذف أو تحديد على الخريطة'):format(p.gang_label),
            icon = 'map-pin',
            onSelect = function()
                local choice = lib.alertDialog({
                    header = p.name, content = 'ماذا تريد أن تفعل؟',
                    centered = true, cancel = true,
                    labels = { confirm = '🗑️ حذف', cancel = '🗺️ تحديد على الخريطة' },
                })
                if choice == 'confirm' then
                    local ok, msg = lib.callback.await('esx_families:server:deleteRecruitmentPoint', false, p.id)
                    notify(ok and 'success' or 'error', msg)
                    if ok then Wait(300); OpenMyRecruitmentMenu(gangId) end
                else
                    SetNewWaypoint(p.coords_x, p.coords_y)
                    notify('inform', 'تم التحديد على الخريطة')
                end
            end,
        }
    end
    lib.registerContext({
        id = 'my_recruitment', title = '📍 نقاط المبايعة',
        menu = 'family_main_menu', options = options,
    })
    lib.showContext('my_recruitment')
end

-- ========== F6: طلبات الانضمام المعلقة ==========
function OpenJoinRequestsMenu()
    local list = lib.callback.await('esx_families:server:listJoinRequests', false) or {}
    local options = {}
    if #list == 0 then
        options[1] = { title = 'لا توجد طلبات معلقة', readOnly = true }
    else
        for _, r in ipairs(list) do
            options[#options+1] = {
                title = '👤 ' .. r.player_name,
                description = ('CitizenID: %s | اضغط للقبول/الرفض'):format(r.citizenid),
                icon = 'user-clock',
                onSelect = function()
                    local c = lib.alertDialog({
                        header = '🤝 طلب من ' .. r.player_name,
                        content = ('هل تقبل ضم **%s** لعائلتك؟'):format(r.player_name),
                        centered = true, cancel = true,
                        labels = { confirm = '✓ قبول', cancel = '✗ رفض' },
                    })
                    local accept = (c == 'confirm')
                    local ok, msg = lib.callback.await('esx_families:server:respondJoinRequest',
                        false, r.id, accept)
                    notify(ok and 'success' or 'error', msg)
                    Wait(300); OpenJoinRequestsMenu()
                end,
            }
        end
    end
    lib.registerContext({
        id = 'join_requests', title = '🤝 طلبات الانضمام',
        menu = 'family_main_menu', options = options,
    })
    lib.showContext('join_requests')
end
