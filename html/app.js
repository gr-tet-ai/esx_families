
// v0.7.8: legacy war HUD quarantine — war UI is drawn only by client/war_hud_clean.lua
function __familiesHideLegacyWarHud() {
  ['war-hud'].forEach((id) => { const el = document.getElementById(id); if (el) el.classList.add('hidden'); });
}

const $ = (id) => document.getElementById(id);
const familyHud = $('family-hud');
const warHud    = $('war-hud');
const conquest  = $('conquest-bar');
const announce  = $('announce');
const countdown = $('countdown');

let cdTimerHandle = null;
let annTimerHandle = null;

function fmtMoney(n) {
  n = Number(n) || 0;
  if (n >= 1e6) return (n/1e6).toFixed(1) + 'M';
  if (n >= 1e3) return (n/1e3).toFixed(1) + 'K';
  return String(n);
}

function showAnnouncement({ sub, title, extra, duration }) {
  $('ann-sub').textContent   = sub   || '';
  $('ann-title').textContent = title || '';
  $('ann-extra').textContent = extra || '';
  announce.classList.remove('hidden');
  // restart animation
  announce.style.animation = 'none';
  void announce.offsetWidth;
  announce.style.animation = '';
  if (annTimerHandle) clearTimeout(annTimerHandle);
  annTimerHandle = setTimeout(() => announce.classList.add('hidden'), duration || 5000);
}

function startCountdown(secs) {
  if (cdTimerHandle) clearInterval(cdTimerHandle);
  let n = Math.max(1, Math.min(10, secs || 10));
  $('cd-num').textContent = n;
  countdown.classList.remove('hidden');
  cdTimerHandle = setInterval(() => {
    n -= 1;
    if (n <= 0) {
      clearInterval(cdTimerHandle); cdTimerHandle = null;
      countdown.classList.add('hidden');
    } else {
      $('cd-num').textContent = n;
    }
  }, 1000);
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  const legacyActions = ['warHud:show','warHud:hide'];
  if (legacyActions.includes(d.action)) { __familiesHideLegacyWarHud(); return; }
  if (d.action==='updateWar') console.log('[FAM]', JSON.stringify(d));

  if (d.action === 'updateFamily') {
    if (!d.show) { familyHud.classList.add('hidden'); return; }
    familyHud.classList.remove('hidden');
    $('f-title').textContent   = '👑 ' + (d.title || 'العائلة');
    $('f-rank').textContent    = d.rank || 'بدون';
    $('f-members').textContent = d.members ?? 0;
    $('f-zones').textContent   = d.zones ?? 0;
    const lock = d.vaultLocked ? ' 🔒' : '';
    $('f-vault').textContent   = '$' + fmtMoney(d.vault) + lock;
  }

  else if (d.action === 'updateWar') {
    if (!d.show) {
      warHud.classList.add('hidden');
      conquest.classList.add('hidden');
      return;
    }
    warHud.classList.add('hidden');
    $('w-title').textContent  = '⚔ ' + (d.attacker || '?') + ' ضد ' + (d.defender || '?');
    $('w-status').textContent = '📍 ' + (d.zone || '?') + ' | ' + (d.status || '—');
    $('w-mine').textContent   = d.myScore ?? 0;
    $('w-theirs').textContent = d.theirScore ?? 0;
    if (d.phase === 'preparing') {
      $('w-prep').classList.remove('hidden');
      $('w-prep-time').textContent = d.prepTimer || '—';
      $('w-timer').textContent = '⏳ مرحلة التحضير';
    } else {
      $('w-prep').classList.add('hidden');
      $('w-timer').textContent = '⏱ ' + (d.timer || '—');
    }

    // Conquest bar (للمشاركين فقط — السيرفر يرسل isParticipant)
    if (d.isParticipant) {
      warHud.classList.add('hidden');
      conquest.classList.remove('hidden');
      $('cq-atk-name').textContent  = d.attacker || '?';
      $('cq-def-name').textContent  = d.defender || '?';
      $('cq-atk-score').textContent = d.attackerScore ?? 0;
      $('cq-def-score').textContent = d.defenderScore ?? 0;
      const total = (d.attackerScore || 0) + (d.defenderScore || 0);
      let atkPct = 50, defPct = 50;
      if (total > 0) {
        atkPct = (d.attackerScore / total) * 100;
        defPct = 100 - atkPct;
      }
      $('cq-fill-atk').style.width = atkPct + '%';
      $('cq-fill-def').style.width = defPct + '%';
      $('cq-timer').textContent = (d.phase === 'preparing' ? '⏳ تحضير ' : '⏱ ') + (d.timer || d.prepTimer || '—');
    } else {
      conquest.classList.add('hidden');
    }
  }

  else if (d.action === 'announce') {
    showAnnouncement(d);
  }

  else if (d.action === 'countdown') {
    startCountdown(d.seconds);
  }

  else if (d.action === 'hideAll') {
    familyHud.classList.add('hidden');
    warHud.classList.add('hidden');
    conquest.classList.add('hidden');
    announce.classList.add('hidden');
    countdown.classList.add('hidden');
  }
});
