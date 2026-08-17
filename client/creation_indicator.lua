local CreationIndicator = nil

local function drawText(x, y, scale, text, r, g, b, a, center)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(r or 255, g or 255, b or 255, a or 255)
    SetTextCentre(center == true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function clearIndicator()
    CreationIndicator = nil
end

RegisterNetEvent('offroad:client:beginTrailCreation', function(name)
    CreationIndicator = {
        name = name,
        points = 0,
        startedAt = GetGameTimer()
    }
end)

RegisterNetEvent('offroad:client:addTrailPoint', function()
    if not CreationIndicator then return end
    CreationIndicator.points = CreationIndicator.points + 1
end)

RegisterNetEvent('offroad:client:finishTrailCreation', function()
    if CreationIndicator then
        QBCore = QBCore or exports['qb-core']:GetCoreObject()
        QBCore.Functions.Notify(
            ('Trail creation finished: %s (%d waypoints + finish)'):format(
                CreationIndicator.name,
                CreationIndicator.points
            ),
            'success',
            5000
        )
    end
    clearIndicator()
end)

RegisterNetEvent('offroad:client:cancelTrailCreation', function()
    clearIndicator()
end)

CreateThread(function()
    while true do
        if not CreationIndicator then
            Wait(500)
        else
            Wait(0)

            local elapsed = math.floor((GetGameTimer() - CreationIndicator.startedAt) / 1000)
            local minutes = math.floor(elapsed / 60)
            local seconds = elapsed % 60

            -- Persistent status bar at the top of the screen.
            drawText(
                0.5, 0.045, 0.48,
                '~y~TRAIL CREATION ACTIVE~w~',
                255, 210, 0, 255, true
            )

            drawText(
                0.5, 0.073, 0.36,
                ('~w~%s~w~  |  Waypoints: ~y~%d~w~  |  Time: ~b~%02d:%02d~w~'):format(
                    CreationIndicator.name,
                    CreationIndicator.points,
                    minutes,
                    seconds
                ),
                255, 255, 255, 245, true
            )

            drawText(
                0.5, 0.101, 0.30,
                ('~g~[%s]~w~ /%s = save waypoint     ~r~/finishcreatetrail~w~ = finish     ~r~/cancelcreatetrail~w~ = cancel'):format(
                    Config.WaypointKey,
                    Config.WaypointCommand
                ),
                255, 255, 255, 235, true
            )

            -- Large center notification whenever the admin is actively recording.
            drawText(
                0.5, 0.91, 0.34,
                ('~y~RECORDING TRAIL:~w~ %s'):format(CreationIndicator.name),
                255, 255, 255, 230, true
            )

            drawText(
                0.5, 0.94, 0.28,
                ('~g~%d WAYPOINTS SAVED~w~ | Keep driving and press ~y~%s~w~ at turns'):format(
                    CreationIndicator.points,
                    Config.WaypointKey
                ),
                255, 255, 255, 220, true
            )
        end
    end
end)
