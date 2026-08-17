local CreationIndicator = nil
local CreationBlip = nil
local CreationStartBlip = nil
local CreationWaypointBlips = {}

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

local function removeCreationBlips()
    if CreationBlip and DoesBlipExist(CreationBlip) then RemoveBlip(CreationBlip) end
    if CreationStartBlip and DoesBlipExist(CreationStartBlip) then RemoveBlip(CreationStartBlip) end
    for _, blip in ipairs(CreationWaypointBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    CreationBlip = nil
    CreationStartBlip = nil
    CreationWaypointBlips = {}
end

local function clearIndicator()
    CreationIndicator = nil
    removeCreationBlips()
end

local function addWaypointBlip(coords, number)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 1)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.65)
    SetBlipDisplay(blip, 4)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('Trail waypoint #%d'):format(number))
    EndTextCommandSetBlipName(blip)
    CreationWaypointBlips[#CreationWaypointBlips + 1] = blip
end

RegisterNetEvent('offroad:client:beginTrailCreation', function(name)
    clearIndicator()
    local coords = GetEntityCoords(PlayerPedId())

    CreationIndicator = {
        name = name,
        points = 0,
        startedAt = GetGameTimer(),
        start = { x = coords.x, y = coords.y, z = coords.z },
        waypoints = {}
    }

    CreationStartBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(CreationStartBlip, 315)
    SetBlipColour(CreationStartBlip, 2)
    SetBlipScale(CreationStartBlip, 1.0)
    SetBlipDisplay(CreationStartBlip, 4)
    SetBlipAsShortRange(CreationStartBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('CREATING TRAIL: %s'):format(name))
    EndTextCommandSetBlipName(CreationStartBlip)

    CreationBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(CreationBlip, 280)
    SetBlipColour(CreationBlip, 5)
    SetBlipScale(CreationBlip, 0.75)
    SetBlipDisplay(CreationBlip, 4)
    SetBlipAsShortRange(CreationBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('RECORDING: %s'):format(name))
    EndTextCommandSetBlipName(CreationBlip)

    QBCore = QBCore or exports['qb-core']:GetCoreObject()
    QBCore.Functions.Notify(('TRAIL CREATION ACTIVE: %s'):format(name), 'success', 7000)
    QBCore.Functions.Notify('Drive the route. Press = or /addtrailpoint to save waypoints. Use /finishcreatetrail at the finish.', 'primary', 9000)
end)

RegisterNetEvent('offroad:client/addTrailPoint', function()
    if not CreationIndicator then
        QBCore = QBCore or exports['qb-core']:GetCoreObject()
        QBCore.Functions.Notify('No trail is currently being created.', 'error')
        return
    end

    local coords = GetEntityCoords(PlayerPedId())
    CreationIndicator.points = CreationIndicator.points + 1
    CreationIndicator.waypoints[#CreationIndicator.waypoints + 1] = { x = coords.x, y = coords.y, z = coords.z }
    addWaypointBlip(coords, CreationIndicator.points)

    QBCore = QBCore or exports['qb-core']:GetCoreObject()
    QBCore.Functions.Notify(('WAYPOINT #%d SAVED'):format(CreationIndicator.points), 'success', 1800)
end)

RegisterNetEvent('offroad:client/finishTrailCreation', function()
    if not CreationIndicator then
        QBCore = QBCore or exports['qb-core']:GetCoreObject()
        QBCore.Functions.Notify('No trail is currently being created.', 'error')
        return
    end

    QBCore = QBCore or exports['qb-core']:GetCoreObject()
    QBCore.Functions.Notify(('TRAIL FINISHED: %s | %d waypoints + finish'):format(CreationIndicator.name, CreationIndicator.points), 'success', 6000)
    clearIndicator()
end)

RegisterNetEvent('offroad:client/cancelTrailCreation', function()
    if CreationIndicator then
        QBCore = QBCore or exports['qb-core']:GetCoreObject()
        QBCore.Functions.Notify(('Trail creation cancelled: %s'):format(CreationIndicator.name), 'primary', 4000)
    end
    clearIndicator()
end)

CreateThread(function()
    while true do
        if not CreationIndicator then
            Wait(500)
        else
            Wait(0)
            local coords = GetEntityCoords(PlayerPedId())

            if CreationBlip and DoesBlipExist(CreationBlip) then
                SetBlipCoords(CreationBlip, coords.x, coords.y, coords.z)
            end

            local elapsed = math.floor((GetGameTimer() - CreationIndicator.startedAt) / 1000)
            local minutes = math.floor(elapsed / 60)
            local seconds = elapsed % 60

            drawText(0.5, 0.040, 0.55, '~y~!! TRAIL CREATION ACTIVE !!~w~', 255, 210, 0, 255, true)
            drawText(0.5, 0.073, 0.38, ('~w~%s~w~  |  Waypoints: ~y~%d~w~  |  Time: ~b~%02d:%02d~w~'):format(CreationIndicator.name, CreationIndicator.points, minutes, seconds), 255, 255, 255, 245, true)
            drawText(0.5, 0.102, 0.30, '~g~[=]~w~ or /addtrailpoint = save waypoint     ~r~/finishcreatetrail~w~ = finish     ~r~/cancelcreatetrail~w~ = cancel', 255, 255, 255, 235, true)
            drawText(0.5, 0.905, 0.40, ('~y~RECORDING TRAIL:~w~ %s'):format(CreationIndicator.name), 255, 255, 255, 235, true)
            drawText(0.5, 0.940, 0.30, ('~g~%d WAYPOINTS SAVED~w~ | Press ~y~[=]~w~ at each turn'):format(CreationIndicator.points), 255, 255, 255, 220, true)

            DrawMarker(1, CreationIndicator.start.x, CreationIndicator.start.y, CreationIndicator.start.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.5, 2.5, 1.0, 0, 255, 0, 150, false, false, 2, false, nil, nil, false)

            for i, point in ipairs(CreationIndicator.waypoints) do
                DrawMarker(1, point.x, point.y, point.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 0.6, 255, 200, 0, 160, false, false, 2, false, nil, nil, false)
                if i == #CreationIndicator.waypoints then
                    DrawLine(point.x, point.y, point.z + 0.5, coords.x, coords.y, coords.z + 0.5, 0, 200, 255, 200)
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then removeCreationBlips() end
end)
