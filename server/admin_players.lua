-- ============================================================
-- esx_families — Online Players Picker (Hotfix)
-- يرجّع قائمة اللاعبين الأونلاين للآدمن (للاستخدام في select)
-- ============================================================

lib.callback.register('qbx_families:server:getOnlinePlayers', function(source)
    if not IsAdmin(source) then return {} end

    local players = {}
    local xPlayers = (ESX and ESX.GetExtendedPlayers and ESX.GetExtendedPlayers()) or {}

    for _, xp in pairs(xPlayers) do
        local src  = xp.source
        local cid  = xp.identifier
        local name = (xp.getName and xp.getName())
                  or (xp.get and xp.get('firstName') and (xp.get('firstName')..' '..(xp.get('lastName') or '')))
                  or GetPlayerName(src)
                  or ('Player '..src)
        players[#players+1] = {
            value = cid,
            label = ('[%d] %s — %s'):format(src, name, cid:sub(1, 24)..'...'),
        }
    end

    table.sort(players, function(a,b) return a.label < b.label end)
    return players
end)

print('^2[esx_families]^7 Online Players Picker callback loaded ✓')
