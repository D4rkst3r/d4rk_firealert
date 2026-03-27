CREATE TABLE IF NOT EXISTS `fire_systems` (
    `id`     INT AUTO_INCREMENT PRIMARY KEY,
    `name`   VARCHAR(100)                            DEFAULT 'Gebäude BMA',
    `owner`  VARCHAR(50)                             DEFAULT NULL,
    `coords` LONGTEXT                                NOT NULL,
    `status` ENUM('normal', 'alarm', 'trouble')      DEFAULT 'normal'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `fire_devices` (
    `id`           INT AUTO_INCREMENT PRIMARY KEY,
    `system_id`    INT           NOT NULL,
    `type`         VARCHAR(50)   NOT NULL,
    `coords`       LONGTEXT      NOT NULL,
    `rotation`     LONGTEXT      NOT NULL,
    `zone`         VARCHAR(50)   DEFAULT 'Standard',
    `health`       INT           DEFAULT 100,
    `last_service` TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_system` FOREIGN KEY (`system_id`) REFERENCES `fire_systems`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- FIX #7: Index auf system_id für bessere Query-Performance bei vielen Geräten
CREATE INDEX IF NOT EXISTS `idx_system_id` ON `fire_devices` (`system_id`);

-- Index auf health für den Trouble-Check im Wartungs-Loop
CREATE INDEX IF NOT EXISTS `idx_health` ON `fire_devices` (`health`);
