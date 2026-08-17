local QBCore = exports['qb-core']:GetCoreObject()

local ActiveRuns = {}
local Trails = {}

local function notify(src, msg, msgType)
    TriggerClientEvent('QBCore:Notify', src, msg, msgType or 'primary')
end

local function findTrail(id)
    id = tonumber(id)
    for _, trail in ipairs(Trails) do
        if tonumber(trail.id) == id then return trail end
    end
end

local function checkpointCount(trail)
    local route = trail.route or {}
    local count = #route
    if count > 0 then
        local last = route[count]
        if last and #(vector3(last.x + 0.0, last.y + 0.0, last.z + 0.0) - trail.finish) <= 2.0 then
            count = count - 1
        end
    end
    return count
end

local function loadTrails()
    local rows = MySQL.query.await([[
        SELECT id, name, start_x, start_y, start_z, start_heading,
               finish_x, finish_y, finish_z, route_json, created_by, created_at
        FROM offroad_trails WHERE enabled = 1 ORDER BY name ASC
    ]])

    Trails = {}
    for _, row in ipairs(rows or {}) do
        local route = {}
        if row.route_json and row.route_json ~= '' then
            local decoded = json.decode(row.route_json)
            if type(decoded) == 'table' then route = decoded end
        end
        Trails[#Trails + 1] = {
            id = row.id,
            name = row.name,
            start = vector3(row.start_x + 0.0, row.start_y + 0.0, row.start_z + 0.0),
            startHeading = row.start_heading or 0.0,
            finish = vector3(row.finish_x + 0.0, row.finish_y + 0.0, row.finish_z + 0.0),
            route = route,
            createdBy = row.created_by,
            createdAt = row.created_at
        }
    end
    TriggerClientEvent('offroad:client:setTrails', -1, Trails)
end

CreateThread(function()
    Wait(1000)
    loadTrails()
end)

QBCore.Functions.CreateCallback('offroad:server:getTrails', function(source, cb)
    cb(Trails)
end)

QBCore.Functions.CreateCallback('offroad:server:getLeaderboard', function(source, cb, trailId)
    local rows = MySQL.query.await([[
        SELECT player_name, citizenid, time_ms,
               vehicle_name, vehicle_model, vehicle_plate,
               DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS completed_at
        FROM offroad_trail_times
        WHERE trail_id = ?
        ORDER BY time_ms ASC
        LIMIT ?
    ]], { tonumber(trailId), Config.MaximumLeaderboardEntries })
    cb(rows or {})
end)

RegisterNetEvent('offroad:server:requestStart', function(trailId)
    local src = source
    local trail = findTrail(trailId)
    if not trail then notify(src, 'That trail no longer exists.', 'error') return end

    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - trail.start) > Config.StartDistance then
        notify(src, 'You are too far from the trailhead.', 'error')
        return
    end

    ActiveRuns[src] = {
        trailId = trail.id,
        startedAt = GetGameTimer(),
        nextCheckpoint = 1,
        checkpointCount = checkpointCount(trail)
    }
    TriggerClientEvent('offroad:client:startRun', src, trail.id, ActiveRuns[src].checkpointCount)
end)

RegisterNetEvent('offroad:server:passedCheckpoint', function(trailId, checkpointIndex)
    local src = source
    local run = ActiveRuns[src]
    local trail = findTrail(trailId)
    checkpointIndex = tonumber(checkpointIndex)
    if not run or not trail or run.trailId ~= trail.id then return end
    if checkpointIndex ~= run.nextCheckpoint then return end

    local routePoint = trail.route[checkpointIndex]
    if not routePoint then return end
    local point = vector3(routePoint.x + 0.0, routePoint.y + 0.0, routePoint.z + 0.0)
    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - point) > Config.WaypointPassDistance then return end

    run.nextCheckpoint = run.nextCheckpoint + 1
    TriggerClientEvent('offroad:client:checkpointPassed', src, checkpointIndex, run.checkpointCount)
end)

RegisterNetEvent('offroad:server:finishRun', function(trailId)
    local src = source
    local run = ActiveRuns[src]
    local trail = findTrail(trailId)
    if not run or not trail or run.trailId ~= trail.id then
        notify(src, 'You do not have an active run for this trail.', 'error')
        return
    end

    if run.nextCheckpoint <= run.checkpointCount then
        notify(src, ('You must pass waypoint %d of %d before finishing.'):format(run.nextCheckpoint, run.checkpointCount), 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - trail.finish) > Config.FinishDistance then
        notify(src, 'You are too far from the finish.', 'error')
        return
    end

    local elapsed = GetGameTimer() - run.startedAt
    ActiveRuns[src] = nil
    if elapsed < Config.MinimumTimeSeconds * 1000 then
        notify(src, 'Run rejected: finish time was too fast to be valid.', 'error')
        return
    end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local playerName = GetPlayerName(src) or 'Unknown'
    local charName = playerName
    if Player.PlayerData.charinfo then
        charName = (Player.PlayerData.charinfo.firstname or '') .. ' ' .. (Player.PlayerData.charinfo.lastname or '')
        charName = charName:gsub('^%s+', ''):gsub('%s+$', '')
        if charName == '' then charName = playerName end
    end

    -- Capture the exact vehicle being used when the player crosses the finish.
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        notify(src, 'You must finish the trail while inside a vehicle.', 'error')
        return
    end

    local vehicleModelHash = GetEntityModel(vehicle)
    local vehicleModel = tostring(vehicleModelHash)
    local vehicleDisplayName = GetDisplayNameFromVehicleModel(vehicleModelHash)
    local vehicleLabel = GetLabelText(vehicleDisplayName)
    if not vehicleLabel or vehicleLabel == 'NULL' then vehicleLabel = vehicleDisplayName end
    if not vehicleLabel or vehicleLabel == '' or vehicleLabel == 'CARNOTFOUND' then vehicleLabel = 'Unknown Vehicle' end
    local vehiclePlate = GetVehicleNumberPlateText(vehicle) or ''
    vehiclePlate = vehiclePlate:gsub('^%s+', ''):gsub('%s+$', '')

    local citizenid = Player.PlayerData.citizenid
    local existing = MySQL.single.await(
        'SELECT id, time_ms FROM offroad_trail_times WHERE trail_id = ? AND citizenid = ? LIMIT 1',
        { trail.id, citizenid }
    )

    if existing then
        if elapsed >= existing.time_ms then
            notify(src, ('Finished in %.3fs. Personal best: %.3fs.'):format(elapsed / 1000, existing.time_ms / 1000), 'primary')
            TriggerClientEvent('offroad:client:runFinished', src, trail.id, elapsed)
            return
        end

        MySQL.update.await([[
            UPDATE offroad_trail_times
            SET player_name = ?, time_ms = ?, vehicle_name = ?, vehicle_model = ?, vehicle_plate = ?, created_at = NOW()
            WHERE id = ?
        ]], { charName, elapsed, vehicleLabel, vehicleModel, vehiclePlate, existing.id })
        notify(src, ('NEW PERSONAL BEST: %.3f seconds!'):format(elapsed / 1000), 'success')
    else
        MySQL.insert.await([[
            INSERT INTO offroad_trail_times
                (trail_id, citizenid, player_name, time_ms, vehicle_name, vehicle_model, vehicle_plate)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], { trail.id, citizenid, charName, elapsed, vehicleLabel, vehicleModel, vehiclePlate })
        notify(src, ('Trail complete: %.3f seconds!'):format(elapsed / 1000), 'success')
    end

    TriggerClientEvent('offroad:client:runFinished', src, trail.id, elapsed)
end)

RegisterCommand('createtrailhead', function(source, args)
    if source == 0 then return end
    local name = table.concat(args, ' ')
    if name == '' then
        notify(source, 'Usage: /createtrailhead <trail name>', 'error')
        return
    end
    TriggerClientEvent('offroad:client:beginTrailCreation', source, name)
end, false)

RegisterNetEvent('offroad:server:saveTrail', function(data)
    local src = source
    if type(data) ~= 'table' or type(data.name) ~= 'string' then return end
    local start, finish = data.start, data.finish
    local route = data.route or {}
    if type(start) ~= 'table' or type(finish) ~= 'table' or type(route) ~= 'table' then
        notify(src, 'Invalid trail data.', 'error')
        return
    end

    local sx, sy, sz = tonumber(start.x), tonumber(start.y), tonumber(start.z)
    local sh = tonumber(start.heading) or 0.0
    local fx, fy, fz = tonumber(finish.x), tonumber(finish.y), tonumber(finish.z)
    if not sx or not sy or not sz or not fx or not fy or not fz then
        notify(src, 'Invalid trail coordinates.', 'error')
        return
    end

    local id = MySQL.insert.await([[
        INSERT INTO offroad_trails
            (name, start_x, start_y, start_z, start_heading,
             finish_x, finish_y, finish_z, route_json, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { data.name, sx, sy, sz, sh, fx, fy, fz, json.encode(route), GetPlayerName(src) or 'Unknown' })

    notify(src, ('Trail "%s" saved with ID %s. %d required waypoints recorded.'):format(data.name, id, #route), 'success')
    loadTrails()
end)

RegisterCommand('traildelete', function(source, args)
    if source == 0 then return end
    local trailId = tonumber(args[1])
    if not trailId then notify(source, 'Usage: /traildelete <trailId>', 'error') return end
    local affected = MySQL.update.await('UPDATE offroad_trails SET enabled = 0 WHERE id = ?', { trailId })
    if affected > 0 then
        notify(source, ('Trail %s disabled.'):format(trailId), 'success')
        loadTrails()
    else
        notify(source, 'Trail not found.', 'error')
    end
end, false)

AddEventHandler('playerDropped', function()
    ActiveRuns[source] = nil
end)
