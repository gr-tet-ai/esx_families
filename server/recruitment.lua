-- ============================================================
-- esx_families - Recruitment Points System (Server) v0.5.0
-- نقاط مبايعة فعلية: NPC + blip + نظام طلبات انضمام
-- ============================================================

RecruitmentPointsCache = {}   -- [id] = { id, gang_id, name, coords_x/y/z, heading, ped_model, active }
JoinRequestsCache      = {}   -- [requestId] = { id, gang_id, citizenid, player_name, point_id, status, src_at_request }
RequestsByCid          = {}   -- [cid] = requestId (طلب نشط واحد فقط لكل لاعب)

local function loadRecruitment()
    RecruitmentPointsCache = {}
    JoinRequestsCache = {}
    RequestsByCid = {}

    local pts = MySQL.query.await('SELECT * FROM family_recruitment_points WHERE active = 1') or {}
    for _, p in ipairs(pts) do RecruitmentPointsCache[p.id] = p end

    -- v0.6.2: الطلبات كانت تُحفظ في DB لكن لا تُحمّل بعد restart، فتختفي من قائمة الرئيس.
    local reqs = MySQL.query.await([[
        SELECT id, gang_id, citizenid, player_name, recruitment_point_id, status
          FROM family_join_requests
          WHERE status = 'pending'
          ORDER BY created_at ASC
    ]]) or {}
    for _, r in ipairs(reqs) do
        JoinRequestsCache[r.id] = {
            id = r.id, gang_id = r.gang_id, citizenid = r.citizenid,
            player_name = r.player_name, recruitment_point_id = r.recruitment_point_id,
            status = r.status, src_at_request = nil,
        }
        RequestsByCid[r.citizenid] = r.id
    end

    print(('^2[esx_families]^7 تم تحميل %d نقطة مبايعة | %d طلب انضمام معلّق'):format(#pts, #reqs))
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Wait(1500)  -- بعد main + ranks (لضمان GangsCache محمّل)
    loadRecruitment()
    -- بث للجميع
    TriggerClientEvent('esx_families:client:syncRecruitmentPoints', -1, RecruitmentPointsCache, GangsCache)
end)

-- v0.5.1: استخدم esx:playerLoaded (يُطلق بعد ما player يصير جاهز فعلاً)
AddEventHandler('esx:playerLoaded', function(playerId)
    Wait(1500)
    TriggerClientEvent('esx_families:client:syncRecruitmentPoints', playerId, RecruitmentPointsCache, GangsCache)
end)

-- v0.5.1: callback لطلب صريح من client (للـ restart cases)
RegisterNetEvent('esx_families:server:requestRecruitmentPoints', function()
    local src = source
    TriggerClientEvent('esx_families:client:syncRecruitmentPoints', src, RecruitmentPointsCache, GangsCache)
end)

local function syncAll()
    TriggerClientEvent('esx_families:client:syncRecruitmentPoints', -1, RecruitmentPointsCache, GangsCache)
end

-- ============================================================
-- Helpers
-- ============================================================
local function isLeaderOrInviter(cid, gangId)
    local g = GangsCache[gangId]
    if g and g.leader_citizenid == cid then return true end
    local rank = GetPlayerRank(cid)
    return rank and rank.gang_id == gangId and rank.can_invite == 1
end

-- ============================================================
-- Callback: Leader/Admin ينشئ نقطة عند موقعه
-- ============================================================
lib.callback.register('esx_families:server:createRecruitmentPoint', function(source, gangId, name, pedModel)
    local cid = GetCitizenId(source); if not cid then return false, 'لا يوجد لاعب' end

    -- صلاحية: أدمن، أو قائد العصابة المحددة (لو ما حدد، نأخذ عصابته)
    local isAdmin = IsAdmin(source)
    if not isAdmin then
        local myGang = GetPlayerGang(cid)
        if not myGang then return false, 'لست في عائلة' end
        local g = GangsCache[myGang]
        if not g or g.leader_citizenid ~= cid then return false, 'القائد فقط يقدر ينشئ نقطة' end
        gangId = myGang  -- تجاهل أي gangId مرسل من الكلاينت لغير الأدمن
    end

    if not gangId or not GangsCache[gangId] then return false, 'العصابة غير موجودة' end

    name = (name and name ~= '' and name) or ('مكتب ' .. (GangsCache[gangId].label or 'عائلة'))
    pedModel = pedModel or 's_m_y_dealer_01'

    -- حد أقصى نقطتين لكل عصابة
    local count = 0
    for _, p in pairs(RecruitmentPointsCache) do
        if p.gang_id == gangId then count = count + 1 end
    end
    if count >= 2 then return false, 'لكل عائلة نقطتي مبايعة كحد أقصى' end

    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    local id = MySQL.insert.await(
        'INSERT INTO family_recruitment_points (gang_id, name, coords_x, coords_y, coords_z, heading, ped_model, created_by) VALUES (?,?,?,?,?,?,?,?)',
        { gangId, name, coords.x, coords.y, coords.z, heading, pedModel, cid }
    )
    if not id then return false, 'فشل الإنشاء في DB' end

    RecruitmentPointsCache[id] = {
        id = id, gang_id = gangId, name = name,
        coords_x = coords.x, coords_y = coords.y, coords_z = coords.z,
        heading = heading, ped_model = pedModel, active = 1,
    }
    syncAll()
    return true, ('تم إنشاء نقطة مبايعة "%s" لعائلة %s'):format(name, GangsCache[gangId].label)
end)

lib.callback.register('esx_families:server:deleteRecruitmentPoint', function(source, pointId)
    local cid = GetCitizenId(source); if not cid then return false end
    local p = RecruitmentPointsCache[pointId]
    if not p then return false, 'النقطة غير موجودة' end

    if not IsAdmin(source) then
        local g = GangsCache[p.gang_id]
        if not g or g.leader_citizenid ~= cid then return false, 'القائد أو الأدمن فقط' end
    end

    MySQL.query.await('DELETE FROM family_recruitment_points WHERE id = ?', { pointId })
    RecruitmentPointsCache[pointId] = nil
    syncAll()
    return true, 'تم حذف نقطة المبايعة'
end)

lib.callback.register('esx_families:server:listRecruitmentPoints', function(source, gangId)
    local list = {}
    for _, p in pairs(RecruitmentPointsCache) do
        if not gangId or p.gang_id == gangId then
            local g = GangsCache[p.gang_id]
            list[#list+1] = {
                id = p.id, gang_id = p.gang_id, gang_label = g and g.label or '?',
                name = p.name,
                coords_x = p.coords_x, coords_y = p.coords_y, coords_z = p.coords_z,
            }
        end
    end
    table.sort(list, function(a,b) return a.id < b.id end)
    return list
end)

-- ============================================================
-- Player يطلب الانضمام
-- ============================================================
lib.callback.register('esx_families:server:requestJoin', function(source, pointId)
    -- v0.6.1: retry بسيط لو xPlayer لسه ما اتحمل (race بعد restart) — الجذر #4
    local cid = GetCitizenId(source)
    if not cid then
        for i = 1, 10 do  -- 10 محاولات × 200ms = 2 ثانية كحد أقصى
            Wait(200)
            cid = GetCitizenId(source)
            if cid then break end
        end
    end
    if not cid then return false, 'لاعبك لم يكتمل تحميله — جرّب بعد ثانيتين' end

    -- لاعب موجود في عائلة؟
    if MembersCache[cid] then
        return false, ('أنت بالفعل في عائلة %s — اخرج منها أولاً'):format(
            (GangsCache[MembersCache[cid].gang_id] or {}).label or '?')
    end

    local p = RecruitmentPointsCache[pointId]
    if not p then return false, 'النقطة غير موجودة' end

    -- تحقق المسافة
    local pcoords = GetEntityCoords(GetPlayerPed(source))
    local d = #(pcoords - vector3(p.coords_x, p.coords_y, p.coords_z))
    if d > 5.0 then return false, 'بعيد عن نقطة المبايعة' end

    -- طلب نشط بالفعل؟
    if RequestsByCid[cid] then
        local oldReq = JoinRequestsCache[RequestsByCid[cid]]
        if oldReq and oldReq.status == 'pending' then
            return false, 'عندك طلب انضمام معلّق بالفعل'
        end
    end

    local g = GangsCache[p.gang_id]
    if not g then return false, 'العصابة غير موجودة' end

    -- اسم اللاعب
    local xPlayer = ESXBridge.GetPlayer(source)
    local pname = cid
    if xPlayer and xPlayer.PlayerData.charinfo then
        local ci = xPlayer.PlayerData.charinfo
        pname = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        if pname == '' then pname = cid end
    end

    local reqId = MySQL.insert.await(
        'INSERT INTO family_join_requests (gang_id, citizenid, player_name, recruitment_point_id, status) VALUES (?,?,?,?,?)',
        { p.gang_id, cid, pname, pointId, 'pending' }
    )
    if not reqId then return false, 'فشل تسجيل الطلب' end

    JoinRequestsCache[reqId] = {
        id = reqId, gang_id = p.gang_id, citizenid = cid, player_name = pname,
        recruitment_point_id = pointId, status = 'pending', src_at_request = source,
    }
    RequestsByCid[cid] = reqId

    -- أبلغ كل أعضاء العصابة الذين عندهم can_invite + القائد (أونلاين)
    local notified = 0
    for memCid, m in pairs(MembersCache) do
        if m.gang_id == p.gang_id then
            local memRank = RanksCache[m.rank_id]
            local isLeader = (g.leader_citizenid == memCid)
            if isLeader or (memRank and memRank.can_invite == 1) then
                local memSrc = ESXBridge.GetSourceByCitizenId(memCid)
                if memSrc then
                    TriggerClientEvent('esx_families:client:newJoinRequest', memSrc, {
                        id = reqId, player_name = pname, citizenid = cid,
                        gang_label = g.label, gang_id = p.gang_id,
                    })
                    notified = notified + 1
                end
            end
        end
    end

    return true, ('تم إرسال طلبك لعائلة %s\nتم تنبيه %d قيادي أونلاين'):format(g.label, notified)
end)

-- ============================================================
-- Leader/Inviter: قائمة الطلبات المعلقة
-- ============================================================
lib.callback.register('esx_families:server:listJoinRequests', function(source)
    local cid = GetCitizenId(source); if not cid then return {} end
    local gangId = GetPlayerGang(cid)

    -- v0.6.2: نفس حماية F6 — إذا العضوية في DB والكاش ضاع، استرجعها.
    if not gangId then
        local row = MySQL.single.await('SELECT id, gang_id, rank_id FROM family_members WHERE citizenid = ? LIMIT 1', { cid })
        if row and row.gang_id then
            MembersCache[cid] = { id = row.id, gang_id = row.gang_id, rank_id = row.rank_id }
            gangId = row.gang_id
        end
    end

    if not gangId or not isLeaderOrInviter(cid, gangId) then return {} end

    -- اقرأ من DB مباشرة حتى لو صار restart بعد تقديم الطلب.
    local rows = MySQL.query.await([[
        SELECT id, player_name, citizenid, gang_id, recruitment_point_id, status
        FROM family_join_requests
        WHERE gang_id = ? AND status = 'pending'
        ORDER BY created_at ASC
    ]], { gangId }) or {}

    for _, r in ipairs(rows) do
        JoinRequestsCache[r.id] = {
            id = r.id, gang_id = r.gang_id, citizenid = r.citizenid,
            player_name = r.player_name, recruitment_point_id = r.recruitment_point_id,
            status = r.status, src_at_request = nil,
        }
        RequestsByCid[r.citizenid] = r.id
    end

    return rows
end)

-- ============================================================
-- Leader/Inviter: قبول أو رفض
-- ============================================================
lib.callback.register('esx_families:server:respondJoinRequest', function(source, reqId, accept)
    local cid = GetCitizenId(source); if not cid then return false end
    local req = JoinRequestsCache[reqId]
    -- v0.6.2: إذا الطلب موجود في DB لكن الكاش فاضي بعد restart، استرجعه قبل الرد.
    if not req then
        local row = MySQL.single.await([[
            SELECT id, gang_id, citizenid, player_name, recruitment_point_id, status
            FROM family_join_requests
            WHERE id = ? AND status = 'pending'
            LIMIT 1
        ]], { reqId })
        if row then
            req = {
                id = row.id, gang_id = row.gang_id, citizenid = row.citizenid,
                player_name = row.player_name, recruitment_point_id = row.recruitment_point_id,
                status = row.status, src_at_request = nil,
            }
            JoinRequestsCache[req.id] = req
            RequestsByCid[req.citizenid] = req.id
        end
    end
    if not req or req.status ~= 'pending' then return false, 'الطلب غير موجود أو منتهي' end
    if not isLeaderOrInviter(cid, req.gang_id) then return false, 'لا تملك صلاحية' end

    local applicantSrc = ESXBridge.GetSourceByCitizenId(req.citizenid)

    if accept then
        -- تأكد من عدم الازدواجية
        if MembersCache[req.citizenid] then
            req.status = 'rejected'
            MySQL.update('UPDATE family_join_requests SET status = ?, responded_at = NOW(), responded_by = ? WHERE id = ?',
                { 'rejected', cid, reqId })
            JoinRequestsCache[reqId] = nil
            RequestsByCid[req.citizenid] = nil
            return false, 'اللاعب أصبح في عائلة أخرى'
        end

        -- أدنى رتبة
        local lowestId, lowestOrder = nil, 0
        for _, r in pairs(RanksCache) do
            if r.gang_id == req.gang_id and r.rank_order > lowestOrder then
                lowestOrder = r.rank_order; lowestId = r.id
            end
        end
        if not lowestId then return false, 'لا توجد رتب — أنشئ رتبة عضو أولاً' end

        local mid = MySQL.insert.await(
            'INSERT INTO family_members (gang_id, citizenid, rank_id, invited_by) VALUES (?,?,?,?)',
            { req.gang_id, req.citizenid, lowestId, cid })
        if not mid then return false, 'فشل الإضافة' end

        MembersCache[req.citizenid] = { id = mid, gang_id = req.gang_id, rank_id = lowestId }

        req.status = 'accepted'
        MySQL.update('UPDATE family_join_requests SET status = ?, responded_at = NOW(), responded_by = ? WHERE id = ?',
            { 'accepted', cid, reqId })
        JoinRequestsCache[reqId] = nil
        RequestsByCid[req.citizenid] = nil

        if applicantSrc then
            local g = GangsCache[req.gang_id]
            TriggerClientEvent('esx_families:client:youJoinedGang', applicantSrc, {
                gang = g, asLeader = false,
            })
            TriggerClientEvent('ox_lib:notify', applicantSrc, {
                type = 'success', icon = 'check', duration = 7000,
                title = '🤝 تم قبولك!',
                description = ('انضممت لعائلة %s\nاضغط F6 لفتح اللوحة'):format(g and g.label or '?'),
            })
        end
        return true, ('تم قبول %s'):format(req.player_name)
    else
        req.status = 'rejected'
        MySQL.update('UPDATE family_join_requests SET status = ?, responded_at = NOW(), responded_by = ? WHERE id = ?',
            { 'rejected', cid, reqId })
        JoinRequestsCache[reqId] = nil
        RequestsByCid[req.citizenid] = nil

        if applicantSrc then
            TriggerClientEvent('ox_lib:notify', applicantSrc, {
                type = 'error', icon = 'x', duration = 5000,
                description = 'تم رفض طلب انضمامك',
            })
        end
        return true, ('تم رفض %s'):format(req.player_name)
    end
end)

-- ============================================================
-- تنظيف الطلبات المنتهية (كل ساعة)
-- ============================================================
CreateThread(function()
    while true do
        Wait(60 * 60 * 1000)
        MySQL.query('UPDATE family_join_requests SET status = ? WHERE status = ? AND created_at < DATE_SUB(NOW(), INTERVAL 24 HOUR)',
            { 'expired', 'pending' })
        for id, r in pairs(JoinRequestsCache) do
            if r.status ~= 'pending' then
                JoinRequestsCache[id] = nil
                RequestsByCid[r.citizenid] = nil
            end
        end
    end
end)

-- ============================================================
-- v0.5.1: Admin Global Recruitment Management (F9)
-- ============================================================

-- كل نقاط المبايعة (للأدمن — يشوف الكل)
lib.callback.register('esx_families:server:adminListAllRecruitment', function(source)
    if not IsAdmin(source) then return {} end
    local list = {}
    for _, p in pairs(RecruitmentPointsCache) do
        local g = GangsCache[p.gang_id]
        list[#list+1] = {
            id = p.id, gang_id = p.gang_id, gang_label = g and g.label or '?',
            name = p.name,
            coords_x = p.coords_x, coords_y = p.coords_y, coords_z = p.coords_z,
        }
    end
    table.sort(list, function(a,b) return a.gang_id == b.gang_id and a.id < b.id or a.gang_id < b.gang_id end)
    return list
end)

-- كل طلبات الانضمام المعلقة في السيرفر (للأدمن)
lib.callback.register('esx_families:server:adminListAllRequests', function(source)
    if not IsAdmin(source) then return {} end
    local list = {}
    for _, r in pairs(JoinRequestsCache) do
        if r.status == 'pending' then
            local g = GangsCache[r.gang_id]
            list[#list+1] = {
                id = r.id, gang_id = r.gang_id,
                gang_label = g and g.label or '?',
                player_name = r.player_name, citizenid = r.citizenid,
            }
        end
    end
    table.sort(list, function(a,b) return a.id < b.id end)
    return list
end)

-- الأدمن يقدر ينشئ نقطة مبايعة لأي عائلة من أي مكان
lib.callback.register('esx_families:server:adminCreateRecruitment', function(source, gangId, name, pedModel)
    if not IsAdmin(source) then return false, 'للأدمن فقط' end
    if not gangId or not GangsCache[gangId] then return false, 'العصابة غير صحيحة' end

    -- الحد الأقصى لكل عائلة
    local count = 0
    for _, p in pairs(RecruitmentPointsCache) do
        if p.gang_id == gangId then count = count + 1 end
    end
    if count >= 2 then return false, 'لكل عائلة نقطتي مبايعة كحد أقصى' end

    name = (name and name ~= '' and name) or ('مكتب ' .. (GangsCache[gangId].label or 'عائلة'))
    pedModel = pedModel or 's_m_y_dealer_01'

    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    local id = MySQL.insert.await(
        'INSERT INTO family_recruitment_points (gang_id, name, coords_x, coords_y, coords_z, heading, ped_model, created_by) VALUES (?,?,?,?,?,?,?,?)',
        { gangId, name, coords.x, coords.y, coords.z, heading, pedModel, GetCitizenId(source) or 'admin' }
    )
    if not id then return false, 'فشل الإنشاء' end

    RecruitmentPointsCache[id] = {
        id = id, gang_id = gangId, name = name,
        coords_x = coords.x, coords_y = coords.y, coords_z = coords.z,
        heading = heading, ped_model = pedModel, active = 1,
    }
    syncAll()
    return true, ('تم إنشاء نقطة "%s" لعائلة %s'):format(name, GangsCache[gangId].label)
end)
