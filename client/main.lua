local QBCore = exports['qb-core']:GetCoreObject()

local Trails = {}
local Blips = {}
local TrailheadScenes = {}
local ActiveRun = nil
local CreatingTrail = nil

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)

    if not IsModelInCdimage(hash) then
        print(('[offroad] Model not found: %s'):format(tostring(model)))
        return nil
    end

    RequestModel(hash)

    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(25)
    end

    if not HasModelLoaded(hash) then
        return nil
    end

    return hash
end

local function deleteScene(scene)
    if not scene then return end

    if scene.ped and DoesEntityExist(scene.ped) then
        DeleteEntity(scene.ped)
    end

    for _, ped in ipairs(scene.crowd or {}) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
end

local function createTrailheadScene(trail)
    if TrailheadScenes[trail.id] then
        deleteScene(TrailheadScenes[trail.id])
        TrailheadScenes[trail.id] = nil
    end

    local scene = {
        ped = nil,
        crowd = {}
    }

    local refHash = loadModel(Config.Trailhead.pedModel)

    if refHash then
        local heading = trail.startHeading + Config.Trailhead.pedHeadingOffset

        scene.ped = CreatePed(
            4,
            refHash,
            trail.start.x,
            trail.start.y,
            trail.start.z,
            heading,
            false,
            false
        )

        SetEntityAsMissionEntity(scene.ped, true, true)
        SetBlockingOfNonTemporaryEvents(scene.ped, true)
        SetEntityInvincible(scene.ped, true)
        FreezeEntityPosition(scene.ped, true)
        TaskStartScenarioInPlace(scene.ped, Config.Trailhead.clipboardScenario, 0, true)
        SetModelAsNoLongerNeeded(refHash)
    end

    for i, offset in ipairs(Config.Trailhead.crowdOffsets) do
        local modelName = Config.Trailhead.crowdModels[((i - 1) % #Config.Trailhead.crowdModels) + 1]
        local hash = loadModel(modelName)

        if hash then
            local position = trail.start + offset
            local ped = CreatePed(
                4,
                hash,
                position.x,
                position.y,
                position.z,
                trail.startHeading,
                false,
                false
            )

            SetEntityAsMissionEntity(ped, true, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)
            TaskStartScenarioInPlace(ped, Config.Trailhead.cheerScenario, 0, true)

            scene.crowd[#scene.crowd + 1] = ped
            SetModelAsNoLongerNeeded(hash)
        end
    end

    TrailheadScenes[trail.id] = scene
end

local function createAllTrailheadScenes()
    for _, scene in pairs(TrailheadScenes) do
        deleteScene(scene)
    end

    TrailheadScenes = {}

    for _, trail in ipairs(Trails) do
        createTrailheadScene(trail)
    end
end

local function clearBlips()
    for _, blip in pairs(Blips) do
        if DoesBlipExist(blip.start) then RemoveBlip(blip.start) end
        if DoesBlipExist(blip.finish) then RemoveBlip(blip.finish) end
    end

    Blips = {}
end

local function createTrailBlips()
    clearBlips()

    for _, trail in ipairs(Trails) do
        local startBlip = AddBlipForCoord(trail.start.x, trail.start.y, trail.start.z)
        SetBlipSprite(startBlip, Config.StartBlip.sprite)
        SetBlipColour(startBlip, Config.StartBlip.color)
        SetBlipScale(startBlip, Config.StartBlip.scale)
        SetBlipAsShortRange(true)

        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(('Trailhead: %s'):format(trail.name))
        EndTextCommandSetBlipName(startBlip)

        local finishBlip = AddBlipForCoord(trail.finish.x, trail.finish.y, trail.finish.z)
        SetBlipSprite(finishBlip, Config.FinishBlip.sprite)
        SetBlipColour(finishBlip, Config.FinishBlip.color)
        SetBlipScale(finishBlip, Config.FinishBlip.scale)
        SetBlipAsShortRange(true)

        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(('Finish: %s'):format(trail.name))
        EndTextCommandSetBlipName(finishBlip)

        Blips[trail.id] = {
            start = startBlip,
            finish = finishBlip
        }
    end
end

local function getTrail(trailId)
    for _, trail in ipairs(Trails) do
        if trail.id == trailId then
            return trail
        end
    end
end

local function drawText3D(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextCentre(true)
    SetTextOutline()

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function formatTime(ms)
    return ('%.3fs'):format((tonumber(ms) or 0) / 1000)
end

local function showLeaderboard(trailId, trailName)
    QBCore.Functions.TriggerCallback('offroad:server:getLeaderboard', function(rows)
        print(('^3===== OFFROAD TRAIL: %s =====^7'):format(trailName))

        if #rows == 0 then
            print('No recorded times yet.')
        else
            for i, row in ipairs(rows) do
                print(('%02d. %-25s %s'):format(i, row.player_name or 'Unknown', formatTime(row.time_ms)))
            end
        end

        print('^3================================^7')

        SendNUIMessage({
            action = 'leaderboard',
            trailName = trailName,
            rows = rows
        })
    end, trailId)
end

RegisterNetEvent('offroad:client:setTrails', function(trails)
    Trails = trails or {}
    createTrailBlips()
    createAllTrailheadScenes()
end)

CreateThread(function()
    QBCore.Functions.TriggerCallback('offroad:server:getTrails', function(trails)
        Trails = trails or {}
        createTrailBlips()
        createAllTrailheadScenes()
    end)
end)

CreateThread(function()
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        for _, trail in ipairs(Trails) do
            local startDist = #(coords - trail.start)
            local finishDist = #(coords - trail.finish)

            if startDist < 60.0 then
                wait = 0

                DrawMarker(1, trail.start.x, trail.start.y, trail.start.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    3.0, 3.0, 1.0, 0, 255, 0, 100,
                    false, false, 2, false, nil, nil, false)

                if startDist <= Config.InteractionDistance and not ActiveRun then
                    drawText3D(trail.start + vector3(0.0, 0.0, 1.7),
                        ('~g~[E]~w~ START ~y~%s~w~\n~c~/trailtimes~w~ for leaderboard'):format(trail.name))

                    if IsControlJustReleased(0, 38) then
                        SetNewWaypoint(trail.finish.x, trail.finish.y)
                        TriggerServerEvent('offroad:server:requestStart', trail.id)
                    end
                end
            end

            if finishDist < 60.0 then
                wait = 0

                DrawMarker(1, trail.finish.x, trail.finish.y, trail.finish.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    3.0, 3.0, 1.0, 255, 50, 50, 100,
                    false, false, 2, false, nil, nil, false)

                if finishDist <= Config.InteractionDistance and ActiveRun and ActiveRun.trailId == trail.id then
                    drawText3D(trail.finish + vector3(0.0, 0.0, 1.5),
                        '~r~FINISH~w~\n~g~[E]~w~ Stop the clock')

                    if IsControlJustReleased(0, 38) then
                        TriggerServerEvent('offroad:server:finishRun', trail.id)
                    end
                end
            end
        end

        Wait(wait)
    end
end)

RegisterNetEvent('offroad:client:startRun', function(trailId)
    local trail = getTrail(trailId)
    if not trail then return end

    ActiveRun = {
        trailId = trailId,
        localStartedAt = GetGameTimer()
    }

    QBCore.Functions.Notify(('GO! %s'):format(trail.name), 'success', 3000)

    CreateThread(function()
        while ActiveRun and ActiveRun.trailId == trailId do
            local elapsed = GetGameTimer() - ActiveRun.localStartedAt

            SetTextFont(4)
            SetTextScale(0.55, 0.55)
            SetTextCentre(true)
            SetTextOutline()
            SetTextColour(255, 255, 255, 230)

            BeginTextCommandDisplayText('STRING')
            AddTextComponentString(('~y~%s~w~ | %s'):format(trail.name, formatTime(elapsed)))
            EndTextCommandDisplayText(0.5, 0.90)

            Wait(0)
        end
    end)
end)

RegisterNetEvent('offroad:client:runFinished', function(trailId)
    if ActiveRun and ActiveRun.trailId == trailId then
        ActiveRun = nil
    end

    local trail = getTrail(trailId)
    if trail then
        showLeaderboard(trailId, trail.name)
    end
end)

-- =========================
-- ADMIN TRAIL CREATION
-- =========================

RegisterNetEvent('offroad:client:beginTrailCreation', function(name)
    if CreatingTrail then
        QBCore.Functions.Notify('You are already creating a trail. Use /finishcreatetrail or /cancelcreatetrail.', 'error')
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    CreatingTrail = {
        name = name,
        start = {
            x = coords.x,
            y = coords.y,
            z = coords.z,
            heading = heading
        },
        route = {},
        startedAt = GetGameTimer()
    }

    QBCore.Functions.Notify(('Trailhead created: %s'):format(name), 'success', 5000)
    QBCore.Functions.Notify(('Drive the route. Press "%s" or type /%s whenever you want to save a waypoint.'):format(Config.WaypointKey, Config.WaypointCommand), 'primary', 7000)
    QBCore.Functions.Notify('When you reach the finish, type /finishcreatetrail.', 'primary', 7000)
end)

RegisterNetEvent('offroad:client:addTrailPoint', function()
    if not CreatingTrail then
        QBCore.Functions.Notify('You are not currently creating a trail.', 'error')
        return
    end

    local coords = GetEntityCoords(PlayerPedId())

    CreatingTrail.route[#CreatingTrail.route + 1] = {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }

    QBCore.Functions.Notify(('Waypoint #%d saved.'):format(#CreatingTrail.route), 'success', 1500)
end)

RegisterNetEvent('offroad:client/finishTrailCreation', function()
    if not CreatingTrail then
        QBCore.Functions.Notify('You are not currently creating a trail.', 'error')
        return
    end

    local coords = GetEntityCoords(PlayerPedId())

    CreatingTrail.finish = {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }

    -- The finish is always the final route point.
    CreatingTrail.route[#CreatingTrail.route + 1] = {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }

    local trailData = CreatingTrail
    CreatingTrail = nil

    TriggerServerEvent('offroad:server:saveTrail', trailData)

    QBCore.Functions.Notify(('Trail finished. %d route points saved.'):format(#trailData.route), 'success', 5000)
end)

RegisterNetEvent('offroad:client/cancelTrailCreation', function()
    CreatingTrail = nil
    QBCore.Functions.Notify('Trail creation cancelled.', 'primary')
end)

-- Client-side commands/keybinds. Server-side events still perform the admin checks.
RegisterCommand(Config.WaypointCommand, function()
    TriggerServerEvent('offroad:server:requestAddTrailPoint')
end, false)

RegisterKeyMapping(Config.WaypointCommand, 'Add waypoint to current offroad trail', 'keyboard', Config.WaypointKey)

RegisterCommand('finishcreatetrail', function()
    TriggerServerEvent('offroad:server:requestFinishTrailCreation')
end, false)

RegisterCommand('cancelcreatetrail', function()
    TriggerServerEvent('offroad:server:requestCancelTrailCreation')
end, false)

CreateThread(function()
    while true do
        if CreatingTrail then
            Wait(0)

            local current = GetEntityCoords(PlayerPedId())

            DrawMarker(1,
                CreatingTrail.start.x, CreatingTrail.start.y, CreatingTrail.start.z - 1.0,
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                2.0, 2.0, 1.0, 0, 255, 0, 150,
                false, false, 2, false, nil, nil, false)

            for i, point in ipairs(CreatingTrail.route) do
                DrawMarker(1,
                    point.x, point.y, point.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    1.0, 1.0, 0.5, 255, 200, 0, 150,
                    false, false, 2, false, nil, nil, false)

                if i > 1 then
                    local previous = CreatingTrail.route[i - 1]
                    DrawLine(previous.x, previous.y, previous.z + 0.5,
                        point.x, point.y, point.z + 0.5,
                        255, 200, 0, 180)
                end
            end

            local last = CreatingTrail.route[#CreatingTrail.route]

            if last then
                DrawLine(last.x, last.y, last.z + 0.5,
                    current.x, current.y, current.z + 0.5,
                    0, 200, 255, 180)
            else
                DrawLine(CreatingTrail.start.x, CreatingTrail.start.y, CreatingTrail.start.z + 0.5,
                    current.x, current.y, current.z + 0.5,
                    0, 200, 255, 180)
            end

            drawText3D(current + vector3(0.0, 0.0, 1.3),
                ('~y~RECORDING: %s~w~\nPoints: ~g~%d~w~\nPress ~b~%s~w~ or /%s to add point\n/finishcreatetrail to finish\n/cancelcreatetrail to cancel'):format(
                    CreatingTrail.name,
                    #CreatingTrail.route,
                    Config.WaypointKey,
                    Config.WaypointCommand
                ))
        else
            Wait(500)
        end
    end
end)

RegisterCommand('trailtimes', function()
    if #Trails == 0 then
        QBCore.Functions.Notify('There are no offroad trails configured.', 'error')
        return
    end

    local coords = GetEntityCoords(PlayerPedId())
    local closest, closestDistance

    for _, trail in ipairs(Trails) do
        local distance = #(coords - trail.start)
        if not closestDistance or distance < closestDistance then
            closest = trail
            closestDistance = distance
        end
    end

    if closest then
        showLeaderboard(closest.id, closest.name)
    end
end, false)

RegisterCommand('traillist', function()
    for _, trail in ipairs(Trails) do
        print(('[Trail %s] %s | start %.2f %.2f %.2f | finish %.2f %.2f %.2f | route points: %d'):format(
            trail.id,
            trail.name,
            trail.start.x, trail.start.y, trail.start.z,
            trail.finish.x, trail.finish.y, trail.finish.z,
            #(trail.route or {})
        ))
    end

    QBCore.Functions.Notify(('Printed %s trail(s) to F8.'):format(#Trails), 'primary')
end, false)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    clearBlips()

    for _, scene in pairs(TrailheadScenes) do
        deleteScene(scene)
    end
end)
