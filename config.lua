Config = {}

Config.AdminPermissions = {
    admin = true,
    god = true
}

Config.InteractionDistance = 12.0
Config.StartDistance = 10.0
Config.FinishDistance = 12.0
Config.MinimumTimeSeconds = 5
Config.MaximumLeaderboardEntries = 25

-- Route-recording settings
Config.WaypointKey = '='
Config.WaypointCommand = 'addtrailpoint'

-- Trailhead scene
Config.Trailhead = {
    pedModel = 's_m_y_prismuscl_01',
    pedHeadingOffset = 180.0,

    crowdModels = {
        'a_f_y_beach_01',
        'a_m_y_beach_01',
        'a_f_y_tourist_01',
        'a_m_y_tourist_01',
        'a_f_y_hipster_01',
        'a_m_y_hipster_01'
    },

    crowdOffsets = {
        vector3(4.0, 2.0, 0.0),
        vector3(5.0, 1.0, 0.0),
        vector3(5.5, -0.5, 0.0),
        vector3(4.5, -2.0, 0.0),
        vector3(6.0, -3.0, 0.0)
    },

    cheerScenario = 'WORLD_HUMAN_CHEERING',
    clipboardScenario = 'WORLD_HUMAN_CLIPBOARD'
}

-- Map blips. Trailheads are always visible on the player's map/minimap.
Config.StartBlip = {
    sprite = 315,
    color = 2,
    scale = 0.90,
    display = 4,
    shortRange = false
}

Config.FinishBlip = {
    sprite = 38,
    color = 1,
    scale = 0.75,
    display = 4,
    shortRange = false
}
