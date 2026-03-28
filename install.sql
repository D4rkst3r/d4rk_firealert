-- d4rk_firealert: install.sql
-- Frische Installation: alle drei Tabellen werden angelegt.
-- Bestehende Installation: die ALTER-Statements am Ende auskommentiert ausführen.

CREATE TABLE IF NOT EXISTS `fire_systems` (
    `id`     INT AUTO_INCREMENT PRIMARY KEY,
    `name`   VARCHAR(100)                       DEFAULT 'Gebäude BMA',
    `owner`  VARCHAR(50)                        DEFAULT NULL,
    `coords` LONGTEXT                           NOT NULL,
    `status` ENUM('normal', 'alarm', 'trouble') DEFAULT 'normal'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `fire_devices` (
    `id`                INT AUTO_INCREMENT PRIMARY KEY,
    `system_id`         INT          NOT NULL,
    `type`              VARCHAR(50)  NOT NULL,
    `coords`            LONGTEXT     NOT NULL,
    `rotation`          LONGTEXT     NOT NULL,
    `zone`              VARCHAR(150) DEFAULT 'Standard',
    `health`            INT          DEFAULT 100,
    `last_service`      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    -- NEU: Datum der nächsten Pflichtinspektion (NULL = noch nie gewartet / gerade installiert)
    -- Wird beim Einbau und nach jeder Reparatur auf CURDATE() + Config.ServiceInterval gesetzt.
    `next_service_date` DATE         DEFAULT NULL,
    CONSTRAINT `fk_system` FOREIGN KEY (`system_id`) REFERENCES `fire_systems`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX IF NOT EXISTS `idx_system_id`       ON `fire_devices` (`system_id`);
CREATE INDEX IF NOT EXISTS `idx_health`          ON `fire_devices` (`health`);
CREATE INDEX IF NOT EXISTS `idx_next_service`    ON `fire_devices` (`next_service_date`);

CREATE TABLE IF NOT EXISTS `fire_alarm_log` (
    `id`               INT AUTO_INCREMENT PRIMARY KEY,
    `system_id`        INT          NOT NULL,
    `system_name`      VARCHAR(100) NOT NULL,
    `zone`             VARCHAR(150) NOT NULL,
    `trigger_type`     ENUM('manual', 'automatic', 'test') DEFAULT 'manual',
    `triggered_at`     TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    `acknowledged_at`  TIMESTAMP    NULL DEFAULT NULL,
    `acknowledged_by`  VARCHAR(50)  NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX IF NOT EXISTS `idx_log_system`  ON `fire_alarm_log` (`system_id`);
CREATE INDEX IF NOT EXISTS `idx_log_time`    ON `fire_alarm_log` (`triggered_at`);

-- NEU: Sabotage-Log — wird geschrieben wenn ein Spieler ein Gerät absichtlich beschädigt
CREATE TABLE IF NOT EXISTS `fire_sabotage_log` (
    `id`               INT AUTO_INCREMENT PRIMARY KEY,
    `device_id`        INT          NOT NULL,
    `system_id`        INT          NOT NULL,
    `system_name`      VARCHAR(100) NOT NULL,
    `zone`             VARCHAR(150) NOT NULL,
    `health_before`    INT          NOT NULL,  -- Health vor der Sabotage
    `health_after`     INT          NOT NULL,  -- Health nach der Sabotage
    `suspected_player` VARCHAR(50)  DEFAULT NULL,  -- Spielername (kein FK — Spieler könnte weg sein)
    `detected_at`      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX IF NOT EXISTS `idx_sabotage_system` ON `fire_sabotage_log` (`system_id`);
CREATE INDEX IF NOT EXISTS `idx_sabotage_time`   ON `fire_sabotage_log` (`detected_at`);

-- ─────────────────────────────────────────────────────────────────
-- MIGRATION für bestehende Installationen (auskommentiert lassen bei Neuinstall):
--
-- ALTER TABLE `fire_devices`
--     ADD COLUMN IF NOT EXISTS `next_service_date` DATE DEFAULT NULL,
--     MODIFY COLUMN `zone` VARCHAR(150) DEFAULT 'Standard';
--
-- ALTER TABLE `fire_alarm_log`
--     MODIFY COLUMN `zone` VARCHAR(150) NOT NULL;
-- ─────────────────────────────────────────────────────────────────