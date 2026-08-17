CREATE TABLE IF NOT EXISTS `offroad_trails` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `start_x` DOUBLE NOT NULL,
    `start_y` DOUBLE NOT NULL,
    `start_z` DOUBLE NOT NULL,
    `start_heading` DOUBLE NOT NULL DEFAULT 0,
    `finish_x` DOUBLE NOT NULL,
    `finish_y` DOUBLE NOT NULL,
    `finish_z` DOUBLE NOT NULL,
    `route_json` LONGTEXT NULL,
    `created_by` VARCHAR(100) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`),
    KEY `idx_enabled` (`enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `offroad_trail_times` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `trail_id` INT NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `player_name` VARCHAR(100) NOT NULL,
    `time_ms` INT NOT NULL,
    `vehicle_name` VARCHAR(100) DEFAULT NULL,
    `vehicle_model` VARCHAR(100) DEFAULT NULL,
    `vehicle_plate` VARCHAR(20) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_trail_player` (`trail_id`, `citizenid`),
    KEY `idx_trail_time` (`trail_id`, `time_ms`),
    CONSTRAINT `fk_offroad_trail_times_trail`
        FOREIGN KEY (`trail_id`) REFERENCES `offroad_trails` (`id`)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- If offroad_trail_times already existed before vehicle tracking was added,
-- run these statements once instead of recreating the table:
-- ALTER TABLE `offroad_trail_times` ADD COLUMN `vehicle_name` VARCHAR(100) DEFAULT NULL AFTER `time_ms`;
-- ALTER TABLE `offroad_trail_times` ADD COLUMN `vehicle_model` VARCHAR(100) DEFAULT NULL AFTER `vehicle_name`;
-- ALTER TABLE `offroad_trail_times` ADD COLUMN `vehicle_plate` VARCHAR(20) DEFAULT NULL AFTER `vehicle_model`;
