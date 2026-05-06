-- ============================================================
-- esx_families - Members Management Menu v0.8.0 (Phase 3)
-- يستخدم QFM Dialogs (Corporate Blue NUI)
-- ============================================================

local function notify(t, msg, title)
    if lib and lib.notify then
        lib.notify({ type = t or 'inform', title = title, description = msg })
    end
end

-- ============================================================
-- قائمة الأعضاء الرئيسية
-- ============================================================
function OpenMembersMenu(gangId)
    CreateThread(function()
        local members = lib.callback.await('qbx_families:server:getMembers', false, gangId)
        local ctx     = lib.callback.await('qbx_families:server:getMyContext', false)
        local myRank  = ctx and ctx.rank or nil
        local isLeader= ctx and ctx.isLeader or false
        local isAdmin = ctx and ctx.isAdmin  or false

        local items = {}
        local handlers = {}   -- idx -> function

        local canInvite = isAdmin or (myRank and myRank.can_invite == 1)
        if canInvite then
            items[#items+1] = {
                title = 'دعوة عضو جديد',
                desc  = 'إدخال CitizenID للاعب',
                fa    = 'fa-user-plus',
                iconColor = 'green',
            }
            handlers[#items] = function() InviteMemberFlow(gangId) end
        end

        items[#items+1] = {
            title = ('إجمالي الأعضاء: %d'):format(#(members or {})),
            desc  = 'العائلة #' .. tostring(gangId),
            fa    = 'fa-users',
            readOnly = true,
        }

        if not members or #members == 0 then
            items[#items+1] = { title = 'لا يوجد أعضاء بعد', readOnly = true, fa='fa-circle-info' }
        else
            for _, m in ipairs(members) do
                local isThisLeader = (m.rank_order == 1)
                local rankLabel = m.rank_label or 'بدون رتبة'
                items[#items+1] = {
                    title = (isThisLeader and '👑 ' or '') .. m.citizenid,
                    desc  = ('الرتبة: %s · منذ: %s'):format(
                        rankLabel,
                        m.joined_at and tostring(m.joined_at):sub(1,16) or '?'),
                    fa    = isThisLeader and 'fa-crown' or 'fa-user',
                    iconColor = isThisLeader and 'orange' or nil,
                }
                local mref = m
                handlers[#items] = function()
                    OpenMemberActions(gangId, mref, isLeader, isAdmin, myRank)
                end
            end
        end

        local idx = QFM.list('الأعضاء', items, { subtitle = ('عائلة #%d'):format(gangId) })
        if idx and handlers[idx] then handlers[idx]() end
    end)
end

-- ============================================================
-- إجراءات على عضو
-- ============================================================
function OpenMemberActions(gangId, member, isLeader, isAdmin, myRank)
    CreateThread(function()
        local items = {}
        local handlers = {}

        items[#items+1] = {
            title = member.citizenid,
            desc  = 'الرتبة الحالية: ' .. (member.rank_label or 'بدون'),
            fa    = (member.rank_order==1) and 'fa-crown' or 'fa-user',
            iconColor = (member.rank_order==1) and 'orange' or nil,
            readOnly = true,
        }

        local canPromote = isAdmin or (myRank and myRank.can_promote == 1)
        local canKick    = isAdmin or (myRank and myRank.can_kick    == 1)

        if canPromote and member.rank_order ~= 1 then
            items[#items+1] = {
                title = 'تغيير الرتبة',
                desc  = 'اختر رتبة جديدة لهذا العضو',
                fa    = 'fa-arrow-up',
            }
            handlers[#items] = function() PromoteMemberFlow(gangId, member) end
        end

        if canKick and member.rank_order ~= 1 then
            items[#items+1] = {
                title = 'طرد من العائلة',
                desc  = 'إزالة هذا العضو نهائياً',
                fa    = 'fa-user-xmark',
                iconColor = 'red',
                danger = true,
            }
            handlers[#items] = function() KickMemberFlow(gangId, member) end
        end

        if member.rank_order == 1 then
            items[#items+1] = {
                title = 'هذا هو القائد',
                desc  = 'لا يمكن طرده أو تنزيل رتبته (للأدمن فقط عبر تغيير القيادة)',
                fa    = 'fa-circle-info',
                readOnly = true,
            }
        end

        local idx = QFM.list(member.citizenid, items, { subtitle='إجراءات على العضو' })
        if idx and handlers[idx] then
            handlers[idx]()
        else
            -- back to members list
            OpenMembersMenu(gangId)
        end
    end)
end

-- ============================================================
-- Flows
-- ============================================================
function InviteMemberFlow(gangId)
    CreateThread(function()
        local vals = QFM.input('دعوة عضو جديد', {
            { type='input', label='CitizenID', placeholder='license:xxxxx أو char1:xxx',
              required=true, min=3, max=80 },
        })
        if not vals or not vals[1] then OpenMembersMenu(gangId); return end
        local cid = tostring(vals[1]):gsub('^%s+',''):gsub('%s+$','')
        local ok, msg = lib.callback.await('qbx_families:server:inviteMember', false, cid)
        notify(ok and 'success' or 'error', msg)
        Wait(250)
        OpenMembersMenu(gangId)
    end)
end

function KickMemberFlow(gangId, member)
    CreateThread(function()
        local ok = QFM.confirm('تأكيد الطرد',
            ('هل أنت متأكد من طرد %s؟'):format(member.citizenid),
            { danger=true, confirmText='طرد', cancelText='إلغاء' })
        if not ok then OpenMembersMenu(gangId); return end
        local sok, msg = lib.callback.await('qbx_families:server:kickMember', false, member.citizenid)
        notify(sok and 'success' or 'error', msg)
        Wait(250)
        OpenMembersMenu(gangId)
    end)
end

function PromoteMemberFlow(gangId, member)
    CreateThread(function()
        local ranks = lib.callback.await('qbx_families:server:getRanks', false, gangId)
        if not ranks or #ranks == 0 then
            notify('error', 'لا توجد رتب'); OpenMembersMenu(gangId); return
        end
        local rankOptions = {}
        for _, r in ipairs(ranks) do
            if r.rank_order ~= 1 then
                rankOptions[#rankOptions+1] = {
                    value = tostring(r.id),
                    label = ('%s (ترتيب %d)'):format(r.label, r.rank_order),
                }
            end
        end
        if #rankOptions == 0 then
            notify('error','لا توجد رتب متاحة (Boss فقط محجوز)')
            OpenMembersMenu(gangId); return
        end
        local vals = QFM.input('تغيير رتبة ' .. member.citizenid, {
            { type='select', label='الرتبة الجديدة', required=true, options=rankOptions },
        })
        if not vals or not vals[1] then OpenMembersMenu(gangId); return end
        local rid = tonumber(vals[1])
        local sok, msg = lib.callback.await('qbx_families:server:promoteMember', false, member.citizenid, rid)
        notify(sok and 'success' or 'error', msg)
        Wait(250)
        OpenMembersMenu(gangId)
    end)
end
