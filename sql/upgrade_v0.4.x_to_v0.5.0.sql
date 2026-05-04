-- ============================================================
-- esx_families - Migration v0.4.x → v0.5.0
-- يضيف نظام Recruitment Points (نقاط المبايعة الفعلية)
-- + إصلاحات على الـ indexes
-- ============================================================

-- جدول نقاط المبايعة (انضمام للعصابة)
CREATE TABLE IF NOT EXISTS `family_recruitment_points` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `gang_id` INT NOT NULL,
  `name` VARCHAR(60) NOT NULL DEFAULT 'مكتب التجنيد',
  `coords_x` FLOAT NOT NULL,
  `coords_y` FLOAT NOT NULL,
  `coords_z` FLOAT NOT NULL,
  `heading` FLOAT DEFAULT 0,
  `ped_model` VARCHAR(60) DEFAULT 's_m_y_dealer_01',
  `active` TINYINT(1) DEFAULT 1,
  `created_by` VARCHAR(60),
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_recruit_gang` (`gang_id`),
  CONSTRAINT `fk_recruit_gang` FOREIGN KEY (`gang_id`)
    REFERENCES `family_gangs` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- جدول طلبات الانضمام (pending)
CREATE TABLE IF NOT EXISTS `family_join_requests` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `gang_id` INT NOT NULL,
  `citizenid` VARCHAR(80) NOT NULL,
  `player_name` VARCHAR(80),
  `recruitment_point_id` INT,
  `status` ENUM('pending','accepted','rejected','expired') DEFAULT 'pending',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `responded_at` TIMESTAMP NULL,
  `responded_by` VARCHAR(80),
  PRIMARY KEY (`id`),
  KEY `idx_jr_gang` (`gang_id`),
  KEY `idx_jr_cid` (`citizenid`),
  KEY `idx_jr_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- إضافة عمود last_seen للأعضاء (لـ HUD online count)
ALTER TABLE `family_members`
  ADD COLUMN IF NOT EXISTS `last_seen` TIMESTAMP NULL DEFAULT NULL;
