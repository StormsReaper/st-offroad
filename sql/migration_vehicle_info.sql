-- Run this once if offroad_trail_times already exists.
-- New installs should use sql/install.sql instead.

ALTER TABLE `offroad_trail_times`
    ADD COLUMN `vehicle_name` VARCHAR(100) DEFAULT NULL AFTER `time_ms`,
    ADD COLUMN `vehicle_model` VARCHAR(100) DEFAULT NULL AFTER `vehicle_name`,
    ADD COLUMN `vehicle_plate` VARCHAR(20) DEFAULT NULL AFTER `vehicle_model`;
