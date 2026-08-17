local QBCore = exports['qb-core']:GetCoreObject()

-- =========================================================
-- OFFROAD CLIENT
-- client/main.lua is the SINGLE SOURCE OF TRUTH for trail
-- creation state. creation_indicator.lua is no longer used.
-- =========================================================

local Trails = {}
local Blips = {}
local TrailheadScenes = {}
local ActiveRun = nil
local CreatingTrail = nil

local function notify(message, kind, duration)
    QBCore.Functions.Notify(message, kind or 'primary', duration or 3000)
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then
        print(('[st-offroad] Model not found: %s'):format(tostring(model)))
        return nil
    end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(25) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function deleteScene(scene)
    if not scene then return end
    if scene.ped and DoesEntityExist(scene.ped) then DeleteEntity(scene.ped) end
    for _, ped in ipairs(scene.crowd or {}) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
end

local function createTrailheadScene(trail)
    if TrailheadScenes[trail.id] then deleteScene(TrailheadScenes[trail.id]) end

    local scene = { ped = nil, crowd = {} }
    local refHash = loadModel(Config.Trailhead.pedModel)

    if refHash then
        scene.ped = CreatePed(4, refHash, trail.start.x, trail.start.y, trail.start.z,
            trail.startHeading + Config.Trailhead.pedHeadingOffset, false, false)
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
            local ped = CreatePed(4, hash, position.x, position.y, position.z,
                trail.startHeading, false, false)
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
    for _, scene in pairs(TrailheadScenes) do deleteScene(scene) end
    TrailheadScenes = {}
    for _, trail in ipairs(Trails) do createTrailheadScene(trail) end
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
        SetBlipDisplay(startBlip, Config.StartBlip.display or 4)
        SetBlipAsShortRange(startBlip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(('Trailhead: %s'):format(trail.name))
        EndTextCommandSetBlipName(startBlip)

        local finishBlip = AddBlipForCoord(trail.finish.x, trail.finish.y, trail.finish.z)
        SetBlipSprite(finishBlip, Config.FinishBlip.sprite)
        SetBlipColour(finishBlip, Config.FinishBlip.color)
        SetBlipScale(finishBlip, Config.FinishBlip.scale)
        SetBlipDisplay(finishBlip, Config.FinishBlip.display or 4)
        SetBlipAsShortRange(finishBlip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(('Finish: %s'):format(trail.name))
        EndTextCommandSetBlipName(finishBlip)

        Blips[trail.id] = { start = startBlip, finish = finishBlip }
    end
end

local function getTrail(trailId)
    for _, trail in ipairs(Trails) do
        if tonumber(trail.id) == tonumber(trailId) then return trail end
    end
end

local function drawText3D(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 230)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function drawCenteredText(text, y, scale)
    SetTextFont(4)
    SetTextScale(scale or 0.38, scale or 0.38)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 235)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, y)
end

local function formatTime(ms)
    return ('%.3fs'):format((tonumber(ms) or 0) / 1000)
end

local function showLeaderboard(trailId, trailName)
    QBCore.Functions.TriggerCallback('offroad:server:getLeaderboard', function(rows)
        print(('^3===== OFFROAD TRAIL: %s =====^7'):format(trailName))
        for i, row in ipairs(rows or {}) do
            print(('%02d. %-25s %s'):format(i, row.player_name or 'Unknown', formatTime(row.time_ms)))
        end
        SendNUIMessage({ action = 'leaderboard', trailName = trailName, rows = rows or {} })
    end, trailId)
end

-- =========================================================
-- TRAIL DATA / PERMANENT MAP BLIPS
-- =========================================================

local function refreshTrails(trails)
    Trails = trails or {}
    createTrailBlips()
    createAllTrailheadScenes()
end

RegisterNetEvent('offroad:client:setTrails', function(trails)
    refreshTrails(trails)
end)

CreateThread(function()
    QBCore.Functions.TriggerCallback('offroad:server:getTrails', function(trails)
        refreshTrails(trails)
    end)
end)

-- =========================================================
-- NORMAL TRAIL RUNNING
-- =========================================================

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
                    0,0,0, 0,0,0, 3.0,3.0,1.0, 0,255,0,100, false,false,2,false,nil,nil,false)
                if startDist <= Config.InteractionDistance and not ActiveRun and not CreatingTrail then
                    drawText3D(trail.start + vector3(0,0,1.7),
                        ('~g~[E]~w~ START ~y~%s~w~'):format(trail.name))
                    if IsControlJustReleased(0, 38) then
                        SetNewWaypoint(trail.finish.x, trail.finish.y)
                        TriggerServerEvent('offroad:server:requestStart', trail.id)
                    end
                end
            end

            if finishDist < 60.0 then
                wait = 0
                DrawMarker(1, trail.finish.x, trail.finish.y, trail.finish.z - 1.0,
                    0,0,0, 0,0,0, 3.0,3.0,1.0, 255,50,50,100, false,false,2,false,nil,nil,false)
                if finishDist <= Config.InteractionDistance and ActiveRun and ActiveRun.trailId == trail.id then
                    drawText3D(trail.finish + vector3(0,0,1.5), '~r~FINISH~w~\n~g~[E]~w~ Stop the clock')
                    if IsControlJustReleased(0, 38) then TriggerServerEvent('offroad:server:finishRun', trail.id) end
                end
            end
        end
        Wait(wait)
    end
end)

RegisterNetEvent('offroad:client:startRun', function(trailId)
    local trail = getTrail(trailId)
    if not trail then return end
    ActiveRun = { trailId = trailId, localStartedAt = GetGameTimer() }
    notify(('GO! %s'):format(trail.name), 'success', 3000)
end)

CreateThread(function()
    while true do
        if ActiveRun then
            Wait(0)
            local elapsed = GetGameTimer() - ActiveRun.localStartedAt
            local trail = getTrail(ActiveRun.trailId)
            drawCenteredText(('~y~%s~w~ | %s'):format(trail and trail.name or 'TRAIL', formatTime(elapsed)), 0.90, 0.55)
        else
            Wait(250)
        end
    end
end)

RegisterNetEvent('offroad:client:runFinished', function(trailId)
    if ActiveRun and ActiveRun.trailId == trailId then ActiveRun = nil end
    local trail = getTrail(trailId)
    if trail then showLeaderboard(trailId, trail.name) end
end)

-- =========================================================
-- TRAIL CREATION - ONLY CreatingTrail IS THE STATE
-- =========================================================

local function clearCreationBlips()
    if not CreatingTrail then return end
    for _, blip in ipairs(CreatingTrail.blips or {}) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    CreatingTrail.blips = {}
end

local function addCreationBlip(coords, sprite, color, scale, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite)
    SetBlipColour(blip, color)
    SetBlipScale(blip, scale or 0.75)
    SetBlipDisplay(blip, 4)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)
    CreatingTrail.blips[#CreatingTrail.blips + 1] = blip
    return blip
end

local function addCreationPoint()
    if not CreatingTrail then
        notify('You are not currently creating a trail.', 'error')
        return
    end

    local coords = GetEntityCoords(PlayerPedId())
    local point = { x = coords.x, y = coords.y, z = coords.z }
    CreatingTrail.route[#CreatingTrail.route + 1] = point

    addCreationBlip(coords, 1, 46, 0.65, ('Waypoint #%d'):format(#CreatingTrail.route))
    notify(('Waypoint #%d saved.'):format(#CreatingTrail.route), 'success', 1500)
end

local function startTrailCreation(name)
    if CreatingTrail then
        notify('A trail is already being created. Use /finishcreatetrail or /cancelcreatetrail.', 'error', 4000)
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    CreatingTrail = {
        name = name,
        start = { x = coords.x, y = coords.y, z = coords.z, heading = GetEntityHeading(ped) },
        route = {},
        blips = {},
        startedAt = GetGameTimer()
    }

    addCreationBlip(coords, Config.StartBlip.sprite, 2, 1.0, ('TRAIL START: %s'):format(name))
    SetNewWaypoint(coords.x, coords.y)

    notify(('TRAIL CREATION STARTED: %s'):format(name), 'success', 5000)
    notify(('Press %s or /%s to save a waypoint.'):format(Config.WaypointKey, Config.WaypointCommand), 'primary', 6000)
    notify('/finishcreatetrail = finish | /cancelcreatetrail = cancel', 'primary', 6000)
end

local function finishTrailCreation()
    if not CreatingTrail then
        notify('You are not currently creating a trail.', 'error')
        return
    end

    local coords = GetEntityCoords(PlayerPedId())
    local trailData = CreatingTrail

    trailData.finish = { x = coords.x, y = coords.y, z = coords.z }
    trailData.route[#trailData.route + 1] = trailData.finish

    notify(('Saving trail "%s"...'):format(trailData.name), 'primary', 2500)
    TriggerServerEvent('offroad:server:saveTrail', trailData)

    clearCreationBlips()
    CreatingTrail = nil
end

local function cancelTrailCreation()
    if not CreatingTrail then
        notify('You are not currently creating a trail.', 'error')
        return
    end
    clearCreationBlips()
    CreatingTrail = nil
    notify('Trail creation cancelled.', 'primary', 3000)
end

RegisterNetEvent('offroad:client:beginTrailCreation', function(name)
    startTrailCreation(name)
end)

RegisterNetEvent('offroad:client:addTrailPoint', function()
    addCreationPoint()
end)

RegisterNetEvent('offroad:client:finishTrailCreation', function()
    finishTrailCreation()
end)

RegisterNetEvent('offroad:client:cancelTrailCreation', function()
    cancelTrailCreation()
end)

-- Commands now execute locally. No duplicate creation state or duplicate
-- command/event chain is involved.
RegisterCommand(Config.WaypointCommand, function()
    addCreationPoint()
end, false)

RegisterKeyMapping(Config.WaypointCommand, 'Save offroad trail waypoint', 'keyboard', Config.WaypointKey)

RegisterCommand('finishcreatetrail', function()
    finishTrailCreation()
end, false)

RegisterCommand('cancelcreatetrail', function()
    cancelTrailCreation()
end, false)

-- =========================================================
-- CREATION HUD / WORLD VISUALIZATION
-- =========================================================

CreateThread(function()
    while true do
        if CreatingTrail then
            Wait(0)
            local current = GetEntityCoords(PlayerPedId())
            local elapsed = GetGameTimer() - CreatingTrail.startedAt
            local totalSeconds = math.floor(elapsed / 1000)
            local minutes = math.floor(totalSeconds / 60)
            local seconds = totalSeconds % 60

            SetTextFont(4)
            SetTextScale(0.48, 0.48)
            SetTextProportional(1)
            SetTextColour(255, 220, 60, 245)
            SetTextCentre(true)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentString('~y~OFFROAD TRAIL CREATION ACTIVE~w~')
            EndTextCommandDisplayText(0.5, 0.045)

            drawCenteredText(('~y~%s~w~ | Waypoints: ~g~%d~w~ | Time: ~c~%02d:%02d~w~'):format(
                CreatingTrail.name, #CreatingTrail.route, minutes, seconds), 0.075, 0.34)

            drawCenteredText(('~b~[%s]~w~ /%s: waypoint   |   ~g~/finishcreatetrail~w~: finish   |   ~r~/cancelcreatetrail~w~: cancel'):format(
                Config.WaypointKey, Config.WaypointCommand), 0.105, 0.28)

            DrawMarker(1, CreatingTrail.start.x, CreatingTrail.start.y, CreatingTrail.start.z - 1.0,
                0,0,0, 0,0,0, 3.0,3.0,1.0, 0,255,0,150, false,false,2,false,nil,nil,false)

            for i, point in ipairs(CreatingTrail.route) do
                DrawMarker(1, point.x, point.y, point.z - 1.0,
                    0,0,0, 0,0,0, 1.2,1.2,0.6, 255,200,0,180, false,false,2,false,nil,nil,false)
                drawText3D(vector3(point.x, point.y, point.z + 1.0), ('~y~WP #%d'):format(i))

                if i > 1 then
                    local previous = CreatingTrail.route[i - 1]
                    DrawLine(previous.x, previous.y, previous.z + 0.5,
                        point.x, point.y, point.z + 0.5, 255,200,0,220)
                end
            end

            local last = CreatingTrail.route[#CreatingTrail.route]
            local from = last or CreatingTrail.start
            DrawLine(from.x, from.y, from.z + 0.5,
                current.x, current.y, current.z + 0.5, 0,200,255,220)

            drawText3D(current + vector3(0,0,1.4),
                ('~y~RECORDING: %s~w~\nWaypoints: ~g~%d~w~'):format(CreatingTrail.name, #CreatingTrail.route))
        else
            Wait(250)
        end
    end
end)

-- =========================================================
-- MISC
-- =========================================================

RegisterCommand('trailtimes', function()
    if #Trails == 0 then
        notify('There are no offroad trails configured.', 'error')
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
    if closest then showLeaderboard(closest.id, closest.name) end
end, false)

RegisterCommand('traillist', function()
    print('^3===== OFFROAD TRAILS =====^7')
    for _, trail in ipairs(Trails) do
        print(('[%s] %s | Start %.2f %.2f %.2f | Finish %.2f %.2f %.2f | Points %d'):format(
            trail.id, trail.name,
            trail.start.x, trail.start.y, trail.start.z,
            trail.finish.x, trail.finish.y, trail.finish.z,
            #(trail.route or {})))
    end
    print('^3===========================^7')
    notify(('Printed %d trail(s) to F8.'):format(#Trails), 'primary')
end, false)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    clearBlips()
    if CreatingTrail then clearCreationBlips() end
    for _, scene in pairs(TrailheadScenes) do deleteScene(scene) end
end)
