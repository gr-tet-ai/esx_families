-- ============================================================
-- esx_families - Members Management Menu v0.4.0
-- إدارة الأعضاء (دعوة / طرد / ترقية) من القائمة
-- ============================================================

local function notify(t, msg, title)
    lib.notify({ type = t or 'inform', title = title, description = msg })
end

-- ============================================================
-- قائمة الأعضاء الرئيسية
-- ============================================================
function OpenMembersMenu(gangId)
    local members = lib.callback.await('qbx_families:server:getMembers', false, gangId)
    local ctx = lib.callback.await('qbx_families:server:getMyContext', false)
    local myRank = ctx and ctx.rank or nil
    local isLeader = ctx and ctx.isLeader or false
    local isAdmin = ctx and ctx.isAdmin or false

    local options = {}

    -- زر الدعوة (للذين يملكون can_invite)
    if isAdmin or (myRank and myRank.can_invite == 1) then
        options[#options+1] = {
            title = '➕ دعوة عضو جديد',
            description = 'إدخال CitizenID للاعب',
            icon = 'user-plus',
            iconColor = '#22c55e',
            onSelect = function() InviteMemberFlow(gangId) end,
        }
    end

    -- ترويسة العدد
    options[#options+1] = {
        title = ('👥 إجمالي الأعضاء: %d'):format(#(members or {})),
        readOnly = true,
    }

    if not members or #members == 0 then
        options[#options+1] = { title = 'لا يوجد أعضاء بعد', readOnly = true }
    else
        for _, m in ipairs(members) do
            local rankLabel = m.rank_label or 'بدون رتبة'
            local isThisLeader = false
            -- نتعرف على القائد عبر الترتيب 1
            if m.rank_order == 1 then isThisLeader = true end

            options[#options+1] = {
                title = ('%s%s'):format(isThisLeader and '👑 ' or '👤 ', m.citizenid),
                description = ('الرتبة: %s | منذ: %s'):format(
                    rankLabel,
                    m.joined_at and tostring(m.joined_at):sub(1, 16) or '?'
                ),
                onSelect = function()
                    OpenMemberActions(gangId, m, isLeader, isAdmin, myRank)
                end,
            }
        end
    end

    lib.registerContext({
        id = 'family_members_menu',
        title = '👥 الأعضاء',
        menu = 'family_main_menu',
        options = options,
    })
    lib.showContext('family_members_menu')
end

-- ============================================================
-- إجراءات على عضو
-- ============================================================
function OpenMemberActions(gangId, member, isLeader, isAdmin, myRank)
    local options = {
        { title = '🆔 ' .. member.citizenid, readOnly = true },
        { title = 'الرتبة: ' .. (member.rank_label or 'بدون'), readOnly = true },
    }

    local canPromote = isAdmin or (myRank and myRank.can_promote == 1)
    local canKick    = isAdmin or (myRank and myRank.can_kick    == 1)

    if canPromote and member.rank_order ~= 1 then
        options[#options+1] = {
            title = '⬆️ تغيير الرتبة',
            description = 'اختر رتبة جديدة لهذا العضو',
            icon = 'arrow-up',
            onSelect = function() PromoteMemberFlow(gangId, member) end,
        }
    end

    if canKick and member.rank_order ~= 1 then
        options[#options+1] = {
            title = '🚫 طرد من العائلة',
            description = 'إزالة هذا العضو نهائياً',
            icon = 'user-xmark',
            iconColor = '#ff3b3b',
            onSelect = function() KickMemberFlow(gangId, member) end,
        }
    end

    if member.rank_order == 1 then
        options[#options+1] = {
            title = 'ℹ️ هذا هو القائد',
            description = 'لا يمكن طرده أو تنزيل رتبته (للأدمن فقط عبر تغيير القيادة)',
            readOnly = true,
        }
    end

    lib.registerContext({
        id = 'family_member_actions',
        title = '👤 ' .. member.citizenid,
        menu = 'family_members_menu',
        options = options,
    })
    lib.showContext('family_member_actions')
end

-- ============================================================
-- Flows
-- ============================================================
function InviteMemberFlow(gangId)
    local input = lib.inputDialog('➕ دعوة عضو جديد', {
        { type = 'input', label = 'CitizenID', placeholder = 'license:xxxxx أو char1:xxx',
          required = true, min = 3, max = 80 },
    })
    if not input or not input[1] then return end

    local cid = input[1]:gsub('^%s+', ''):gsub('%s+$', '')
    local ok, msg = lib.callback.await('qbx_families:server:inviteMember', false, cid)
    notify(ok and 'success' or 'error', msg)
    if ok then
        Wait(300)
        OpenMembersMenu(gangId)  -- refresh
    end
end

function KickMemberFlow(gangId, member)
    local c = lib.alertDialog({
        header = 'تأكيد الطرد',
        content = ('متأكد من طرد %s؟'):format(member.citizenid),
        centered = true, cancel = true,
    })
    if c ~= 'confirm' then return end
    local ok, msg = lib.callback.await('qbx_families:server:kickMember', false, member.citizenid)
    notify(ok and 'success' or 'error', msg)
    if ok then Wait(300); OpenMembersMenu(gangId) end
end

function PromoteMemberFlow(gangId, member)
    local ranks = lib.callback.await('qbx_families:server:getRanks', false, gangId)
    if not ranks or #ranks == 0 then
        return notify('error', 'لا توجد رتب')
    end

    local rankOptions = {}
    for _, r in ipairs(ranks) do
        if r.rank_order ~= 1 then  -- لا نسمح بالترقية لـ Boss
            table.insert(rankOptions, { value = r.id, label = ('%s (ترتيب %d)'):format(r.label, r.rank_order) })
        end
    end
    if #rankOptions == 0 then
        return notify('error', 'لا توجد رتب متاحة (Boss فقط محجوز)')
    end

    local input = lib.inputDialog('⬆️ تغيير رتبة ' .. member.citizenid, {
        { type = 'select', label = 'الرتبة الجديدة', options = rankOptions, required = true },
    })
    if not input or not input[1] then return end
    local ok, msg = lib.callback.await('qbx_families:server:promoteMember', false, member.citizenid, tonumber(input[1]))
    notify(ok and 'success' or 'error', msg)
    if ok then Wait(300); OpenMembersMenu(gangId) end
end
