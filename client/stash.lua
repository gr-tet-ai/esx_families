-- ============================================================
-- esx_families v0.5.3 — Stash UI (ox_lib menus)
-- ============================================================
-- قائمة احترافية بنفس مستوى متجر الأسلحة
-- ============================================================

local function fmtWeight(g)
    if g >= 1000 then return ('%.1f kg'):format(g / 1000) end
    return ('%d g'):format(g)
end

local function openDepositSubMenu(gangId, data)
    local options = {}

    if #data.myInventory == 0 then
        options[#options+1] = { title = 'جردك فارغ', disabled = true, icon = 'box-open' }
    else
        for _, it in ipairs(data.myInventory) do
            options[#options+1] = {
                title = ('📥 %s'):format(it.label),
                description = ('عندك: %d  •  وزن القطعة: %s'):format(it.count, fmtWeight(it.weight)),
                icon = 'arrow-down',
                onSelect = function()
                    local input = lib.inputDialog(('إيداع %s'):format(it.label), {
                        { type = 'number', label = 'الكمية', default = 1, min = 1, max = it.count, required = true },
                    })
                    if not input or not input[1] then return end
                    local ok, msg = lib.callback.await('esx_families:server:stashDeposit', false, gangId, it.name, input[1])
                    lib.notify({ title = '🏦 صندوق العائلة', description = msg or '?', type = ok and 'success' or 'error' })
                    Wait(200)
                    OpenFamilyStash(gangId)
                end,
            }
        end
    end

    options[#options+1] = { title = '↩️ رجوع', icon = 'arrow-left', onSelect = function() OpenFamilyStash(gangId) end }

    lib.registerContext({
        id = 'esx_families_stash_deposit',
        title = '📥 إيداع في الصندوق',
        menu  = 'esx_families_stash_main',
        options = options,
    })
    lib.showContext('esx_families_stash_deposit')
end

local function openWithdrawSubMenu(gangId, data)
    local options = {}

    if #data.stash == 0 then
        options[#options+1] = { title = 'الصندوق فارغ', disabled = true, icon = 'box-open' }
    else
        for _, it in ipairs(data.stash) do
            options[#options+1] = {
                title = ('📤 %s × %d'):format(it.label, it.count),
                description = ('وزن القطعة: %s'):format(fmtWeight(it.weight)),
                icon = 'arrow-up',
                onSelect = function()
                    local input = lib.inputDialog(('سحب %s'):format(it.label), {
                        { type = 'number', label = 'الكمية', default = 1, min = 1, max = it.count, required = true },
                    })
                    if not input or not input[1] then return end
                    local ok, msg = lib.callback.await('esx_families:server:stashWithdraw', false, gangId, it.name, input[1])
                    lib.notify({ title = '🏦 صندوق العائلة', description = msg or '?', type = ok and 'success' or 'error' })
                    Wait(200)
                    OpenFamilyStash(gangId)
                end,
            }
        end
    end

    options[#options+1] = { title = '↩️ رجوع', icon = 'arrow-left', onSelect = function() OpenFamilyStash(gangId) end }

    lib.registerContext({
        id = 'esx_families_stash_withdraw',
        title = '📤 سحب من الصندوق',
        menu  = 'esx_families_stash_main',
        options = options,
    })
    lib.showContext('esx_families_stash_withdraw')
end

-- القائمة الرئيسية للصندوق
function OpenFamilyStash(gangId)
    local data, err = lib.callback.await('esx_families:server:stashGetContents', false, gangId)
    if not data then
        lib.notify({ title = '🏦 صندوق العائلة', description = err or 'تعذّر فتح الصندوق', type = 'error' })
        return
    end

    local pct = math.floor((data.currentWeight / data.maxWeight) * 100)
    local options = {
        {
            title = '📊 حالة الصندوق',
            description = ('الوزن: %s / %s  (%d%%)  •  عدد الأنواع: %d'):format(
                fmtWeight(data.currentWeight), fmtWeight(data.maxWeight), pct, #data.stash
            ),
            icon = 'chart-pie',
            disabled = true,
        },
        {
            title = '📥 إيداع قطعة',
            description = 'انقل من جردك إلى الصندوق',
            icon = 'arrow-down',
            onSelect = function() openDepositSubMenu(gangId, data) end,
        },
        {
            title = '📤 سحب قطعة',
            description = 'انقل من الصندوق إلى جردك',
            icon = 'arrow-up',
            onSelect = function() openWithdrawSubMenu(gangId, data) end,
        },
    }

    lib.registerContext({
        id = 'esx_families_stash_main',
        title = '🏦 صندوق العائلة',
        options = options,
    })
    lib.showContext('esx_families_stash_main')
end

-- event من الـ vault marker (نفس آلية v0.5.2)
RegisterNetEvent('esx_families:client:openStash', function(gangId)
    OpenFamilyStash(gangId)
end)
