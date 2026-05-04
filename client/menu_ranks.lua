-- ============================================================
-- esx_families - Ranks Management Menu v0.4.0
-- إدارة الرتب والصلاحيات (للقادة فقط)
-- ============================================================

local function notify(t, msg, title)
    lib.notify({ type = t or 'inform', title = title, description = msg })
end

local PERM_LABELS = {
    can_open_vault   = 'فتح الخزنة',
    can_withdraw     = 'سحب من الخزنة',
    can_deposit      = 'إيداع في الخزنة',
    can_invite       = 'دعوة أعضاء',
    can_kick         = 'طرد أعضاء',
    can_promote      = 'ترقية أعضاء',
    can_manage_zones = 'إدارة المناطق',
}

local function permsString(rank)
    local on = {}
    for k, label in pairs(PERM_LABELS) do
        if rank[k] == 1 then on[#on+1] = label end
    end
    if #on == 0 then return 'لا توجد صلاحيات' end
    return table.concat(on, ' • ')
end

-- ============================================================
-- قائمة الرتب
-- ============================================================
function OpenRanksMenu(gangId)
    local ranks = lib.callback.await('qbx_families:server:getRanks', false, gangId)

    local options = {
        {
            title = '➕ إنشاء رتبة جديدة',
            description = 'إضافة رتبة جديدة بصلاحيات مخصصة',
            icon = 'plus',
            iconColor = '#22c55e',
            onSelect = function() CreateRankFlow(gangId) end,
        },
        { title = ('🎖️ إجمالي الرتب: %d'):format(#(ranks or {})), readOnly = true },
    }

    if ranks then
        for _, r in ipairs(ranks) do
            local locked = r.rank_order == 1
            options[#options+1] = {
                title = ('%s %s'):format(locked and '🔒' or '🎖️', r.label),
                description = ('الترتيب: %d | الفئة: %d | حد السحب: %s%s'):format(
                    r.rank_order, r.tier or 3,
                    (r.daily_withdraw_limit and r.daily_withdraw_limit > 0)
                        and ('$' .. r.daily_withdraw_limit) or 'بلا حد',
                    locked and ' | (محمية — رتبة القائد)' or ''
                ),
                onSelect = function() OpenRankActions(gangId, r) end,
            }
        end
    end

    lib.registerContext({
        id = 'family_ranks_menu',
        title = '🎖️ الرتب',
        menu = 'family_main_menu',
        options = options,
    })
    lib.showContext('family_ranks_menu')
end

-- ============================================================
-- إجراءات على رتبة
-- ============================================================
function OpenRankActions(gangId, rank)
    local options = {
        { title = '🎖️ ' .. rank.label, readOnly = true },
        { title = 'الصلاحيات الحالية', description = permsString(rank), readOnly = true },
    }

    if rank.rank_order == 1 then
        options[#options+1] = { title = '🔒 رتبة القائد محمية',
            description = 'لا يمكن تعديلها أو حذفها', readOnly = true }
    else
        options[#options+1] = {
            title = '✏️ تعديل الرتبة',
            description = 'تغيير الاسم والصلاحيات وحد السحب',
            icon = 'pen',
            onSelect = function() EditRankFlow(gangId, rank) end,
        }
        options[#options+1] = {
            title = '🗑️ حذف الرتبة',
            description = 'الأعضاء بهذه الرتبة سيصبحون بلا رتبة',
            icon = 'trash',
            iconColor = '#ff3b3b',
            onSelect = function() DeleteRankFlow(gangId, rank) end,
        }
    end

    lib.registerContext({
        id = 'family_rank_actions',
        title = '🎖️ ' .. rank.label,
        menu = 'family_ranks_menu',
        options = options,
    })
    lib.showContext('family_rank_actions')
end

-- ============================================================
-- Flows
-- ============================================================
local function rankInputFields(rank)
    rank = rank or {}
    return {
        { type = 'input',  label = 'اسم الرتبة', default = rank.label or '', required = true, max = 50 },
        { type = 'select', label = 'الفئة (Tier)', default = rank.tier or 3, required = true,
          options = {
              { value = 1, label = '1 — قيادي' },
              { value = 2, label = '2 — وسط' },
              { value = 3, label = '3 — أساسي' },
          } },
        { type = 'number', label = 'حد السحب اليومي ($) — صفر = بلا حد',
          default = rank.daily_withdraw_limit or 0, min = 0, max = 100000000, step = 1000 },
        { type = 'checkbox', label = 'فتح الخزنة',     checked = rank.can_open_vault == 1 },
        { type = 'checkbox', label = 'سحب من الخزنة',  checked = rank.can_withdraw == 1 },
        { type = 'checkbox', label = 'إيداع في الخزنة', checked = rank.can_deposit == 1 },
        { type = 'checkbox', label = 'دعوة أعضاء',     checked = rank.can_invite == 1 },
        { type = 'checkbox', label = 'طرد أعضاء',      checked = rank.can_kick == 1 },
        { type = 'checkbox', label = 'ترقية أعضاء',    checked = rank.can_promote == 1 },
        { type = 'checkbox', label = 'إدارة المناطق',  checked = rank.can_manage_zones == 1 },
    }
end

local function inputToData(input)
    return {
        label                = input[1],
        tier                 = tonumber(input[2]) or 3,
        daily_withdraw_limit = tonumber(input[3]) or 0,
        can_open_vault       = input[4] and true or false,
        can_withdraw         = input[5] and true or false,
        can_deposit          = input[6] and true or false,
        can_invite           = input[7] and true or false,
        can_kick             = input[8] and true or false,
        can_promote          = input[9] and true or false,
        can_manage_zones     = input[10] and true or false,
    }
end

function CreateRankFlow(gangId)
    local input = lib.inputDialog('➕ رتبة جديدة', rankInputFields(nil))
    if not input then return end
    local data = inputToData(input)
    local ok, msg = lib.callback.await('qbx_families:server:createRank', false, gangId, data)
    notify(ok and 'success' or 'error', msg)
    if ok then Wait(300); OpenRanksMenu(gangId) end
end

function EditRankFlow(gangId, rank)
    local input = lib.inputDialog('✏️ تعديل ' .. rank.label, rankInputFields(rank))
    if not input then return end
    local data = inputToData(input)
    local ok, msg = lib.callback.await('qbx_families:server:updateRank', false, rank.id, data)
    notify(ok and 'success' or 'error', msg)
    if ok then Wait(300); OpenRanksMenu(gangId) end
end

function DeleteRankFlow(gangId, rank)
    local c = lib.alertDialog({
        header = 'تأكيد حذف الرتبة',
        content = ('متأكد من حذف رتبة "%s"؟ الأعضاء بهذه الرتبة سيصبحون بلا رتبة.'):format(rank.label),
        centered = true, cancel = true,
    })
    if c ~= 'confirm' then return end
    local ok, msg = lib.callback.await('qbx_families:server:deleteRank', false, rank.id)
    notify(ok and 'success' or 'error', msg)
    if ok then Wait(300); OpenRanksMenu(gangId) end
end
