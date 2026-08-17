local QBCore = exports['qb-core']:GetCoreObject()

-- This file contains NO trail-creation state. client/main.lua remains the
-- single source of truth for creation and active trail runs.
local Trails = {}
local ShowingLeaderboard = nil

local function notify(msg, kind, duration)
    QBCore.Functions.Notify(msg, kind or 'primary', duration or 3000)
end

local function getTrail(id)
    for _, trail in ipairs(Trails) do
        if tonumber(trail.id) == tonumber(id) then return trail end
    end
end

local function formatTime(ms)
    return ('%.3fs'):format((tonumber(ms) or 0) / 1000)
end

local function drawCenter(text, y, scale)
    SetTextFont(4)
    SetTextScale(scale or 0.34, scale or 0.34)
    SetTextProportional(1)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, y)
end

local function drawLeaderboard(trail, rows)
    local lines = {}
    for i, row in ipairs(rows or {}) do
        local vehicle = row.vehicle_name or 'Unknown Vehicle'
        local plate = row.vehicle_plate or 'N/A'
        lines[#lines + 1] = ('~y~%02d.~w~ %s  ~g~%s~w~  | %s [%s]'):format(
            i,
            row.player_name or 'Unknown',
            formatTime(row.time_ms),
            vehicle,
            plate
        )
    end

    if #lines == 0 then
        lines[1] = '~c~No completed runs yet.~w~'
    end

    ShowingLeaderboard = {
        trail = trail,
        rows = rows or {},
        lines = lines,
        expires = GetGameTimer() + 10000
    }
end

local function showLeaderboard(trail)
    if not trail then return end

    QBCore.Functions.TriggerCallback('offroad:server:getLeaderboard', function(rows)
        drawLeaderboard(trail, rows)
    end, trail.id)
end

RegisterNetEvent('offroad:client:setTrails', function(trails)
    Trails = trails or {}
end)

CreateThread(function()
    QBCore.Functions.TriggerCallback('offroad:server:getTrails', function(trails)
        Trails = trails or {}
    end)
end)

-- At every trailhead, M opens that trail's leaderboard.
CreateThread(function()
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local nearest = nil
        local nearestDistance = nil

        for _, trail in ipairs(Trails) do
            local distance = #(coords - trail.start)
            if distance <= Config.InteractionDistance and (not nearestDistance or distance < nearestDistance) then
                nearest = trail
                nearestDistance = distance
            end
        end

        if nearest and not IsPauseMenuActive() then
            wait = 0
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(('Press ~INPUT_CHARACTER_WHEEL~ to view the ~y~%s~w~ leaderboard'):format(nearest.name))
            EndTextCommandDisplayHelp(0, false, true, -1)

            -- INPUT_CHARACTER_WHEEL = M on the default GTA keyboard layout.
            if IsControlJustReleased(0, 244) then
                showLeaderboard(nearest)
            end
        end

        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        if ShowingLeaderboard then
            if GetGameTimer() >= ShowingLeaderboard.expires then
                ShowingLeaderboard = nil
                Wait(250)
            else
                Wait(0)
                local trail = ShowingLeaderboard.trail
                drawCenter(('~y~%s~w~  |  ~b~LEADERBOARD~w~'):format(trail.name), 0.16, 0.52)
                drawCenter('Rank   Driver                         Time       Vehicle [Plate]', 0.205, 0.30)

                local y = 0.245
                for i = 1, math.min(#ShowingLeaderboard.lines, 10) do
                    drawCenter(ShowingLeaderboard.lines[i], y, 0.28)
                    y = y + 0.035
                end

                drawCenter('Press ~r~M~w~ at the trailhead to refresh | Auto closes in 10 seconds', 0.79, 0.27)
            end
        else
            Wait(250)
        end
    end
end)

RegisterCommand('trailleaderboard', function()
    local coords = GetEntityCoords(PlayerPedId())
    local closest, distance
    for _, trail in ipairs(Trails) do
        local d = #(coords - trail.start)
        if not distance or d < distance then
            closest, distance = trail, d
        end
    end

    if not closest or distance > Config.InteractionDistance then
        notify('You must be at a trailhead to view its leaderboard.', 'error')
        return
    end

    showLeaderboard(closest)
end, false)
