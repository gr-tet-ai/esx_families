-- ============================================================
-- سجل عمليات الخزنة
-- ============================================================

---@param vaultId number
---@param citizenid string|nil
---@param action string  -- deposit/withdraw/protection_tax/give_key/revoke_key
---@param item string|nil
---@param amount number
---@param note string|nil
function LogVaultAction(vaultId, citizenid, action, item, amount, note)
    MySQL.insert(
        'INSERT INTO family_vault_logs (vault_id, citizenid, action, item, amount, note) VALUES (?, ?, ?, ?, ?, ?)',
        { vaultId, citizenid, action, item, amount or 0, note }
    )
end

-- [v0.5.4] duplicate callback removed — النسخة المعتمدة في callbacks.lua (تدعم IsAdmin/keyholders)
