-- ============================================================
-- esx_families v0.5.3 — جدول الصندوق المخصص
-- ============================================================
-- استبدال لـ ox_inventory stash
-- ============================================================

CREATE TABLE IF NOT EXISTS `family_stash` (
  `gang_id`   INT NOT NULL,
  `item_name` VARCHAR(64) NOT NULL,
  `count`     INT NOT NULL DEFAULT 0,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`gang_id`, `item_name`),
  KEY `idx_gang` (`gang_id`),
  CONSTRAINT `fk_family_stash_gang`
    FOREIGN KEY (`gang_id`) REFERENCES `family_gangs` (`id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
