-- ============================================================
-- نظام الخزنة (Server-side) v0.3.0
-- إصلاحات: leader fallback، war_locked، atomic withdraw
-- ============================================================

---@param citizenid string
---@param vault table
---@param src? number
---@return boolean canOpen, string reason, table|nil rank
function CanAccessVault(citizenid, vault, src)
    local gang = GangsCache[vault.gang_id]
    if not gang then return false, 'العصابة غير موجودة' end

    -- الآدمن دائماً (يتجاوز حتى war lock)
    if src and IsAdmin(src) then return true, 'admin', nil end

    -- 🔒 إذا الخزنة مقفلة بسبب حرب → ممنوع لكل أحد ما عدا الآدمن
    if vault.war_locked == 1 then
        return false, 'الخزنة مقفلة أثناء الحرب', nil
    end

    -- القائد دائماً يفتح (حتى لو مو في family_members) — fix v0.3.0
    if gang.leader_citizenid == citizenid then return true, 'leader', nil end

    -- عضو في العصابة → اعتمد على الرتبة
    local myGang = GetPlayerGang(citizenid)
    if myGang == vault.gang_id then
        local rank = GetPlayerRank(citizenid)
        if rank and rank.can_open_vault == 1 then
            return true, 'rank', rank
        else
            return false, 'رتبتك لا تسمح بفتح الخزنة', nil
        end
    end

    -- صاحب مفتاح خارجي
    if VaultKeysCache[vault.id] and VaultKeysCache[vault.id][citizenid] then
        return true, 'keyholder', nil
    end

    return false, 'ليس لديك صلاحية الوصول للخزنة', nil
end

-- ============================================================
-- فتح الخزنة
-- ============================================================
lib.callback.register('qbx_families:server:openVault', function(source, gangId)
    local cid = GetCitizenId(source)
    if not cid then return false end

    local vault = VaultsCache[gangId]
    if not vault then return false, 'لا توجد خزنة' end

    local can, reason = CanAccessVault(cid, vault, source)
    if not can then return false, reason end

    if not IsAdmin(source) then
        -- v0.6.1: 2D distance + z tolerance يطابق client (الجذر #2)
        local coords = GetEntityCoords(GetPlayerPed(source))
        local maxDist = (Config.VaultInteractDistance or 2.0) + 1.5
        local dist2D = #(vector2(coords.x, coords.y) - vector2(vault.coords_x, vault.coords_y))
        local distZ  = math.abs(coords.z - vault.coords_z)
        if dist2D > maxDist or distZ > 3.0 then return false, 'بعيد عن الخزنة' end
    end

    local gang = GangsCache[gangId]
    local isLeader = (gang.leader_citizenid == cid) or IsAdmin(source)
    local myRank = GetPlayerRank(cid)

    return true, {
        money = vault.money,
        gangLabel = gang.label,
        isLeader = isLeader,
        keyholders = VaultKeysCache[vault.id] or {},
        myRank = myRank,
        warLocked = vault.war_locked == 1,
    }
end)

-- ============================================================
-- إيداع
-- ============================================================
lib.callback.register('qbx_families:server:depositVault', function(source, gangId, amount)
    if type(amount) ~= 'number' or amount <= 0 then return false, 'مبلغ غير صحيح' end
    amount = math.floor(amount)

    local cid = GetCitizenId(source); if not cid then return false end
    local vault = VaultsCache[gangId]; if not vault then return false, 'لا توجد خزنة' end

    if vault.war_locked == 1 then return false, 'الخزنة مقفلة أثناء الحرب' end

    local can, reason = CanAccessVault(cid, vault, source)
    if not can then return false, reason end

    local gang = GangsCache[gangId]
    if not IsAdmin(source) and gang.leader_citizenid ~= cid then
        local rank = GetPlayerRank(cid)
        if rank and rank.gang_id == gangId and rank.can_deposit ~= 1 then
            return false, 'رتبتك لا تسمح بالإيداع'
        end
    end

    local player = ESXBridge.GetPlayer(source)
    if not player or not player.PlayerData or not player.Functions then
        return false, 'تعذّر تحميل بيانات اللاعب'
    end
    if (player.PlayerData.money.cash or 0) < amount then return false, 'لا يوجد كاش كافي' end
    if not player.Functions.RemoveMoney('cash', amount, 'family-vault-deposit') then
        return false, 'فشل خصم المبلغ'
    end

    vault.money = vault.money + amount
    -- batch write — لا فوري
    PendingVaultMoneyWrites[vault.id] = vault.money
    LogVaultAction(vault.id, cid, 'deposit', nil, amount, nil)
    return true, vault.money
end)

-- ============================================================
-- سحب — atomic + daily limit
-- ============================================================
lib.callback.register('qbx_families:server:withdrawVault', function(source, gangId, amount)
    if type(amount) ~= 'number' or amount <= 0 then return false, 'مبلغ غير صحيح' end
    amount = math.floor(amount)

    local cid = GetCitizenId(source); if not cid then return false end
    local vault = VaultsCache[gangId]; if not vault then return false end

    if vault.war_locked == 1 then return false, 'الخزنة مقفلة أثناء الحرب' end

    local can, reason = CanAccessVault(cid, vault, source)
    if not can then return false, reason end

    local gang = GangsCache[gangId]
    -- القائد والآدمن معفيون من حد السحب
    if not IsAdmin(source) and gang.leader_citizenid ~= cid then
        local ok, why = CanWithdrawToday(cid, amount)
        if not ok then return false, why end
    end

    if vault.money < amount then return false, 'الخزنة لا تحتوي مبلغ كافي' end

    local player = ESXBridge.GetPlayer(source)
    if not player or not player.Functions then
        return false, 'تعذّر تحميل بيانات اللاعب'
    end
    -- خصم تفاؤلي من الكاش، ثم محاولة AddMoney
    vault.money = vault.money - amount
    local addOk = player.Functions.AddMoney('cash', amount, 'family-vault-withdraw')

    -- Rollback لو فشل AddMoney
    if not addOk then
        vault.money = vault.money + amount
        return false, 'فشل إضافة المبلغ للاعب'
    end

    -- batch write
    PendingVaultMoneyWrites[vault.id] = vault.money

    -- tracker (إلا للقائد والآدمن)
    if not IsAdmin(source) and gang.leader_citizenid ~= cid then
        AddToWithdrawTracker(cid, amount)
    end

    LogVaultAction(vault.id, cid, 'withdraw', nil, amount, nil)
    return true, vault.money
end)

-- ============================================================
-- إعطاء/سحب مفتاح خارجي
-- ============================================================
lib.callback.register('qbx_families:server:giveKey', function(source, gangId, targetCitizenId)
    local cid = GetCitizenId(source); if not cid then return false end
    local gang = GangsCache[gangId]
    local vault = VaultsCache[gangId]
    if not gang or not vault then return false, 'غير موجود' end
    if gang.leader_citizenid ~= cid then return false, 'القائد فقط يقدر يعطي مفاتيح' end
    if targetCitizenId == cid then return false, 'أنت القائد بالفعل' end

    -- لو الشخص عضو فعلاً، لا داعي للمفتاح
    if MembersCache[targetCitizenId] and MembersCache[targetCitizenId].gang_id == gangId then
        return false, 'هذا الشخص عضو في العصابة، رقّه برتبة بدلاً من إعطاء مفتاح'
    end

    VaultKeysCache[vault.id] = VaultKeysCache[vault.id] or {}
    local count = 0
    for _ in pairs(VaultKeysCache[vault.id]) do count = count + 1 end
    if count >= Config.MaxVaultKeys then
        return false, ('وصلت للحد الأقصى من المفاتيح (%d)'):format(Config.MaxVaultKeys)
    end
    if VaultKeysCache[vault.id][targetCitizenId] then
        return false, 'هذا الشخص لديه مفتاح بالفعل'
    end

    MySQL.insert.await(
        'INSERT INTO family_vault_keys (vault_id, citizenid, granted_by) VALUES (?, ?, ?)',
        { vault.id, targetCitizenId, cid }
    )
    VaultKeysCache[vault.id][targetCitizenId] = true
    LogVaultAction(vault.id, cid, 'give_key', nil, 0, 'to: ' .. targetCitizenId)
    return true
end)

lib.callback.register('qbx_families:server:revokeKey', function(source, gangId, targetCitizenId)
    local cid = GetCitizenId(source)
    local gang = GangsCache[gangId]
    local vault = VaultsCache[gangId]
    if not gang or not vault then return false end
    if gang.leader_citizenid ~= cid then return false, 'القائد فقط' end

    MySQL.query.await('DELETE FROM family_vault_keys WHERE vault_id = ? AND citizenid = ?',
        { vault.id, targetCitizenId })
    if VaultKeysCache[vault.id] then VaultKeysCache[vault.id][targetCitizenId] = nil end
    LogVaultAction(vault.id, cid, 'revoke_key', nil, 0, 'from: ' .. targetCitizenId)
    return true
end)

-- ============================================================
-- Helpers مُصدَّرة (تُستخدم في wars.lua)
-- ============================================================
function LockVault(gangId)
    local v = VaultsCache[gangId]
    if not v then return end
    v.war_locked = 1
    MySQL.update('UPDATE family_vaults SET war_locked = 1 WHERE id = ?', { v.id })
end

function UnlockVault(gangId)
    local v = VaultsCache[gangId]
    if not v then return end
    v.war_locked = 0
    MySQL.update('UPDATE family_vaults SET war_locked = 0 WHERE id = ?', { v.id })
end

function SnapshotVault(gangId)
    local v = VaultsCache[gangId]
    if not v then return 0 end
    -- flush pending write أولاً
    if PendingVaultMoneyWrites[v.id] then
        MySQL.update.await('UPDATE family_vaults SET money = ? WHERE id = ?',
            { PendingVaultMoneyWrites[v.id], v.id })
        PendingVaultMoneyWrites[v.id] = nil
    end
    v.war_snapshot = v.money
    MySQL.update('UPDATE family_vaults SET war_snapshot = ? WHERE id = ?', { v.money, v.id })
    return v.money
end

function ClearVaultSnapshot(gangId)
    local v = VaultsCache[gangId]
    if not v then return end
    v.war_snapshot = nil
    MySQL.update('UPDATE family_vaults SET war_snapshot = NULL WHERE id = ?', { v.id })
end

---ينقل مبلغ من خزنة لخزنة (atomic داخل الذاكرة + batch DB)
---@return boolean ok, number actualTransferred
function TransferVaultMoney(fromGangId, toGangId, amount)
    local from = VaultsCache[fromGangId]
    local to = VaultsCache[toGangId]
    if not from or not to then return false, 0 end
    amount = math.floor(amount)
    if amount <= 0 then return false, 0 end

    local actual = math.min(amount, from.money or 0)
    if actual <= 0 then return true, 0 end  -- لا شيء للنقل

    from.money = from.money - actual
    to.money = (to.money or 0) + actual

    -- نكتب فوراً (مهم — حالات الحرب)
    MySQL.update.await('UPDATE family_vaults SET money = ? WHERE id = ?', { from.money, from.id })
    MySQL.update.await('UPDATE family_vaults SET money = ? WHERE id = ?', { to.money, to.id })

    LogVaultAction(from.id, nil, 'war_loot_out', nil, actual, ('to gang '..toGangId))
    LogVaultAction(to.id, nil, 'war_loot_in', nil, actual, ('from gang '..fromGangId))
    return true, actual
end

exports('LockVault', LockVault)
exports('UnlockVault', UnlockVault)
exports('SnapshotVault', SnapshotVault)
exports('ClearVaultSnapshot', ClearVaultSnapshot)
exports('TransferVaultMoney', TransferVaultMoney)
exports('AddMoneyToVault', AddMoneyToVault)
