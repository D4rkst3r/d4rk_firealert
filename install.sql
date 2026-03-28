CREATE TABLE IF NOT EXISTS `fire_systems` (
    `id`     INT AUTO_INCREMENT PRIMARY KEY,
    `name`   VARCHAR(100)                       DEFAULT 'Gebäude BMA',
    `owner`  VARCHAR(50)                        DEFAULT NULL,
    `coords` LONGTEXT                           NOT NULL,
    `status` ENUM('normal', 'alarm', 'trouble') DEFAULT 'normal'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `fire_devices` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `system_id`    INT         NOT NULL,
    `type`         VARCHAR(50) NOT NULL,
    `coords`       LONGTEXT    NOT NULL,
    `rotation`     LONGTEXT    NOT NULL,
    -- FIX #7: VARCHAR(150) statt VARCHAR(50) — verhindert stilles Abschneiden
    -- bei langen Zonennamen aus lib.inputDialog
    `zone`         VARCHAR(150) DEFAULT 'Standard',
    `health`       INT         DEFAULT 100,
    `last_service` TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_system` FOREIGN KEY (`system_id`) REFERENCES `fire_systems`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX IF NOT EXISTS `idx_system_id` ON `fire_devices` (`system_id`);
CREATE INDEX IF NOT EXISTS `idx_health`    ON `fire_devices` (`health`);

CREATE TABLE IF NOT EXISTS `fire_alarm_log` (
    `id`          INT AUTO_INCREMENT PRIMARY KEY,
    `system_id`   INT          NOT NULL,
    `system_name` VARCHAR(100) NOT NULL,
    -- FIX #7: VARCHAR(150) statt VARCHAR(50)
    `zone`        VARCHAR(150) NOT NULL,
    `trigger_type` ENUM('manual', 'automatic', 'test') DEFAULT 'manual',
    `triggered_at` TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    `acknowledged_at` TIMESTAMP NULL DEFAULT NULL,
    `acknowledged_by` VARCHAR(50) NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX IF NOT EXISTS `idx_log_system`  ON `fire_alarm_log` (`system_id`);
CREATE INDEX IF NOT EXISTS `idx_log_time`    ON `fire_alarm_log` (`triggered_at`);

-- Migration für bestehende Installationen (nur ausführen wenn Tabellen bereits existieren)
-- ALTER TABLE `fire_devices`   MODIFY COLUMN `zone` VARCHAR(150) DEFAULT 'Standard';
-- ALTER TABLE `fire_alarm_log` MODIFY COLUMN `zone` VARCHAR(150) NOT NULL;