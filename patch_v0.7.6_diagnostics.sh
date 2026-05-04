#!/usr/bin/env bash
# ============================================================
# esx_families v0.7.6 — Diagnostics Pack
# ============================================================
# يضيف أدوات تشخيص فقط (لا يغيّر منطق):
#   - /familywar_simkill <victimSrc>   (client) يحاكي قتل ويستدعي reportKill
#   - /familywar_strace on|off          (server) تريس مفصّل لكل decision في reportKill
#   - /familywar_clienttrace on|off     (client) — مفعّل افتراضياً للجلسة
# ============================================================
set -euo pipefail

RES="/root/fivem/txData/ESXLegacy_F5DD44.base/resources/[esx_addons]/esx_families"
TS="$(date +%Y%m%d_%H%M%S)"

CLIENT_WARS="$RES/client/wars.lua"
SERVER_WARS="$RES/server/wars.lua"

for f in "$CLIENT_WARS" "$SERVER_WARS"; do
  [ -f "$f" ] || { echo "❌ مفقود: $f"; exit 1; }
  cp "$f" "$f.bak.v076.$TS"
done
echo "📋 backups: *.bak.v076.$TS"

python3 <<'PY'
from pathlib import Path
RES = Path('/root/fivem/txData/ESXLegacy_F5DD44.base/resources/[esx_addons]/esx_families')
cw = RES / 'client/wars.lua'
sw = RES / 'server/wars.lua'

# ---------- CLIENT: simkill + force-enable trace ----------
cwt = cw.read_text(encoding='utf-8')
if 'v0.7.6 Diagnostics' not in cwt:
    block = r"""

-- ============================================================
-- v0.7.6 Diagnostics — simkill + force-enable trace
-- ============================================================
CreateThread(function()
    Wait(2500)
    if FAM75_TRACE ~= nil then
        FAM75_TRACE = true
        print('[esx_families:client-kill] trace AUTO-ON (v0.7.6 diag)')
    end
end)

RegisterCommand('familywar_simkill', function(_, args)
    local victimSrc = tonumber(args[1])
    if not victimSrc or victimSrc <= 0 then
        print('Usage: /familywar_simkill <victimServerId>')
        return
    end
    local mySrc = GetPlayerServerId(PlayerId())
    if victimSrc == mySrc then
        print('[esx_families:client-kill] simkill rejected: cannot kill self')
        return
    end
    print(('[esx_families:client-kill] SIMKILL fired mySrc=%d -> victim=%d'):format(mySrc, victimSrc))
    TriggerServerEvent('qbx_families:server:reportKill', mySrc, victimSrc)
end, false)

RegisterCommand('familywar_simctx', function()
    local cw  = CurrentWar
    local cz  = CurrentZone
    print(('[esx_families:client-kill] CTX CurrentWar=%s CurrentZone=%s zoneMatch=%s'):format(
        cw and (cw.id or '?') or 'nil',
        cz and (cz.id or '?') or 'nil',
        (cw and cz and cw.zone == cz.id) and 'YES' or 'NO'
    ))
    if MyContext and MyContext.myWar then
        local mw = MyContext.myWar
        print(('[esx_families:client-kill] MyContext.myWar id=%s status=%s side=%s scores=%s:%s'):format(
            tostring(mw.id), tostring(mw.status), tostring(mw.my_side),
            tostring(mw.attacker_score), tostring(mw.defender_score)
        ))
    else
        print('[esx_families:client-kill] MyContext.myWar = nil')
    end
end, false)
"""
    cw.write_text(cwt.rstrip() + block + '\n', encoding='utf-8')
    print('✅ client/wars.lua: added simkill + simctx + auto-trace')
else:
    print('↷ client/wars.lua: v0.7.6 already present')

# ---------- SERVER: strace inside reportKill ----------
swt = sw.read_text(encoding='utf-8')
if 'FAM76_STRACE' not in swt:
    # 1) inject globals + command at top (after first line)
    header = r"""
-- ============================================================
-- v0.7.6 Diagnostics — server-side reportKill trace
-- ============================================================
FAM76_STRACE = false
local function fam76(msg)
    if FAM76_STRACE then
        print(('[esx_families:strace] %s'):format(msg))
    end
end

RegisterCommand('familywar_strace', function(src, args)
    if src ~= 0 then return end
    FAM76_STRACE = (args[1] == 'on' or args[1] == '1' or args[1] == 'true')
    print('[esx_families:strace] server trace ' .. (FAM76_STRACE and 'ON' or 'OFF'))
end, true)

"""
    swt = header + swt

    # 2) inject trace lines into reportKill — replace the function signature line
    target = "RegisterNetEvent('qbx_families:server:reportKill', function(killerSrc, victimSrc)\n    local actualSrc = source  -- نتجاهل killerSrc من الكلاينت لأمان\n    if killerSrc ~= actualSrc then return end  -- spoofing protection"
    repl = """RegisterNetEvent('qbx_families:server:reportKill', function(killerSrc, victimSrc)
    local actualSrc = source  -- نتجاهل killerSrc من الكلاينت لأمان
    fam76(('reportKill IN actualSrc=%s claimedKiller=%s victim=%s'):format(tostring(actualSrc), tostring(killerSrc), tostring(victimSrc)))
    if killerSrc ~= actualSrc then fam76('REJECT: spoofing (killerSrc != source)'); return end"""
    if target in swt:
        swt = swt.replace(target, repl, 1)
    else:
        raise SystemExit('ERR: لم أجد reportKill signature في server/wars.lua')

    # 3) more trace points using simple string substitutions
    pairs = [
        (
            "    LastKillEventAt[actualSrc] = nowMs\n\n    local killerCid = GetCitizenId(actualSrc)\n    if not killerCid then return end",
            "    LastKillEventAt[actualSrc] = nowMs\n\n    local killerCid = GetCitizenId(actualSrc)\n    if not killerCid then fam76('REJECT: killerCid nil'); return end\n    fam76('killerCid=' .. tostring(killerCid))"
        ),
        (
            "    local victim = tonumber(victimSrc)\n    if not victim or victim == 0 or victim == actualSrc then return end\n    local victimCid = GetCitizenId(victim)\n    if not victimCid then return end",
            "    local victim = tonumber(victimSrc)\n    if not victim or victim == 0 or victim == actualSrc then fam76('REJECT: bad victim id ' .. tostring(victimSrc)); return end\n    local victimCid = GetCitizenId(victim)\n    if not victimCid then fam76('REJECT: victimCid nil for src=' .. tostring(victim)); return end\n    fam76('victimCid=' .. tostring(victimCid))"
        ),
        (
            "    local war, killerGid = getWarFor(killerCid)\n    if not war then return end\n    local victimGid = war.participants[victimCid]\n    if not victimGid or victimGid == killerGid then return end  -- friendly fire يا جانب آخر",
            "    local war, killerGid = getWarFor(killerCid)\n    if not war then fam76('REJECT: killer not in any active war'); return end\n    fam76(('war=%s killerGid=%s'):format(tostring(war.id), tostring(killerGid)))\n    local victimGid = war.participants[victimCid]\n    if not victimGid then fam76('REJECT: victim not participant in war ' .. tostring(war.id) .. ' (victimCid=' .. tostring(victimCid) .. ')'); return end\n    if victimGid == killerGid then fam76('REJECT: friendly fire same gang ' .. tostring(killerGid)); return end\n    fam76('victimGid=' .. tostring(victimGid))"
        ),
        (
            "        if d > zone.radius + (Config.War.killConfirmRadius or 50.0) then return end",
            "        fam76(('zone-check dist=%.1f radius=%.1f confirm=%.1f'):format(d, zone.radius, (Config.War.killConfirmRadius or 50.0)))\n        if d > zone.radius + (Config.War.killConfirmRadius or 50.0) then fam76('REJECT: victim outside zone'); return end"
        ),
        (
            "    if (os.time() - lastDeath) < cdSec then\n        return  -- نفس القتيل قُتل قريباً — ما يحتسب\n    end",
            "    if (os.time() - lastDeath) < cdSec then\n        fam76('REJECT: victim cooldown ' .. tostring(cdSec - (os.time()-lastDeath)) .. 's left')\n        return\n    end"
        ),
    ]
    for old, new in pairs:
        if old in swt:
            swt = swt.replace(old, new, 1)
        else:
            print('⚠ skip pair (not found, non-fatal): ' + old.split(chr(10))[0][:60])

    sw.write_text(swt, encoding='utf-8')
    print('✅ server/wars.lua: added strace + reportKill trace points')
else:
    print('↷ server/wars.lua: v0.7.6 already present')
PY

echo ""
echo "════════════════════════════════════════════════════"
echo "✅ v0.7.6 Diagnostics Pack installed"
echo "════════════════════════════════════════════════════"
echo ""
echo "▶️  في txAdmin Console:"
echo "    ensure esx_families"
echo "    familywar_strace on"
echo ""
echo "🧪 الاختبار الحاسم (3 خطوات بالترتيب):"
echo ""
echo "── اختبار A: simkill (يعزل منطق السيرفر) ──"
echo "  1) ابدأ حرب فعلية مع لاعب آخر (أو حساب ثاني)"
echo "  2) داخل الزون، في F8 شغّل:"
echo "       /familywar_simctx          ← يعرض حالة CurrentWar/Zone عندك"
echo "       /familywar_simkill <victimServerId>"
echo "  3) راقب txAdmin:"
echo "     • إذا ظهر [esx_families:war-kill] COUNTED → السيرفر سليم،"
echo "       المشكلة في كشف القتل التلقائي (ننتقل لـ B)"
echo "     • إذا ظهر [esx_families:strace] REJECT: ... → السبب واضح هنا"
echo ""
echo "── اختبار B: قتل حقيقي + clienttrace ──"
echo "  1) من F8: /familywar_clienttrace on (شغال auto لكن للتأكيد)"
echo "  2) اقتل اللاعب الآخر داخل الزون"
echo "  3) ابعث لي كل أسطر [esx_families:client-kill] و [esx_families:strace]"
echo ""
echo "🔙 رجوع: استرجع *.bak.v076.$TS"
