fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'esx_families'
author 'Lovable AI for Family Server'
description 'ESX Family/Gang System v0.6.3b — Identifier + Manifest Start Fix'
version '0.8.0-p3d1'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'shared/shared.lua',
}

server_scripts {
    'server/kill_relay_pathC.lua',
    '@oxmysql/lib/MySQL.lua',
    'server/esx_bridge.lua',
    'server/war_time.lua',
    'server/main.lua',
    'server/admin_config.lua',
    'server/ranks.lua',
    'server/zones.lua',
    'server/vault.lua',
    'server/stash.lua',
    'server/protection.lua',
    'server/admin.lua',
    'server/admin_players.lua',
    'server/callbacks.lua',
    'server/trade.lua',
    'server/recruitment.lua',
    'server/wars.lua',
    'server/wars_admin.lua',
    'server/wars_force_console.lua',
    'server/war_report.lua',
    'server/diagnostics.lua',
    'server/logs.lua',
    'server/war_hud_heartbeat.lua',
}

client_scripts {
    'client/kill_detector_pathC.lua',
    'client/war_time.lua',
    'client/main.lua',
    'client/bootstrap_failsafe.lua',
    'client/zones.lua',
    'client/vault.lua',
    'client/stash.lua',
    'client/notifications.lua',
    'client/qfm_dialogs.lua',
    'client/menu_modern.lua',
    'client/menu.lua',
    'client/menu_members.lua',
    'client/menu_ranks.lua',
    'client/menu_admin.lua',
    'client/menu_recruitment.lua',
    'client/recruitment.lua',
    'client/hud.lua',
    'client/trade.lua',
    'client/wars.lua',
    'client/war_visual.lua',
    'client/war_hud_clean.lua',
    'client/war_topbar_failsafe.lua',
}

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/menu/style.css',
    'html/menu/core.js',
    'html/menu/screens/f6_main.js',
    'html/menu/screens/f6_dialogs.js',
}

-- esx_families v0.7.0e hard kill detector
client_script 'client/kill_detector_v0_7_0e.lua'
client_script 'client/kill_detector_attacker.lua'

-- esx_families v0.7.0e hard kill relay
server_script 'server/kill_relay_v0_7_0e.lua'
