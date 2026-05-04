-- ============================================================
-- إدارة الزونات (Server-side) v0.3.0 — uses spatial grid
-- ============================================================

---إيجاد الزون اللي يحتوي إحداثيات معينة (O(1) عبر spatial grid)
---@param x number
---@param y number
---@return table|nil zone
function FindZoneAt(x, y)
    return Shared.FindZoneAt(x, y, ZonesCache)
end

-- مزامنة عند الطلب من الكلاينت
RegisterNetEvent('qbx_families:server:requestZones', function()
    local src = source
    TriggerClientEvent('qbx_families:client:syncZones', src, ZonesCache, GangsCache)
end)
