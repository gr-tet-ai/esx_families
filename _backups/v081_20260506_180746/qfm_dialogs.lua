-- ============================================================
-- esx_families v0.8.0-p3d2 — QFM Dialogs (sync wrapper + timeout)
-- ============================================================
QFM = QFM or {}

local pending = {}
local nextTok = 1
local DIALOG_TIMEOUT_MS = 8000  -- 15s — لو NUI عاطل، نفكّ القفل

local function setFocus(state) SetNuiFocus(state, state) end

local function newToken()
    nextTok = nextTok + 1
    return 'dlg_' .. tostring(nextTok) .. '_' .. tostring(GetGameTimer())
end

local function resolveToken(tok, data)
    local co = pending[tok]
    if not co then return end
    pending[tok] = nil
    setFocus(false)
    CreateThread(function()
        local ok, err = coroutine.resume(co, data or { ok=false })
        if not ok then print('[QFM] resume error:', err) end
    end)
end

local function awaitDialog(screen, payload)
    local co = coroutine.running()
    if not co then error('[QFM] Dialog called outside coroutine; wrap in CreateThread()') end
    local tok = newToken()
    payload.token = tok
    pending[tok] = co
    print(('[DIAG_P3D3_AWAIT] sending screen=%s token=%s payload_keys=%s'):format(tostring(screen), tostring(tok), tostring(payload and table.concat((function() local k={} for kk in pairs(payload) do k[#k+1]=kk end return k end)(), ',') or 'nil')))
    setFocus(true)
    SendNUIMessage({ qfm = true, cmd = 'open', screen = screen, payload = payload })

    -- timeout watchdog
    SetTimeout(DIALOG_TIMEOUT_MS, function()
        if pending[tok] then
            print(('[QFM] TIMEOUT screen=%s token=%s — NUI did not render'):format(screen, tok))
            if lib and lib.notify then lib.notify({type='error', description='القائمة لم تستجب — جرّب /qfm_unstick'}) end
            SendNUIMessage({ qfm = true, cmd = 'close' })
            resolveToken(tok, { ok=false, timeout=true })
        end
    end)

    return coroutine.yield()
end

RegisterNUICallback('qfm:dlg', function(data, cb)
    cb({ ok = true })
    local tok = data and data.token
    if tok then resolveToken(tok, data) end
end)

function QFM.list(title, items, opts)
    opts = opts or {}
    local res = awaitDialog('dlg_list', {
        title=title, subtitle=opts.subtitle, items=items or {},
        backToken= opts.back and true or nil,
    })
    if not res or not res.ok then return nil end
    local idx = tonumber(res.value); if idx == nil then return nil end
    return idx + 1
end

function QFM.input(title, fields, opts)
    opts = opts or {}
    local res = awaitDialog('dlg_input', { title=title, subtitle=opts.subtitle, fields=fields or {} })
    if not res or not res.ok then return nil end
    return res.value or {}
end

function QFM.confirm(title, content, opts)
    opts = opts or {}
    local res = awaitDialog('dlg_confirm', {
        title=title, content=content,
        danger=opts.danger and true or false,
        confirmText=opts.confirmText, cancelText=opts.cancelText,
    })
    return (res and res.ok) and true or false
end

-- أمر طوارئ للاعب
RegisterCommand('qfm_unstick', function()
    setFocus(false)
    SendNUIMessage({ qfm = true, cmd = 'close' })
    for tok,_ in pairs(pending) do resolveToken(tok, { ok=false, force=true }) end
    print('[QFM] unstick executed')
end, false)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    setFocus(false)
    for tok, co in pairs(pending) do
        pending[tok] = nil
        pcall(coroutine.resume, co, { ok=false, stop=true })
    end
end)
