-- ============================================================
-- esx_families v0.8.0 — QFM Dialogs (sync-style wrapper)
-- API:
--   QFM.list(title, items, opts) -> idx | nil
--   QFM.input(title, fields, opts) -> {values...} | nil
--   QFM.confirm(title, content, opts) -> true | false
-- All blocking (must be called inside a CreateThread / coroutine).
-- ============================================================
QFM = QFM or {}

local pending = {}     -- token -> coroutine
local nextTok  = 1

local function setFocus(state)
    -- Reuse menu_modern's focus tracker if present, otherwise direct
    SetNuiFocus(state, state)
end

local function newToken()
    nextTok = nextTok + 1
    return 'dlg_' .. tostring(nextTok) .. '_' .. tostring(GetGameTimer())
end

local function awaitDialog(screen, payload)
    local co = coroutine.running()
    if not co then
        error('[QFM] Dialog called outside coroutine; wrap in CreateThread()')
    end
    local tok = newToken()
    payload.token = tok
    pending[tok] = co
    setFocus(true)
    SendNUIMessage({ qfm = true, cmd = 'open', screen = screen, payload = payload })
    return coroutine.yield()
end

RegisterNUICallback('qfm:dlg', function(data, cb)
    cb({ ok = true })
    setFocus(false)
    local tok = data and data.token
    local co  = tok and pending[tok]
    if not co then return end
    pending[tok] = nil
    -- resume safely on next tick to avoid NUI callback stalls
    CreateThread(function()
        local ok, err = coroutine.resume(co, data)
        if not ok then print('[QFM] resume error:', err) end
    end)
end)

-- ===== Public API =====

-- list: returns selected idx (1-based) | nil if cancelled/back
function QFM.list(title, items, opts)
    opts = opts or {}
    local res = awaitDialog('dlg_list', {
        title    = title,
        subtitle = opts.subtitle,
        items    = items or {},
        backToken= opts.back and true or nil,
    })
    if not res or not res.ok then return nil end
    local idx = tonumber(res.value)
    if idx == nil then return nil end
    return idx + 1   -- JS is 0-based, Lua 1-based
end

-- input: returns array of values | nil if cancelled
function QFM.input(title, fields, opts)
    opts = opts or {}
    local res = awaitDialog('dlg_input', {
        title    = title,
        subtitle = opts.subtitle,
        fields   = fields or {},
    })
    if not res or not res.ok then return nil end
    return res.value or {}
end

-- confirm: returns true | false
function QFM.confirm(title, content, opts)
    opts = opts or {}
    local res = awaitDialog('dlg_confirm', {
        title       = title,
        content     = content,
        danger      = opts.danger and true or false,
        confirmText = opts.confirmText,
        cancelText  = opts.cancelText,
    })
    return (res and res.ok) and true or false
end

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    for tok, co in pairs(pending) do
        pending[tok] = nil
        pcall(coroutine.resume, co, { ok=false })
    end
end)
