-- ============================================================
-- qbx_families - Shared Library v0.3.0
-- يُحمَّل في server و client (راجع fxmanifest)
-- مُحسَّن للأداء: O(1) lookups، spatial grid، helpers خفيفة
-- ============================================================

Shared = {}

-- ============================================================
-- (1) Illegal Items Set — O(1) lookup بدلاً من linear scan
-- ============================================================
Shared.IllegalItemsSet = {}

local function buildIllegalSet()
    Shared.IllegalItemsSet = {}
    for _, name in ipairs(Config.IllegalItems or {}) do
        Shared.IllegalItemsSet[name] = true
    end
end

---@param itemName string
---@return boolean
function Shared.IsIllegalItem(itemName)
    if not itemName then return false end
    return Shared.IllegalItemsSet[itemName] == true
end

-- ============================================================
-- (2) FormatMoney — تنسيق الأرقام
-- ============================================================
---@param n number
---@return string
function Shared.FormatMoney(n)
    n = tonumber(n) or 0
    local formatted = tostring(math.floor(n))
    -- إضافة فواصل
    local k
    while true do
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return '$' .. formatted
end

-- ============================================================
-- (3) Spatial Grid Index للزونات (O(1) findZoneAt)
-- يقسم الخريطة إلى cells 500x500m
-- ============================================================
Shared.GRID_CELL_SIZE = 500.0
Shared.SpatialGrid = {}  -- [cellKey] = { zoneId1, zoneId2, ... }

local function cellKey(x, y)
    local cx = math.floor(x / Shared.GRID_CELL_SIZE)
    local cy = math.floor(y / Shared.GRID_CELL_SIZE)
    return cx .. ':' .. cy
end

---يضيف zone للـ grid (يُستدعى عند تحميل/إنشاء zone)
---@param zone table
function Shared.AddZoneToGrid(zone)
    if not zone or not zone.id then return end
    -- نحدد كل cells اللي تتقاطع مع دائرة الزون
    local r = zone.radius or 50.0
    local minCx = math.floor((zone.center_x - r) / Shared.GRID_CELL_SIZE)
    local maxCx = math.floor((zone.center_x + r) / Shared.GRID_CELL_SIZE)
    local minCy = math.floor((zone.center_y - r) / Shared.GRID_CELL_SIZE)
    local maxCy = math.floor((zone.center_y + r) / Shared.GRID_CELL_SIZE)
    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            local k = cx .. ':' .. cy
            Shared.SpatialGrid[k] = Shared.SpatialGrid[k] or {}
            -- منع التكرار
            local exists = false
            for _, zid in ipairs(Shared.SpatialGrid[k]) do
                if zid == zone.id then exists = true; break end
            end
            if not exists then
                Shared.SpatialGrid[k][#Shared.SpatialGrid[k]+1] = zone.id
            end
        end
    end
end

---يحذف zone من الـ grid
---@param zone table
function Shared.RemoveZoneFromGrid(zone)
    if not zone or not zone.id then return end
    local r = zone.radius or 50.0
    local minCx = math.floor((zone.center_x - r) / Shared.GRID_CELL_SIZE)
    local maxCx = math.floor((zone.center_x + r) / Shared.GRID_CELL_SIZE)
    local minCy = math.floor((zone.center_y - r) / Shared.GRID_CELL_SIZE)
    local maxCy = math.floor((zone.center_y + r) / Shared.GRID_CELL_SIZE)
    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            local k = cx .. ':' .. cy
            local cell = Shared.SpatialGrid[k]
            if cell then
                for i = #cell, 1, -1 do
                    if cell[i] == zone.id then table.remove(cell, i) end
                end
                if #cell == 0 then Shared.SpatialGrid[k] = nil end
            end
        end
    end
end

---يبني الـ grid من cache كامل (يُستدعى عند بدء السكربت)
---@param zonesCache table [id] = zone
function Shared.RebuildSpatialGrid(zonesCache)
    Shared.SpatialGrid = {}
    for _, z in pairs(zonesCache) do Shared.AddZoneToGrid(z) end
end

---البحث الذكي: نحدد cell الإحداثيات + نفحص zones في تلك cell فقط
---@param x number
---@param y number
---@param zonesCache table
---@return table|nil zone (الأقرب للمركز)
function Shared.FindZoneAt(x, y, zonesCache)
    local k = cellKey(x, y)
    local cell = Shared.SpatialGrid[k]
    if not cell then return nil end

    local best, bestDist = nil, math.huge
    for i = 1, #cell do
        local z = zonesCache[cell[i]]
        if z then
            local dx = x - z.center_x
            local dy = y - z.center_y
            local dist = math.sqrt(dx*dx + dy*dy)
            if dist <= z.radius and dist < bestDist then
                best, bestDist = z, dist
            end
        end
    end
    return best
end

-- ============================================================
-- (4) Debug — يُطفى في production
-- ============================================================
function Shared.Debug(...)
    if Config and Config.Debug then
        print('^3[qbx_families:debug]^7', ...)
    end
end

-- ============================================================
-- (5) Init
-- ============================================================
CreateThread(function()
    -- ننتظر تحميل Config
    while not Config or not Config.IllegalItems do Wait(50) end
    buildIllegalSet()
    Shared.Debug('Shared initialized: '..tostring(#Config.IllegalItems)..' illegal items')
end)
