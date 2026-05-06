-- ============================================================
-- نظام الرتب والأعضاء (Server-side) — v0.2.0
-- ============================================================

-- Caches
RanksCache    = {}   -- [rank_id] = { id, gang_id, rank_order, label, tier, perms..., daily_withdraw_limit }
MembersCache  = {}   -- [citizenid] = { id, gang_id, rank_id }
GangRanksIdx  = {}   -- [gang_id] = { [rank_order] = rank_id }  للوصول السريع

local function indexRank(r)
    RanksCache[r.id] = r
    GangRanksIdx[r.gang_id] = GangRanksIdx[r.gang_id] or {}
    GangRanksIdx[r.gang_id][r.rank_order] = r.id
end

local function loadRanksAndMembers()
    local ranks = MySQL.query.await('SELECT * FROM family_ranks') or {}
    for _, r in ipairs(ranks) do indexRank(r) end

    local members = MySQL.query.await('SELECT * FROM family_members') or {}
    for _, m in ipairs(members) do
        MembersCache[m.citizenid] = { id = m.id, gang_id = m.gang_id, rank_id = m.rank_id }
    end

    print(('^2[qbx_families]^7 تم تحميل %d رتبة | %d عضو'):format(#ranks, #members))
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Wait(800)  -- بعد main.lua
    loadRanksAndMembers()
end)

-- ============================================================
-- Helpers (تُستخدم من vault.lua وغيرها)
-- ============================================================

---رجع رتبة اللاعب (نسخة كاملة من جدول family_ranks)
---@param citizenid string
---@return table|nil rank
function GetPlayerRank(citizenid)
    local m = MembersCache[citizenid]
    if not m or not m.rank_id then return nil end
    return RanksCache[m.rank_id]
end

---رجع عصابة اللاعب (id) — بناءً على عضويته
---@param citizenid string
---@return number|nil gang_id
function GetPlayerGang(citizenid)
    local m = MembersCache[citizenid]
    return m and m.gang_id or nil
end

---صلاحية محددة (string key مثل 'can_open_vault')
function HasRankPermission(citizenid, perm)
    local rank = GetPlayerRank(citizenid)
    return rank and rank[perm] == 1 or false
end

---إنشاء الرتب الافتراضية لعصابة جديدة (يُستدعى من callbacks adminCreateGang)
---@param gangId number
---@param leaderCid string
function CreateDefaultRanksForGang(gangId, leaderCid)
    local defaults = {
        { 1, 'زعيم', 1, 1, 1, 1, 1, 1, 1, 1, 0 },
        { 2, 'كابو', 2, 1, 1, 1, 1, 1, 0, 0, 100000 },
        { 3, 'عضو',  3, 0, 0, 1, 0, 0, 0, 0, 0 },
    }
    for _, d in ipairs(defaults) do
        local id = MySQL.insert.await([[
            INSERT INTO family_ranks
            (gang_id, rank_order, label, tier,
             can_open_vault, can_withdraw, can_deposit,
             can_invite, can_kick, can_promote, can_manage_zones,
             daily_withdraw_limit)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
        ]], { gangId, d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11] })
        if id then
            indexRank({
                id = id, gang_id = gangId, rank_order = d[1], label = d[2], tier = d[3],
                can_open_vault = d[4], can_withdraw = d[5], can_deposit = d[6],
                can_invite = d[7], can_kick = d[8], can_promote = d[9],
                can_manage_zones = d[10], daily_withdraw_limit = d[11],
            })
        end
    end
    -- سجل القائد كعضو Boss
    local bossRankId = GangRanksIdx[gangId] and GangRanksIdx[gangId][1]
    if bossRankId then
        MySQL.insert.await(
            'INSERT IGNORE INTO family_members (gang_id, citizenid, rank_id, invited_by) VALUES (?,?,?,?)',
            { gangId, leaderCid, bossRankId, 'system' }
        )
        MembersCache[leaderCid] = { gang_id = gangId, rank_id = bossRankId }
    end
end

---متابعة السحب اليومي — يرجع كم سحب اللاعب اليوم
local function getTodayWithdrawn(citizenid)
    local row = MySQL.single.await(
        'SELECT amount_withdrawn FROM family_withdraw_tracker WHERE citizenid = ? AND tracker_date = CURDATE()',
        { citizenid })
    return row and row.amount_withdrawn or 0
end

---يضيف للـ tracker (يُستدعى من vault.lua قبل السحب)
function AddToWithdrawTracker(citizenid, amount)
    MySQL.query.await([[
        INSERT INTO family_withdraw_tracker (citizenid, tracker_date, amount_withdrawn)
        VALUES (?, CURDATE(), ?)
        ON DUPLICATE KEY UPDATE amount_withdrawn = amount_withdrawn + VALUES(amount_withdrawn)
    ]], { citizenid, amount })
end

---تحقق إذا اللاعب يقدر يسحب مبلغ (يحترم daily_withdraw_limit)
---@return boolean ok, string|nil reason, number remaining
function CanWithdrawToday(citizenid, amount)
    local rank = GetPlayerRank(citizenid)
    if not rank then return false, 'لست عضواً في عصابة', 0 end
    if rank.can_withdraw ~= 1 then return false, 'رتبتك لا تسمح بالسحب', 0 end

    local limit = rank.daily_withdraw_limit or 0
    if limit == 0 then return true, nil, math.huge end  -- بدون حد

    local used = getTodayWithdrawn(citizenid)
    local remaining = limit - used
    if amount > remaining then
        return false, ('تجاوزت الحد اليومي. المتبقي: %s'):format(Shared.FormatMoney(remaining)), remaining
    end
    return true, nil, remaining
end

-- ============================================================
-- Callbacks: قراءة الرتب والأعضاء
-- ============================================================

lib.callback.register('qbx_families:server:getMyRank', function(source)
    local cid = GetCitizenId(source); if not cid then return nil end
    local rank = GetPlayerRank(cid)
    local gangId = GetPlayerGang(cid)
    if not rank then return nil end
    return {
        rank = rank,
        gang = GangsCache[gangId],
        todayWithdrawn = getTodayWithdrawn(cid),
    }
end)

lib.callback.register('qbx_families:server:getRanks', function(source, gangId)
    local cid = GetCitizenId(source); if not cid then return {} end
    -- آدمن أو عضو في نفس العصابة
    if not IsAdmin(source) and GetPlayerGang(cid) ~= gangId then return {} end

    local list = {}
    for _, r in pairs(RanksCache) do
        if r.gang_id == gangId then table.insert(list, r) end
    end
    table.sort(list, function(a, b) return a.rank_order < b.rank_order end)
    return list
end)

lib.callback.register('qbx_families:server:getMembers', function(source, gangId)
    print(('[DIAG_P3D3_GET_MEMBERS] src=%s gangId=%s'):format(tostring(source), tostring(gangId)))
    local cid = GetCitizenId(source); if not cid then print('[DIAG_P3D3_GET_MEMBERS] reject: no cid'); return {} end
    if not IsAdmin(source) and GetPlayerGang(cid) ~= gangId then print(('[DIAG_P3D3_GET_MEMBERS] reject: cid=%s not in gang=%s'):format(cid, tostring(gangId))); return {} end

    local rows = MySQL.query.await([[
        SELECT m.*, r.label AS rank_label, r.rank_order, r.tier
        FROM family_members m
        LEFT JOIN family_ranks r ON r.id = m.rank_id
        WHERE m.gang_id = ?
        ORDER BY r.rank_order ASC, m.joined_at ASC
    ]], { gangId }) or {}
    print(('[DIAG_P3D3_GET_MEMBERS] returning %d rows'):format(#rows))
    return rows
end)

-- ============================================================
-- Callbacks: إدارة الرتب (Boss / Admin فقط)
-- ============================================================

local function isBossOrAdmin(src, gangId)
    if IsAdmin(src) then return true end
    local cid = GetCitizenId(src)
    local rank = GetPlayerRank(cid)
    return rank and rank.gang_id == gangId and rank.tier == 1 and rank.rank_order == 1
end

lib.callback.register('qbx_families:server:createRank', function(source, gangId, data)
    if not isBossOrAdmin(source, gangId) then return false, 'للزعيم فقط' end
    if not data or not data.label then return false, 'بيانات ناقصة' end

    -- احسب أعلى rank_order موجود
    local maxOrder = MySQL.scalar.await(
        'SELECT COALESCE(MAX(rank_order), 0) FROM family_ranks WHERE gang_id = ?', { gangId }) or 0
    local newOrder = maxOrder + 1

    local id = MySQL.insert.await([[
        INSERT INTO family_ranks
        (gang_id, rank_order, label, tier,
         can_open_vault, can_withdraw, can_deposit,
         can_invite, can_kick, can_promote, can_manage_zones,
         daily_withdraw_limit)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
    ]], {
        gangId, newOrder, data.label, data.tier or 3,
        data.can_open_vault and 1 or 0,
        data.can_withdraw and 1 or 0,
        data.can_deposit and 1 or 0,
        data.can_invite and 1 or 0,
        data.can_kick and 1 or 0,
        data.can_promote and 1 or 0,
        data.can_manage_zones and 1 or 0,
        data.daily_withdraw_limit or 0,
    })
    if not id then return false, 'فشل الإنشاء' end

    indexRank({
        id = id, gang_id = gangId, rank_order = newOrder, label = data.label, tier = data.tier or 3,
        can_open_vault = data.can_open_vault and 1 or 0,
        can_withdraw   = data.can_withdraw   and 1 or 0,
        can_deposit    = data.can_deposit    and 1 or 0,
        can_invite     = data.can_invite     and 1 or 0,
        can_kick       = data.can_kick       and 1 or 0,
        can_promote    = data.can_promote    and 1 or 0,
        can_manage_zones = data.can_manage_zones and 1 or 0,
        daily_withdraw_limit = data.daily_withdraw_limit or 0,
    })
    return true, ('تم إنشاء رتبة %s'):format(data.label)
end)

lib.callback.register('qbx_families:server:updateRank', function(source, rankId, data)
    local rank = RanksCache[rankId]
    if not rank then return false, 'الرتبة غير موجودة' end
    if not isBossOrAdmin(source, rank.gang_id) then return false, 'للزعيم فقط' end
    -- منع تعديل رتبة Boss نفسها (rank_order = 1)
    if rank.rank_order == 1 then return false, 'لا يمكن تعديل رتبة الزعيم' end

    MySQL.update.await([[
        UPDATE family_ranks SET
          label = ?, tier = ?,
          can_open_vault = ?, can_withdraw = ?, can_deposit = ?,
          can_invite = ?, can_kick = ?, can_promote = ?, can_manage_zones = ?,
          daily_withdraw_limit = ?
        WHERE id = ?
    ]], {
        data.label or rank.label, data.tier or rank.tier,
        data.can_open_vault and 1 or 0,
        data.can_withdraw and 1 or 0,
        data.can_deposit and 1 or 0,
        data.can_invite and 1 or 0,
        data.can_kick and 1 or 0,
        data.can_promote and 1 or 0,
        data.can_manage_zones and 1 or 0,
        data.daily_withdraw_limit or 0,
        rankId,
    })
    -- حدّث الكاش
    for k, v in pairs({
        label = data.label or rank.label, tier = data.tier or rank.tier,
        can_open_vault = data.can_open_vault and 1 or 0,
        can_withdraw = data.can_withdraw and 1 or 0,
        can_deposit  = data.can_deposit  and 1 or 0,
        can_invite   = data.can_invite   and 1 or 0,
        can_kick     = data.can_kick     and 1 or 0,
        can_promote  = data.can_promote  and 1 or 0,
        can_manage_zones = data.can_manage_zones and 1 or 0,
        daily_withdraw_limit = data.daily_withdraw_limit or 0,
    }) do rank[k] = v end
    return true, 'تم التحديث'
end)

lib.callback.register('qbx_families:server:deleteRank', function(source, rankId)
    local rank = RanksCache[rankId]
    if not rank then return false end
    if not isBossOrAdmin(source, rank.gang_id) then return false, 'للزعيم فقط' end
    if rank.rank_order == 1 then return false, 'لا يمكن حذف رتبة الزعيم' end

    -- الأعضاء المرتبطين بهذه الرتبة سينزلون لـ rank_id = NULL (ON DELETE SET NULL)
    MySQL.query.await('DELETE FROM family_ranks WHERE id = ?', { rankId })
    RanksCache[rankId] = nil
    if GangRanksIdx[rank.gang_id] then
        GangRanksIdx[rank.gang_id][rank.rank_order] = nil
    end
    -- صفّر الكاش للأعضاء المتأثرين
    for cid, m in pairs(MembersCache) do
        if m.rank_id == rankId then m.rank_id = nil end
    end
    return true, 'تم الحذف'
end)

-- ============================================================
-- Callbacks: إدارة الأعضاء (دعوة / طرد / ترقية)
-- ============================================================

lib.callback.register('qbx_families:server:inviteMember', function(source, targetCitizenId)
    local cid = GetCitizenId(source); if not cid then return false end
    local inviterRank = GetPlayerRank(cid)
    if not inviterRank or inviterRank.can_invite ~= 1 then
        return false, 'رتبتك لا تسمح بالدعوة'
    end

    -- v0.5.0: تطبيع + تحقق
    targetCitizenId = ESXBridge.NormalizeCitizenId(targetCitizenId)
    if not targetCitizenId then return false, 'CitizenID فارغ' end

    if MembersCache[targetCitizenId] then
        return false, 'هذا اللاعب عضو في عصابة بالفعل'
    end

    local exists, targetSrc = ESXBridge.CitizenExists(targetCitizenId)
    if not exists then return false, ('اللاعب %s غير موجود في DB'):format(targetCitizenId) end

    -- أدنى رتبة (آخر rank_order) هي رتبة الدعوة الافتراضية
    local lowestId, lowestOrder = nil, 0
    for _, r in pairs(RanksCache) do
        if r.gang_id == inviterRank.gang_id and r.rank_order > lowestOrder then
            lowestOrder = r.rank_order; lowestId = r.id
        end
    end
    if not lowestId then return false, 'لا توجد رتب متاحة' end

    local id = MySQL.insert.await(
        'INSERT INTO family_members (gang_id, citizenid, rank_id, invited_by) VALUES (?,?,?,?)',
        { inviterRank.gang_id, targetCitizenId, lowestId, cid }
    )
    if not id then return false, 'فشل الإضافة (لعله موجود بالفعل)' end
    MembersCache[targetCitizenId] = { id = id, gang_id = inviterRank.gang_id, rank_id = lowestId }

    -- v0.5.0: أبلغ المدعو لو أونلاين
    if targetSrc then
        local gang = GangsCache[inviterRank.gang_id]
        TriggerClientEvent('esx_families:client:youJoinedGang', targetSrc, {
            gang = gang, asLeader = false,
        })
        TriggerClientEvent('ox_lib:notify', targetSrc, {
            type = 'success', icon = 'user-plus', duration = 7000,
            title = '🤝 انضممت لعائلة',
            description = ('تم ضمك لعائلة %s\nاضغط F6 لفتح اللوحة'):format(gang and gang.label or '?'),
        })
    end

    return true, 'تم إضافة العضو'
end)


lib.callback.register('qbx_families:server:kickMember', function(source, targetCitizenId)
    local cid = GetCitizenId(source); if not cid then return false end
    local myRank = GetPlayerRank(cid)
    local target = MembersCache[targetCitizenId]
    if not myRank or not target then return false, 'بيانات غير صحيحة' end
    if myRank.gang_id ~= target.gang_id then return false, 'ليس من عصابتك' end
    if myRank.can_kick ~= 1 then return false, 'رتبتك لا تسمح بالطرد' end

    -- لا يمكن طرد قائد العصابة
    local gang = GangsCache[target.gang_id]
    if gang and gang.leader_citizenid == targetCitizenId then
        return false, 'لا يمكن طرد القائد'
    end

    -- لا يمكن طرد رتبة أعلى أو مساوية (إلا للزعيم)
    if myRank.rank_order ~= 1 then
        local targetRank = RanksCache[target.rank_id]
        if targetRank and targetRank.rank_order <= myRank.rank_order then
            return false, 'لا يمكن طرد رتبة أعلى أو مساوية'
        end
    end

    MySQL.query.await('DELETE FROM family_members WHERE citizenid = ?', { targetCitizenId })
    MembersCache[targetCitizenId] = nil
    -- v0.5.1: أبلغ المطرود لو أونلاين
    local kickedSrc = ESXBridge.GetSourceByCitizenId(targetCitizenId)
    if kickedSrc then
        TriggerClientEvent('esx_families:client:youLeftGang', kickedSrc)
        TriggerClientEvent('ox_lib:notify', kickedSrc, {
            type = 'error', icon = 'door-open', duration = 7000,
            title = 'تم طردك',
            description = 'تم إخراجك من العائلة',
        })
    end
    return true, 'تم الطرد'
end)

lib.callback.register('qbx_families:server:promoteMember', function(source, targetCitizenId, newRankId)
    local cid = GetCitizenId(source); if not cid then return false end
    local myRank = GetPlayerRank(cid)
    local target = MembersCache[targetCitizenId]
    local newRank = RanksCache[newRankId]
    if not myRank or not target or not newRank then return false, 'بيانات غير صحيحة' end
    if myRank.gang_id ~= target.gang_id or myRank.gang_id ~= newRank.gang_id then
        return false, 'عصابات مختلفة'
    end
    if myRank.can_promote ~= 1 then return false, 'رتبتك لا تسمح بالترقية' end
    -- لا يمكن الترقية لرتبة أعلى من رتبتك (إلا للزعيم)
    if myRank.rank_order ~= 1 and newRank.rank_order <= myRank.rank_order then
        return false, 'لا يمكن الترقية لرتبة أعلى أو مساوية لرتبتك'
    end
    -- لا يمكن تغيير رتبة القائد
    local gang = GangsCache[target.gang_id]
    if gang and gang.leader_citizenid == targetCitizenId then
        return false, 'لا يمكن تغيير رتبة القائد'
    end

    MySQL.update.await('UPDATE family_members SET rank_id = ? WHERE citizenid = ?',
        { newRankId, targetCitizenId })
    target.rank_id = newRankId
    return true, ('تم تحديث الرتبة إلى %s'):format(newRank.label)
end)


-- ============================================================
-- Admin UI: إضافة عضو لعائلة محددة مباشرةً بالـ CitizenID/identifier
-- يعالج مشكلة أن inviteMember كان يضيف اللاعب لعائلة الآدمن بدلاً من العائلة المختارة
-- ============================================================
lib.callback.register('qbx_families:server:adminAddMemberToGang', function(source, gangId, targetCitizenId)
    if not IsAdmin(source) then return false, 'للأدمن فقط' end

    gangId = tonumber(gangId)
    if not gangId or not GangsCache[gangId] then return false, 'العائلة غير موجودة' end

    targetCitizenId = ESXBridge.NormalizeCitizenId(targetCitizenId)
    if not targetCitizenId then return false, 'CitizenID فارغ أو غير صالح' end

    if MembersCache[targetCitizenId] then
        local currentGang = MembersCache[targetCitizenId].gang_id
        if currentGang == gangId then
            return false, 'هذا اللاعب عضو في نفس العائلة بالفعل'
        end
        return false, ('هذا اللاعب عضو في عائلة أخرى (#%s). انقله أو أخرجه أولاً'):format(currentGang or '?')
    end

    local exists, targetSrc = ESXBridge.CitizenExists(targetCitizenId)
    if not exists then return false, ('اللاعب %s غير موجود في DB'):format(targetCitizenId) end

    local lowestId, lowestOrder = nil, -1
    for _, r in pairs(RanksCache) do
        if r.gang_id == gangId and (tonumber(r.rank_order) or 0) > lowestOrder then
            lowestOrder = tonumber(r.rank_order) or 0
            lowestId = r.id
        end
    end

    if not lowestId and CreateDefaultRanksForGang then
        CreateDefaultRanksForGang(gangId, GangsCache[gangId].leader_citizenid)
        for _, r in pairs(RanksCache) do
            if r.gang_id == gangId and (tonumber(r.rank_order) or 0) > lowestOrder then
                lowestOrder = tonumber(r.rank_order) or 0
                lowestId = r.id
            end
        end
    end

    if not lowestId then return false, 'لا توجد رتب متاحة لهذه العائلة' end

    local id = MySQL.insert.await(
        'INSERT INTO family_members (gang_id, citizenid, rank_id, invited_by) VALUES (?,?,?,?)',
        { gangId, targetCitizenId, lowestId, 'admin' }
    )
    if not id then return false, 'فشل إضافة العضو' end

    MembersCache[targetCitizenId] = { id = id, gang_id = gangId, rank_id = lowestId }

    if targetSrc then
        TriggerClientEvent('esx_families:client:youJoinedGang', targetSrc, {
            gang = GangsCache[gangId],
            asLeader = false,
        })
        TriggerClientEvent('ox_lib:notify', targetSrc, {
            type = 'success', icon = 'user-plus', duration = 7000,
            title = '🤝 انضممت لعائلة',
            description = ('تم ضمك لعائلة %s\nاضغط F6 لفتح اللوحة'):format(GangsCache[gangId].label or '?'),
        })
    end

    return true, ('تم إضافة العضو إلى %s'):format(GangsCache[gangId].label or ('#' .. gangId))
end)

-- ============================================================
-- Export للملفات الثانية
-- ============================================================
exports('GetPlayerRank',     function(cid) return GetPlayerRank(cid) end)
exports('GetPlayerGang',     function(cid) return GetPlayerGang(cid) end)
exports('HasRankPermission', function(cid, perm) return HasRankPermission(cid, perm) end)
