# QBCore Offroad Trails v2

Point-to-point offroad trail system for FiveM/QBCore.

## Requirements

- QBCore
- oxmysql
- MySQL/MariaDB

## Installation

1. Replace your existing resource with this folder.
2. If installing fresh, import `sql/install.sql`.
3. If upgrading from v1, run the migration below.
4. Ensure the resource after QBCore and oxmysql.

```cfg
ensure oxmysql
ensure qb-core
ensure qbcore_offroad_trails
```

## Admin trail creation

Stand exactly where you want the trailhead.

Run:

```text
/createtrailhead Sandy Shores Rally
```

The position and heading of the admin become the trailhead position.

A trailhead scene is created with:
- A referee-style ped holding a clipboard.
- A small group of spectators positioned to the side.
- Spectators use a cheering scenario.

Drive the exact route you want to record.

Every time the admin presses `=`, the current vehicle/player coordinates are saved as a route waypoint.

The script also draws the saved route points and lines while you are recording.

You can also use:

```text
/addtrailpoint
```

if the keyboard binding does not recognize the `=` key on your keyboard/layout.

When you reach the desired finish:

```text
/finishcreatetrail
```

The current position becomes the finish and is also saved as the final route point.

To abandon creation:

```text
/cancelcreatetrail
```

## Running a trail

Players go to the trailhead and press `E`.

The timer starts and a waypoint is placed at the finish.

At the finish, press `E` to stop the timer.

The server validates the player is physically at the finish before recording the time.

Only each player's personal best is kept.

## Leaderboard

Use:

```text
/trailtimes
```

The nearest trail's leaderboard is printed to F8 and sent through a NUI message for a future/custom UI.

## Upgrading from v1

If you already installed the earlier version, run:

```sql
ALTER TABLE offroad_trails
    ADD COLUMN start_heading DOUBLE NOT NULL DEFAULT 0 AFTER start_z,
    ADD COLUMN route_json LONGTEXT NULL AFTER finish_z;
```

If either column already exists, omit that column from the ALTER statement.

## Notes

The recorded route is stored as JSON in `route_json`.

The current race timing system still uses the trailhead and finish positions. The saved route points are available for the next phase, where the system can enforce checkpoints and prevent shortcutting.
