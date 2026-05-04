-- ============================================================
-- esx_families v0.6.0 — War Final Report (server)
-- يُستدعى من wars.lua عند انتهاء/forfeit الحرب
-- يبني تقرير: الفائز + النتيجة + أكثر قاتل + المكافأة
-- ============================================================

---@param war table
---@param winnerGid number|nil
function BuildWarReport(war, winnerGid)
    if not war then return end

    local atkLabel = (GangsCache[war.attacker_gang_id] or {}).label or '?'
    local defLabel = (GangsCache[war.defender_gang_id] or {}).label or '?'
    local atkScore = (war.scores and war.scores[war.attacker_gang_id]) or 0
    local defScore = (war.scores and war.scores[war.defender_gang_id]) or 0

    -- أكثر قاتل (top fragger) من DB logs
    local top = MySQL.query.await([[
        SELECT actor_citizenid AS cid, COUNT(*) AS kills
          FROM family_war_logs
         WHERE war_id = ? AND event_type IN ('kill','boss_kill')
         GROUP BY actor_citizenid
         ORDER BY kills DESC LIMIT 1
    ]], { war.id }) or {}
    local mvpCid   = top[1] and top[1].cid or nil
    local mvpKills = top[1] and top[1].kills or 0

    local winnerLabel = winnerGid == war.attacker_gang_id and atkLabel
                      or winnerGid == war.defender_gang_id and defLabel
                      or 'تعادل'

    local report = {
        warId       = war.id,
        winner      = winnerLabel,
        attacker    = { label = atkLabel, score = atkScore },
        defender    = { label = defLabel, score = defScore },
        mvpCid      = mvpCid,
        mvpKills    = mvpKills,
        durationMin = math.floor((os.time() - (war.starts_at or os.time())) / 60),
    }

    -- بث للجميع (notification بسيط)
    TriggerClientEvent('ox_lib:notify', -1, {
        type = 'success', duration = 12000, position = 'top',
        title = '🏁 انتهت الحرب: ' .. winnerLabel,
        description = ('%s %d - %d %s'):format(atkLabel, atkScore, defScore, defLabel),
        icon = 'flag-checkered', iconColor = '#ffd700',
    })

    -- إخفاء blip الحرب عند الكلاينت
    TriggerClientEvent('esx_families:client:warEndedVisual', -1, war.id)

    -- log final
    MySQL.insert([[
        INSERT INTO family_war_logs (war_id, event_type, actor_citizenid, actor_gang_id,
                                     target_citizenid, target_gang_id, points)
        VALUES (?, 'final_report', ?, ?, NULL, NULL, ?)
    ]], { war.id, mvpCid, winnerGid, atkScore + defScore })

    return report
end

-- callback لجلب التقرير من UI
lib.callback.register('esx_families:server:getWarReport', function(source, warId)
    if not warId then return nil end
    local row = MySQL.single.await('SELECT * FROM family_wars WHERE id = ?', { warId })
    if not row then return nil end
    -- إعادة بناء التقرير من DB
    local atk = (GangsCache[row.attacker_gang_id] or {}).label or '?'
    local def = (GangsCache[row.defender_gang_id] or {}).label or '?'
    local top = MySQL.query.await([[
        SELECT actor_citizenid AS cid, COUNT(*) AS kills
          FROM family_war_logs
         WHERE war_id = ? AND event_type IN ('kill','boss_kill')
         GROUP BY actor_citizenid ORDER BY kills DESC LIMIT 5
    ]], { warId }) or {}
    return {
        warId = warId, status = row.status, winner = row.winner_gang_id,
        attacker = { label = atk, score = row.attacker_score or 0 },
        defender = { label = def, score = row.defender_score or 0 },
        topFraggers = top,
    }
end)
