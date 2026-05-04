-- ============================================================
-- qbx_families - Full Install Schema v0.3.0
-- ============================================================
-- آمن للتثبيت من الصفر. لو عندك v0.2.0، استخدم upgrade_v0.2.0_to_v0.3.0.sql بدلاً منه.
-- ============================================================

-- ============================================================
-- (1) العصابات
-- ============================================================
CREATE TABLE IF NOT EXISTS `family_gangs` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(60) NOT NULL UNIQUE,
  `label` VARCHAR(100) NOT NULL,
  `leader_citizenid` VARCHAR(60) NOT NULL,
  `blip_color` INT DEFAULT 1,
  `coward_until` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_leader` (`leader_citizenid`),
  INDEX `idx_coward` (`coward_until`)
) ENGINE=InnoDB;

-- ============================================================
-- (2) الزونات
-- ============================================================
CREATE TABLE IF NOT EXISTS `family_zones` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(100) NOT NULL,
  `gang_id` INT NOT NULL,
  `center_x` FLOAT NOT NULL,
  `center_y` FLOAT NOT NULL,
  `center_z` FLOAT NOT NULL,
  `radius` FLOAT NOT NULL DEFAULT 50.0,
  `protection_percent` FLOAT NOT NULL DEFAULT 10.0,
  `war_locked` TINYINT(1) DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`gang_id`) REFERENCES `family_gangs`(`id`) ON DELETE CASCADE,
  INDEX `idx_gang` (`gang_id`),
  INDEX `idx_war_locked` (`war_locked`)
) ENGINE=InnoDB;

-- ============================================================
-- (3) الخزائن
-- ============================================================
CREATE TABLE IF NOT EXISTS `family_vaults` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `gang_id` INT NOT NULL UNIQUE,
  `coords_x` FLOAT NOT NULL,
  `coords_y` FLOAT NOT NULL,
  `coords_z` FLOAT NOT NULL,
  `money` BIGINT DEFAULT 0,
  `war_snapshot` BIGINT DEFAULT NULL,
  `war_locked` TINYINT(1) DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`gang_id`) REFERENCES `family_gangs`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `family_vault_keys` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `vault_id` INT NOT NULL,
  `citizenid` VARCHAR(60) NOT NULL,
  `granted_by` VARCHAR(60) NOT NULL,
  `granted_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`vault_id`) REFERENCES `family_vaults`(`id`) ON DELETE CASCADE,
  UNIQUE KEY `uniq_vault_citizen` (`vault_id`, `citizenid`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `family_vault_logs` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `vault_id` INT NOT NULL,
  `citizenid` VARCHAR(60),
  `action` VARCHAR(30) NOT NULL,
  `item` VARCHAR(60),
  `amount` BIGINT DEFAULT 0,
  `note` VARCHAR(255),
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`vault_id`) REFERENCES `family_vaults`(`id`) ON DELETE CASCADE,
  INDEX `idx_vault_time` (`vault_id`, `created_at`)
) ENGINE=InnoDB;

-- ============================================================
-- (4) نقاط البيع (مرتبطة بالزونات في v0.3.0)
-- ============================================================
CREATE TABLE IF NOT EXISTS `family_trade_points` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(100) NOT NULL,
  `coords_x` FLOAT NOT NULL,
  `coords_y` FLOAT NOT NULL,
  `coords_z` FLOAT NOT NULL,
  `zone_id` INT NULL,
  `created_by` VARCHAR(60),
  `created_by_gang_id` INT NULL,
  `war_disabled` TINYINT(1) DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`zone_id`) REFERENCES `family_zones`(`id`) ON DELETE CASCADE,
  INDEX `idx_zone` (`zone_id`),
  INDEX `idx_war_disabled` (`war_disabled`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `family_trade_logs` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `point_id` INT,
  `seller_cid` VARCHAR(60),
  `buyer_cid` VARCHAR(60),
  `seller_items` TEXT,
  `buyer_items` TEXT,
  `tax_amount` BIGINT DEFAULT 0,
  `tax_to_gang_id` INT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`point_id`) REFERENCES `family_trade_points`(`id`) ON DELETE SET NULL,
  INDEX `idx_time` (`created_at`),
  INDEX `idx_gang` (`tax_to_gang_id`)
) ENGINE=InnoDB;

-- ============================================================
-- (5) الرتب والأعضاء (v0.2.0)
-- ============================================================
CREATE TABLE IF NOT EXISTS `family_ranks` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `gang_id` INT NOT NULL,
  `rank_order` INT NOT NULL,
  `label` VARCHAR(60) NOT NULL,
  `tier` TINYINT NOT NULL DEFAULT 3,
  `can_open_vault`     TINYINT(1) DEFAULT 0,
  `can_withdraw`       TINYINT(1) DEFAULT 0,
  `can_deposit`        TINYINT(1) DEFAULT 1,
  `can_invite`         TINYINT(1) DEFAULT 0,
  `can_kick`           TINYINT(1) DEFAULT 0,
  `can_promote`        TINYINT(1) DEFAULT 0,
  `can_manage_zones`   TINYINT(1) DEFAULT 0,
  `daily_withdraw_limit` BIGINT DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`gang_id`) REFERENCES `family_gangs`(`id`) ON DELETE CASCADE,
  UNIQUE KEY `uniq_gang_order` (`gang_id`, `rank_order`),
  INDEX `idx_gang_tier` (`gang_id`, `tier`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `family_members` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `gang_id` INT NOT NULL,
  `citizenid` VARCHAR(60) NOT NULL UNIQUE,
  `rank_id` INT,
  `invited_by` VARCHAR(60),
  `war_blacklisted_until` TIMESTAMP NULL DEFAULT NULL,
  `joined_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`gang_id`) REFERENCES `family_gangs`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`rank_id`) REFERENCES `family_ranks`(`id`) ON DELETE SET NULL,
  INDEX `idx_gang` (`gang_id`),
  INDEX `idx_rank` (`rank_id`),
  INDEX `idx_blacklist` (`war_blacklisted_until`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `family_withdraw_tracker` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(60) NOT NULL,
  `tracker_date` DATE NOT NULL,
  `amount_withdrawn` BIGINT DEFAULT 0,
  UNIQUE KEY `uniq_cid_date` (`citizenid`, `tracker_date`),
  INDEX `idx_date` (`tracker_date`)
) ENGINE=InnoDB;

-- ============================================================
-- (6) نظام الحرب — جديد في v0.3.0
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
-- (7) إعدادات الآدمن المرنة (key-value)
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
