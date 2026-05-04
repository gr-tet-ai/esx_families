-- ============================================================
-- التفاعل مع الخزنة (Marker + Blip + Menu) — v0.5.0
-- ============================================================

VaultBlips = {}  -- [gangId] = blip handle

local function addVaultBlip(gangId, vault, gang)
    if VaultBlips[gangId] then RemoveBlip(VaultBlips[gangId]) end
    local b = AddBlipForCoord(vault.coords_x, vault.coords_y, vault.coords_z)
    SetBlipSprite(b, 500)             -- vault icon
    SetBlipDisplay(b, 4)
    SetBlipScale(b, 0.95)
    SetBlipColour(b, gang.blip_color or 5)  -- لون العائلة (افتراضي ذهبي)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('🏦 خزنة ' .. (gang.label or 'عائلة'))
    EndTextCommandSetBlipName(b)
    VaultBlips[gangId] = b
end

local function removeVaultBlip(gangId)
    if VaultBlips[gangId] then
        RemoveBlip(VaultBlips[gangId])
        VaultBlips[gangId] = nil
    end
end

RegisterNetEvent('qbx_families:client:vaultCreated', function(vault, gang)
    CurrentVaults[vault.gang_id] = vault
    CurrentVaults[vault.gang_id]._gang = gang
    addVaultBlip(vault.gang_id, vault, gang)
    -- v0.7.8: no startup vault-created notification spam; blip update only
end)

RegisterNetEvent('qbx_families:client:vaultDeleted', function(gangId)
    if CurrentVaults[gangId] then
        local label = CurrentVaults[gangId]._gang and CurrentVaults[gangId]._gang.label or '?'
        CurrentVaults[gangId] = nil
        removeVaultBlip(gangId)
        lib.hideTextUI()
        lib.notify({ type = 'inform', description = ('تم حذف خزنة عصابة %s'):format(label) })
    end
end)

-- نظف blips عند توقف المورد
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for gid in pairs(VaultBlips) do removeVaultBlip(gid) end
end)


-- رسم Marker للخزائن القريبة (مُحسَّن v0.5.2: 2D pre-check + textUI cache)
CreateThread(function()
    local textShown = false
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        local interactGid = nil

        for gangId, v in pairs(CurrentVaults) do
            local dx = pcoords.x - v.coords_x
            local dy = pcoords.y - v.coords_y
            if (dx*dx + dy*dy) < 625.0 then  -- 25m squared
                local dist = #(pcoords - vector3(v.coords_x, v.coords_y, v.coords_z))
                if dist < 25.0 then
                    sleep = 0
                    DrawMarker(
                        Config.VaultMarker.type,
                        v.coords_x, v.coords_y, v.coords_z - 0.95,
                        0,0,0, 0,0,0,
                        Config.VaultMarker.size.x, Config.VaultMarker.size.y, Config.VaultMarker.size.z,
                        Config.VaultMarker.color.r, Config.VaultMarker.color.g, Config.VaultMarker.color.b, Config.VaultMarker.color.a,
                        false, true, 2, Config.VaultMarker.rotate, nil, nil, false
                    )
                    if dist < Config.VaultInteractDistance then
                        interactGid = gangId
                    end
                end
            end
        end

        if interactGid then
            if not textShown then
                lib.showTextUI('[E] فتح الخزنة', { position = 'right-center' })
                textShown = true
            end
            if IsControlJustPressed(0, 38) then
                OpenVaultMenu(interactGid)
            end
        elseif textShown then
            lib.hideTextUI(); textShown = false
        end
        Wait(sleep)
    end
end)

function OpenVaultMenu(gangId)
    local ok, data = lib.callback.await('qbx_families:server:openVault', false, gangId)
    if not ok then
        return lib.notify({ type = 'error', description = data or 'فشل فتح الخزنة' })
    end

    lib.hideTextUI()

    local options = {
        { title = '💰 الرصيد', description = data.money .. ' $' .. (data.warLocked and ' 🔒 (مقفلة - حرب)' or ''), readOnly = true },
    }
    if not data.warLocked then
        options[#options+1] = { title = '⬇️ إيداع فلوس', icon = 'arrow-down', onSelect = function() VaultDeposit(gangId) end }
        options[#options+1] = { title = '⬆️ سحب فلوس',  icon = 'arrow-up',   onSelect = function() VaultWithdraw(gangId) end }
        options[#options+1] = { title = '🏦 صندوق العائلة (ممنوعات / مخدرات)', icon = 'box',
            description = 'تخزين مشترك بإذن الأعضاء',
            onSelect = function() OpenFamilyStash(gangId) end }
    end
    options[#options+1] = { title = '📜 سجل العمليات', icon = 'list', onSelect = function() VaultLogs(gangId) end }

    if data.isLeader then
        table.insert(options, { title = '🔑 إدارة المفاتيح', icon = 'key', onSelect = function() VaultKeys(gangId, data.keyholders) end })
    end

    lib.registerContext({
        id = 'family_vault',
        title = '🏦 خزنة ' .. data.gangLabel,
        options = options,
    })
    lib.showContext('family_vault')
end

function VaultDeposit(gangId)
    local input = lib.inputDialog('إيداع في الخزنة', { { type = 'number', label = 'المبلغ', min = 1 } })
    if not input or not input[1] then return end
    local ok, res = lib.callback.await('qbx_families:server:depositVault', false, gangId, input[1])
    if ok then lib.notify({ type = 'success', description = 'تم الإيداع. الرصيد: ' .. res })
    else      lib.notify({ type = 'error',   description = res or 'فشل الإيداع' }) end
end

function VaultWithdraw(gangId)
    local input = lib.inputDialog('سحب من الخزنة', { { type = 'number', label = 'المبلغ', min = 1 } })
    if not input or not input[1] then return end
    local ok, res = lib.callback.await('qbx_families:server:withdrawVault', false, gangId, input[1])
    if ok then lib.notify({ type = 'success', description = 'تم السحب. الرصيد: ' .. res })
    else      lib.notify({ type = 'error',   description = res or 'فشل السحب' }) end
end

function VaultLogs(gangId)
    local logs = lib.callback.await('qbx_families:server:getVaultLogs', false, gangId, 30)
    local options = {}
    for _, log in ipairs(logs or {}) do
        table.insert(options, {
            title = ('%s - %s'):format(log.action, log.amount or 0),
            description = ('%s | %s'):format(log.citizenid or 'system', log.note or ''),
            readOnly = true,
        })
    end
    if #options == 0 then options[1] = { title = 'لا توجد عمليات', readOnly = true } end
    lib.registerContext({ id = 'vault_logs', title = '📜 سجل الخزنة', menu = 'family_vault', options = options })
    lib.showContext('vault_logs')
end

function VaultKeys(gangId, keyholders)
    local options = {
        { title = '➕ إضافة مفتاح جديد', icon = 'plus', onSelect = function()
            local input = lib.inputDialog('إعطاء مفتاح', { { type = 'input', label = 'CitizenID للعضو', required = true } })
            if not input or not input[1] then return end
            local ok, err = lib.callback.await('qbx_families:server:giveKey', false, gangId, input[1])
            if ok then lib.notify({ type = 'success', description = 'تم إعطاء المفتاح' })
            else      lib.notify({ type = 'error',   description = err or 'فشل' }) end
        end },
    }
    for cid, _ in pairs(keyholders or {}) do
        table.insert(options, {
            title = '🔑 ' .. cid,
            description = 'اضغط للسحب',
            onSelect = function()
                local ok = lib.callback.await('qbx_families:server:revokeKey', false, gangId, cid)
                if ok then lib.notify({ type = 'success', description = 'تم سحب المفتاح' }) end
            end,
        })
    end
    lib.registerContext({ id = 'vault_keys', title = '🔑 إدارة المفاتيح', menu = 'family_vault', options = options })
    lib.showContext('vault_keys')
end
