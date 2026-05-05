-- esx_families v0.8.0 — Modern NUI bridge for F6 main menu
local function fmtMoney(n)
  n = tonumber(n) or 0
  if n >= 1e6 then return string.format('%.1fM', n/1e6) end
  if n >= 1e3 then return string.format('%.1fK', n/1e3) end
  return tostring(n)
end

local nuiOpen = false

local function setNui(state)
  if nuiOpen == state then return end
  nuiOpen = state
  SetNuiFocus(state, state)
end

function CloseModernFamilyMenu(reason)
  if nuiOpen then
    SendNUIMessage({ qfm = true, cmd = 'close' })
    setNui(false)
  end
end

-- builds the same option set as legacy OpenFamilyMainMenu (logic mirrored 1:1)
local function buildItems(ctx)
  local items = {}
  if ctx.gang then
    items[#items+1] = {
      title = ('🏛️ %s'):format(ctx.gang.label),
      desc  = ('رتبتك: %s\nالخزينة: %s | %d عضو | %d منطقة'):format(
        (ctx.rank and ctx.rank.label) or 'بدون رتبة',
        fmtMoney(ctx.vault and ctx.vault.money or 0),
        ctx.memberCount or 0, ctx.zoneCount or 0),
      icon = '🏛', iconColor = 'orange', readOnly = true,
    }
    items[#items+1] = { title='📊 نظرة عامة', desc='تفاصيل العائلة والمناطق والخزنة', icon='📊', action='overview', id=tostring(ctx.gang.id) }
    items[#items+1] = { title='👥 الأعضاء', desc='عرض / دعوة / طرد / ترقية', icon='👥', action='members', id=tostring(ctx.gang.id) }

    local canHandleRequests = ctx.isLeader or (ctx.rank and ctx.rank.can_invite == 1)
    if canHandleRequests then
      items[#items+1] = { title='🤝 طلبات الانضمام', desc='قبول/رفض اللاعبين الذين تقدموا للمبايعة', icon='🤝', iconColor='green', action='join_requests' }
    end
    if ctx.isLeader then
      items[#items+1] = { title='📍 نقاط المبايعة', desc='إنشاء/إدارة نقاط الانضمام لعائلتك', icon='📍', iconColor='orange', action='recruit_points', id=tostring(ctx.gang.id) }
    end
    if ctx.isLeader or ctx.isAdmin then
      items[#items+1] = { title='🎖️ الرتب والصلاحيات', desc='إنشاء / تعديل / حذف الرتب', icon='🎖', action='ranks', id=tostring(ctx.gang.id) }
    end
    items[#items+1] = { title='🗺️ مناطقي', desc='عرض المناطق + تحديد على الخريطة', icon='🗺', action='my_zones', id=tostring(ctx.gang.id) }
    if ctx.vault then
      items[#items+1] = { title='🏦 الخزنة', desc=(ctx.vault.war_locked and '🔒 مقفلة (حرب)' or 'فتح / إيداع / سحب / مفاتيح'), icon='🏦', action='vault', id=tostring(ctx.gang.id) }
    end
    items[#items+1] = {
      title='⚔️ الحروب',
      desc=(ctx.myWar and ('حرب نشطة: %s vs %s'):format(ctx.myWar.attacker_label, ctx.myWar.defender_label) or 'إعلان حرب / مجلس الحرب'),
      icon='⚔', iconColor=(ctx.myWar and 'red' or nil), action='wars',
    }
    if ctx.isLeader and not ctx.myWar then
      items[#items+1] = { title='⚡ إعلان حرب مباشر', desc='اختر زون عدو لمهاجمته فوراً (للقائد فقط)', icon='⚡', iconColor='orange', action='war_declare_quick' }
    end
    if not ctx.isLeader then
      items[#items+1] = { title='🚪 مغادرة العائلة', desc='الخروج من العضوية نهائياً', icon='🚪', iconColor='red', action='leave_gang' }
    end
  end

  items[#items+1] = { title='🌐 العائلات في السيرفر', desc='قائمة بكل العائلات المسجلة', icon='🌐', action='public_gangs' }
  items[#items+1] = { title='📜 الحروب الجارية', desc='عرض كل الحروب النشطة', icon='📜', action='public_wars' }

  if ctx.isAdmin then
    items[#items+1] = { title='⚙️ لوحة الإدارة (F9)', desc='إدارة كل العائلات والمناطق والخزائن ونقاط المبايعة', icon='⚙', iconColor='green', action='open_admin' }
  end
  return items
end

function OpenModernFamilyMainMenu(ctx)
  local items = buildItems(ctx)
  setNui(true)
  SendNUIMessage({
    qfm = true, cmd = 'open', screen = 'f6_main',
    payload = {
      title    = ctx.gang and ctx.gang.label or 'نظام العوائل',
      subtitle = ctx.gang and ('عائلتك · ' .. (ctx.rank and ctx.rank.label or 'بدون رتبة')) or 'لوحة العائلات',
      items    = items,
    }
  })
end

-- NUI callbacks
RegisterNUICallback('qfm:close', function(_, cb)
  setNui(false); cb({ ok = true })
end)

RegisterNUICallback('qfm:select', function(data, cb)
  setNui(false)
  cb({ ok = true })
  local act = data and data.action or ''
  local id  = tonumber(data and data.id) or nil
  -- Phase 1: dispatch back to legacy ox_lib sub-menus (already loaded in client/menu.lua)
  if act == 'overview'        and id then ShowFamilyOverview(id)
  elseif act == 'members'     and id then OpenMembersMenu(id)
  elseif act == 'join_requests'    then OpenJoinRequestsMenu()
  elseif act == 'recruit_points' and id then OpenMyRecruitmentMenu(id)
  elseif act == 'ranks'       and id then OpenRanksMenu(id)
  elseif act == 'my_zones'    and id then ShowMyZones(id)
  elseif act == 'vault'       and id then OpenVaultMenu(id)
  elseif act == 'wars'                then OpenWarsMenuFromF6()
  elseif act == 'war_declare_quick'   then if ShowAttackableZonesUI then ShowAttackableZonesUI() else OpenWarsMenuFromF6() end
  elseif act == 'leave_gang'          then
    local c = lib.alertDialog({ header='تأكيد المغادرة', content='هل أنت متأكد من مغادرة العائلة؟', centered=true, cancel=true })
    if c == 'confirm' then
      local ok, msg = lib.callback.await('qbx_families:server:leaveGang', false)
      if notify then notify(ok and 'success' or 'error', msg) end
    end
  elseif act == 'public_gangs'        then ShowPublicGangsList()
  elseif act == 'public_wars'         then ShowPublicWarsList()
  elseif act == 'open_admin'          then if OpenAdminMenu then OpenAdminMenu() end
  end
end)

-- safety: close on resource stop
AddEventHandler('onResourceStop', function(r)
  if r == GetCurrentResourceName() and nuiOpen then setNui(false) end
end)
