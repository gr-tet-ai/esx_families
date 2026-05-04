-- ============================================================
-- qbx_families — Migration v0.2.0 → v0.3.0
-- ============================================================
-- آمن: يستخدم IF NOT EXISTS و IGNORE — ما يحذف بيانات قديمة
-- شغّل هذا الملف على نفس قاعدة بيانات v0.2.0
-- ============================================================

-- ============================================================
-- (A) تعديل الجداول الموجودة
-- ============================================================

-- (A1) family_gangs: إضافة coward_until
ALTER TABLE `family_gangs`
  ADD COLUMN IF NOT EXISTS `coward_until` TIMESTAMP NULL DEFAULT NULL,
  ADD INDEX IF NOT EXISTS `idx_coward` (`coward_until`);

-- (A2) family_zones: إضافة war_locked
ALTER TABLE `family_zones`
  ADD COLUMN IF NOT EXISTS `war_locked` TINYINT(1) DEFAULT 0,
  ADD INDEX IF NOT EXISTS `idx_war_locked` (`war_locked`);

-- (A3) family_vaults: snapshot + lock
ALTER TABLE `family_vaults`
  ADD COLUMN IF NOT EXISTS `war_snapshot` BIGINT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `war_locked` TINYINT(1) DEFAULT 0;

-- (A4) family_members: war blacklist
ALTER TABLE `family_members`
  ADD COLUMN IF NOT EXISTS `war_blacklisted_until` TIMESTAMP NULL DEFAULT NULL,
  ADD INDEX IF NOT EXISTS `idx_blacklist` (`war_blacklisted_until`);

-- (A5) family_trade_points: ربط بـ zone + war disable
ALTER TABLE `family_trade_points`
  ADD COLUMN IF NOT EXISTS `zone_id` INT NULL,
  ADD COLUMN IF NOT EXISTS `created_by_gang_id` INT NULL,
  ADD COLUMN IF NOT EXISTS `war_disabled` TINYINT(1) DEFAULT 0,
  ADD INDEX IF NOT EXISTS `idx_zone` (`zone_id`),
  ADD INDEX IF NOT EXISTS `idx_war_disabled` (`war_disabled`);

-- ربط trade_points الموجودة بأقرب zone (auto-link)
-- تحديث كل نقطة بيع بأقرب zone (لو في حدوده)
UPDATE `family_trade_points` tp
LEFT JOIN (
  SELECT tp2.id AS tp_id,
    (SELECT z.id FROM `family_zones` z
     WHERE SQRT(POW(z.center_x - tp2.coords_x, 2) + POW(z.center_y - tp2.coords_y, 2)) <= z.radius
     ORDER BY SQRT(POW(z.center_x - tp2.coords_x, 2) + POW(z.center_y - tp2.coords_y, 2)) ASC
     LIMIT 1) AS matched_zone
  FROM `family_trade_points` tp2
) AS m ON m.tp_id = tp.id
SET tp.zone_id = m.matched_zone
WHERE tp.zone_id IS NULL;

-- إضافة FK لـ trade_points (بعد الربط)
-- ملاحظة: لو فيه نقاط بيع zone_id NULL ولا تنتمي لأي zone، تبقى كذا (يمكن حذفها يدوياً)
ALTER TABLE `family_trade_points`
  ADD CONSTRAINT `fk_tp_zone` FOREIGN KEY (`zone_id`)
    REFERENCES `family_zones`(`id`) ON DELETE CASCADE;

-- (A6) family_trade_logs: tax + FK
ALTER TABLE `family_trade_logs`
  ADD COLUMN IF NOT EXISTS `tax_amount` BIGINT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `tax_to_gang_id` INT NULL,
  ADD INDEX IF NOT EXISTS `idx_gang` (`tax_to_gang_id`);

-- FK مع ON DELETE SET NULL (لأن point_id قد يُحذف)
ALTER TABLE `family_trade_logs`
  ADD CONSTRAINT `fk_tl_point` FOREIGN KEY (`point_id`)
    REFERENCES `family_trade_points`(`id`) ON DELETE SET NULL;

-- ============================================================
-- (B) الجداول الجديدة — نظام الحرب
-- ============================================================
CREATE TABLE IF NOT EXISTS `family_wars` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `attacker_gang_id` INT NOT NULL,
  `defender_gang_id` INT NOT NULL,
  `zone_id` INT NOT NULL,
  `status` ENUM('preparing','active','overtime','ended','forfeited','surrendered','refunded','cancelled')
           NOT NULL DEFAULT 'preparing',
  `declared_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `starts_at` TIMESTAMP NOT NULL,
  `ends_at` TIMESTAMP NOT NULL,
  `cost_paid` BIGINT NOT NULL,
  `vault_snapshot` BIGINT DEFAULT NULL,
  `loot_percent` INT DEFAULT 30,
  `winner_gang_id` INT NULL,
  `end_reason` VARCHAR(60) NULL,
  `is_test_mode` TINYINT(1) DEFAULT 0,
  FOREIGN KEY (`attacker_gang_id`) REFERENCES `family_gangs`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`defender_gang_id`) REFERENCES `family_gangs`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`zone_id`) REFERENCES `family_zones`(`id`) ON DELETE CASCADE,
  INDEX `idx_status` (`status`),
  INDEX `idx_zone_active` (`zone_id`, `status`),
  INDEX `idx_attacker` (`attacker_gang_id`, `status`),
  INDEX `idx_defender` (`defender_gang_id`, `status`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `family_war_scores` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `war_id` INT NOT NULL,
  `gang_id` INT NOT NULL,
  `score` INT DEFAULT 0,
  `kills` INT DEFAULT 0,
  `deaths` INT DEFAULT 0,
  `presence_minutes` INT DEFAULT 0,
  FOREIGN KEY (`war_id`) REFERENCES `family_wars`(`id`) ON DELETE CASCADE,
  UNIQUE KEY `uniq_war_gang` (`war_id`, `gang_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `family_war_events` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `war_id` INT NOT NULL,
  `event_type` VARCHAR(30) NOT NULL,
  `citizenid` VARCHAR(60),
  `gang_id` INT,
  `target_citizenid` VARCHAR(60),
  `target_gang_id` INT,
  `score_delta` INT DEFAULT 0,
  `metadata` TEXT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`war_id`) REFERENCES `family_wars`(`id`) ON DELETE CASCADE,
  INDEX `idx_war_time` (`war_id`, `created_at`),
  INDEX `idx_war_type` (`war_id`, `event_type`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `family_war_participants` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `war_id` INT NOT NULL,
  `citizenid` VARCHAR(60) NOT NULL,
  `gang_id` INT NOT NULL,
  `joined_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`war_id`) REFERENCES `family_wars`(`id`) ON DELETE CASCADE,
  UNIQUE KEY `uniq_war_cid` (`war_id`, `citizenid`),
  INDEX `idx_war_gang` (`war_id`, `gang_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `family_war_history` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `war_id` INT NOT NULL,
  `attacker_label` VARCHAR(100),
  `defender_label` VARCHAR(100),
  `zone_name` VARCHAR(100),
  `winner_label` VARCHAR(100),
  `end_reason` VARCHAR(60),
  `attacker_score` INT,
  `defender_score` INT,
  `total_kills` INT,
  `loot_amount` BIGINT,
  `duration_minutes` INT,
  `ended_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_ended` (`ended_at`)
) ENGINE=InnoDB;

-- ============================================================
-- (C) إعدادات الآدمن المرنة
-- ============================================================
CREATE TABLE IF NOT EXISTS `family_admin_config` (
  `config_key` VARCHAR(60) PRIMARY KEY,
  `config_value` TEXT NOT NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

INSERT IGNORE INTO `family_admin_config` (`config_key`, `config_value`) VALUES
  ('war_cost', '100000'),
  ('war_duration_minutes', '60'),
  ('war_prep_minutes', '1440'),
  ('war_forfeit_minutes', '30'),
  ('war_overtime_minutes', '10'),
  ('war_cooldown_hours', '48'),
  ('war_min_members', '3'),
  ('war_loot_percent', '30'),
  ('war_surrender_loot_percent', '50'),
  ('war_council_coords', '{"x":0.0,"y":0.0,"z":72.0}'),
  ('coward_duration_days', '7'),
  ('coward_income_penalty', '50'),
  ('test_mode_enabled', '0'),
  ('test_mode_expires_at', '0'),
  ('score_kill', '10'),
  ('score_boss_kill', '25'),
  ('score_death', '-5'),
  ('score_presence_per_minute', '2'),
  ('vault_stash_slots', '50'),
  ('vault_stash_weight', '200000');

-- ============================================================
-- ✅ انتهت الترقية بنجاح
-- ============================================================
