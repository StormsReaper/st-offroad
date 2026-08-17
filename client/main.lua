local QBCore = exports['qb-core']:GetCoreObject()

-- client/main.lua is the single source of truth for trail creation and runs.
local Trails, Blips, TrailheadScenes = {}, {}, {}
local ActiveRun, CreatingTrail = nil, nil

local function notify(msg, kind, duration) QBCore.Functions.Notify(msg, kind or 'primary', duration or 3000) end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(25) end
    return HasModelLoaded(hash) and hash or nil
end

local function groundPosition(x, y, z)
    RequestCollisionAtCoord(x, y, z)
    local height = Config.Trailhead.groundSearchHeight or 100.0
    local step = Config.Trailhead.groundSearchStep or 5.0
    for probe = z + height, z - height, -step do
        local found, groundZ = GetGroundZFor_3dCoord(x, y, probe, false)
        if found then return vector3(x, y, groundZ) end
    end
    return vector3(x, y, z)
end

local function placePedOnGround(ped, x, y, z)
    local g = groundPosition(x, y, z)
    SetEntityCoordsNoOffset(ped, g.x, g.y, g.z, false, false, false)
    PlaceObjectOnGroundProperly(ped)
    FreezeEntityPosition(ped, true)
    return g
end

local function deleteScene(scene)
    if not scene then return end
    if scene.ped and DoesEntityExist(scene.ped) then DeleteEntity(scene.ped) end
    for _, ped in ipairs(scene.crowd or {}) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
end

local function createTrailheadScene(trail)
    if TrailheadScenes[trail.id] then deleteScene(TrailheadScenes[trail.id]) end
    local scene = { ped = nil, crowd = {} }
    local start = groundPosition(trail.start.x, trail.start.y, trail.start.z)

    local hash = loadModel(Config.Trailhead.pedModel)
    if hash then
        scene.ped = CreatePed(4, hash, start.x, start.y, start.z, trail.startHeading + Config.Trailhead.pedHeadingOffset, false, false)
        SetEntityAsMissionEntity(scene.ped, true, true); SetBlockingOfNonTemporaryEvents(scene.ped, true); SetEntityInvincible(scene.ped, true)
        placePedOnGround(scene.ped, start.x, start.y, start.z)
        TaskStartScenarioInPlace(scene.ped, Config.Trailhead.clipboardScenario, 0, true)
        SetModelAsNoLongerNeeded(hash)
    end

    for i, offset in ipairs(Config.Trailhead.crowdOffsets) do
        local model = Config.Trailhead.crowdModels[((i - 1) % #Config.Trailhead.crowdModels) + 1]
        local h = loadModel(model)
        if h then
            local wanted = vector3(start.x + offset.x, start.y + offset.y, start.z + offset.z)
            local g = groundPosition(wanted.x, wanted.y, wanted.z)
            local ped = CreatePed(4, h, g.x, g.y, g.z, trail.startHeading, false, false)
            SetEntityAsMissionEntity(ped, true, true); SetBlockingOfNonTemporaryEvents(ped, true); SetEntityInvincible(ped, true)
            placePedOnGround(ped, g.x, g.y, g.z)
            TaskStartScenarioInPlace(ped, Config.Trailhead.cheerScenario, 0, true)
            scene.crowd[#scene.crowd + 1] = ped
            SetModelAsNoLongerNeeded(h)
        end
    end
    TrailheadScenes[trail.id] = scene
end

local function refreshScenes()
    for _, scene in pairs(TrailheadScenes) do deleteScene(scene) end
    TrailheadScenes = {}
    for _, trail in ipairs(Trails) do createTrailheadScene(trail) end
end

local function clearBlips()
    for _, group in pairs(Blips) do
        if DoesBlipExist(group.start) then RemoveBlip(group.start) end
        if DoesBlipExist(group.finish) then RemoveBlip(group.finish) end
    end
    Blips = {}
end

local function createTrailBlips()
    clearBlips()
    for _, trail in ipairs(Trails) do
        local s = AddBlipForCoord(trail.start.x, trail.start.y, trail.start.z)
        SetBlipSprite(s, Config.StartBlip.sprite); SetBlipColour(s, Config.StartBlip.color); SetBlipScale(s, Config.StartBlip.scale); SetBlipDisplay(s, Config.StartBlip.display or 4); SetBlipAsShortRange(s, false)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentString(('Trailhead: %s'):format(trail.name)); EndTextCommandSetBlipName(s)
        local f = AddBlipForCoord(trail.finish.x, trail.finish.y, trail.finish.z)
        SetBlipSprite(f, Config.FinishBlip.sprite); SetBlipColour(f, Config.FinishBlip.color); SetBlipScale(f, Config.FinishBlip.scale); SetBlipDisplay(f, Config.FinishBlip.display or 4); SetBlipAsShortRange(f, false)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentString(('Finish: %s'):format(trail.name)); EndTextCommandSetBlipName(f)
        Blips[trail.id] = { start = s, finish = f }
    end
end

local function refreshTrails(trails)
    Trails = trails or {}; createTrailBlips(); refreshScenes()
end
RegisterNetEvent('offroad:client:setTrails', function(trails) refreshTrails(trails) end)
CreateThread(function() QBCore.Functions.TriggerCallback('offroad:server:getTrails', refreshTrails) end)

local function getTrail(id)
    id = tonumber(id)
    for _, trail in ipairs(Trails) do if tonumber(trail.id) == id then return trail end end
end

local function checkpointCount(trail)
    local count = #(trail.route or {})
    if count > 0 then
        local last = trail.route[count]
        if last and #(vector3(last.x + 0.0, last.y + 0.0, last.z + 0.0) - trail.finish) <= 2.0 then count = count - 1 end
    end
    return count
end

local function drawText3D(c, text)
    local ok,x,y = World3dToScreen2d(c.x,c.y,c.z); if not ok then return end
    SetTextScale(0.32,0.32); SetTextFont(4); SetTextProportional(1); SetTextCentre(true); SetTextOutline()
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandDisplayText(x,y)
end
local function drawCenter(text,y,scale)
    SetTextFont(4); SetTextScale(scale or .35,scale or .35); SetTextProportional(1); SetTextCentre(true); SetTextOutline()
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandDisplayText(.5,y)
end
local function formatTime(ms) return ('%.3fs'):format((tonumber(ms) or 0)/1000) end

-- Trail start/finish interaction.
CreateThread(function()
    while true do
        local wait=1000; local c=GetEntityCoords(PlayerPedId())
        for _,trail in ipairs(Trails) do
            local sd=#(c-trail.start); local fd=#(c-trail.finish)
            if sd<60.0 then
                wait=0; DrawMarker(1,trail.start.x,trail.start.y,trail.start.z-1,0,0,0,0,0,0,3,3,1,0,255,0,100,false,false,2,false,nil,nil,false)
                if sd<=Config.InteractionDistance and not ActiveRun and not CreatingTrail then
                    drawText3D(trail.start+vector3(0,0,1.7),('~g~[E]~w~ START ~y~%s'):format(trail.name))
                    if IsControlJustReleased(0,38) then TriggerServerEvent('offroad:server:requestStart',trail.id) end
                end
            end
            if fd<60.0 then
                wait=0; DrawMarker(1,trail.finish.x,trail.finish.y,trail.finish.z-1,0,0,0,0,0,0,3,3,1,255,50,50,100,false,false,2,false,nil,nil,false)
                if fd<=Config.FinishDistance and ActiveRun and ActiveRun.trailId==trail.id then
                    if ActiveRun.nextCheckpoint>ActiveRun.checkpointCount then
                        drawText3D(trail.finish+vector3(0,0,1.5),'~r~FINISH~w~\n~g~[E]~w~ Stop the clock')
                        if IsControlJustReleased(0,38) then TriggerServerEvent('offroad:server:finishRun',trail.id) end
                    else drawText3D(trail.finish+vector3(0,0,1.5),('~r~FINISH LOCKED~w~\nPass waypoint ~y~#%d~w~ first'):format(ActiveRun.nextCheckpoint)) end
                end
            end
        end
        Wait(wait)
    end
end)

RegisterNetEvent('offroad:client:startRun',function(trailId,count)
    local trail=getTrail(trailId); if not trail then return end
    ActiveRun={trailId=trailId,nextCheckpoint=1,checkpointCount=count or checkpointCount(trail),localStartedAt=GetGameTimer()}
    if ActiveRun.checkpointCount>0 then
        local p=trail.route[1]; SetNewWaypoint(p.x,p.y); notify(('GO! Pass waypoint #1 of %d.'):format(ActiveRun.checkpointCount),'success',4000)
    else SetNewWaypoint(trail.finish.x,trail.finish.y); notify('GO! Head to the finish.','success',3500) end
end)

RegisterNetEvent('offroad:client:checkpointPassed',function(index,total)
    if not ActiveRun or index~=ActiveRun.nextCheckpoint then return end
    ActiveRun.nextCheckpoint=index+1
    local trail=getTrail(ActiveRun.trailId); if not trail then return end
    if ActiveRun.nextCheckpoint<=total then
        local p=trail.route[ActiveRun.nextCheckpoint]; SetNewWaypoint(p.x,p.y)
        notify(('Waypoint #%d/%d cleared. Next: #%d.'):format(index,total,ActiveRun.nextCheckpoint),'success',1800)
    else SetNewWaypoint(trail.finish.x,trail.finish.y); notify('All waypoints cleared. Finish unlocked!','success',3500) end
end)

CreateThread(function()
    while true do
        if ActiveRun then
            Wait(0); local trail=getTrail(ActiveRun.trailId); local done=math.min(ActiveRun.nextCheckpoint-1,ActiveRun.checkpointCount)
            drawCenter(('~y~%s~w~ | %s | ~b~Checkpoint %d/%d~w~'):format(trail and trail.name or 'TRAIL',formatTime(GetGameTimer()-ActiveRun.localStartedAt),done,ActiveRun.checkpointCount),.90,.45)
        else Wait(250) end
    end
end)

CreateThread(function()
    while true do
        if ActiveRun then
            Wait(100); local trail=getTrail(ActiveRun.trailId)
            if trail and ActiveRun.nextCheckpoint<=ActiveRun.checkpointCount then
                local p=trail.route[ActiveRun.nextCheckpoint]; local c=GetEntityCoords(PlayerPedId()); local v=vector3(p.x,p.y,p.z)
                DrawMarker(1,v.x,v.y,v.z-1,0,0,0,0,0,0,2.5,2.5,1,255,200,0,130,false,false,2,false,nil,nil,false)
                if #(c-v)<=Config.WaypointPassDistance then TriggerServerEvent('offroad:server:passedCheckpoint',trail.id,ActiveRun.nextCheckpoint) end
            end
        else Wait(250) end
    end
end)

RegisterNetEvent('offroad:client:runFinished',function(trailId)
    ActiveRun=nil; notify('Trail complete!','success',2500)
end)

-- ===================== TRAIL CREATION =====================
local function clearCreationBlips()
    if not CreatingTrail then return end
    for _,b in ipairs(CreatingTrail.blips or {}) do if DoesBlipExist(b) then RemoveBlip(b) end end
    CreatingTrail.blips={}
end
local function addCreationBlip(c,sprite,color,scale,label)
    local b=AddBlipForCoord(c.x,c.y,c.z); SetBlipSprite(b,sprite); SetBlipColour(b,color); SetBlipScale(b,scale or .7); SetBlipDisplay(b,4); SetBlipAsShortRange(b,false)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(label); EndTextCommandSetBlipName(b); CreatingTrail.blips[#CreatingTrail.blips+1]=b
end
local function addCreationPoint()
    if not CreatingTrail then notify('You are not currently creating a trail.','error'); return end
    local c=GetEntityCoords(PlayerPedId()); CreatingTrail.route[#CreatingTrail.route+1]={x=c.x,y=c.y,z=c.z}
    addCreationBlip(c,1,46,.65,('Waypoint #%d'):format(#CreatingTrail.route)); notify(('Waypoint #%d saved.'):format(#CreatingTrail.route),'success',1500)
end
local function startCreation(name)
    if CreatingTrail then notify('A trail is already being created.','error'); return end
    local ped=PlayerPedId(); local c=GetEntityCoords(ped)
    CreatingTrail={name=name,start={x=c.x,y=c.y,z=c.z,heading=GetEntityHeading(ped)},route={},blips={},startedAt=GetGameTimer()}
    addCreationBlip(c,Config.StartBlip.sprite,2,1.0,('TRAIL START: %s'):format(name)); SetNewWaypoint(c.x,c.y)
    notify(('TRAIL CREATION STARTED: %s'):format(name),'success',5000); notify(('Press %s or /%s to add waypoints.'):format(Config.WaypointKey,Config.WaypointCommand),'primary',5000); notify('/finishcreatetrail = finish | /cancelcreatetrail = cancel','primary',5000)
end
local function finishCreation()
    if not CreatingTrail then notify('You are not currently creating a trail.','error'); return end
    local c=GetEntityCoords(PlayerPedId()); local data=CreatingTrail; data.finish={x=c.x,y=c.y,z=c.z}
    if #data.route==0 then notify('Add at least one waypoint before finishing the trail.','error'); return end
    notify(('Saving trail "%s"...'):format(data.name),'primary',2500); TriggerServerEvent('offroad:server:saveTrail',data); clearCreationBlips(); CreatingTrail=nil
end
local function cancelCreation()
    if not CreatingTrail then notify('You are not currently creating a trail.','error'); return end
    clearCreationBlips(); CreatingTrail=nil; notify('Trail creation cancelled.','primary',2500)
end
RegisterNetEvent('offroad:client:beginTrailCreation',function(name) startCreation(name) end)
RegisterCommand(Config.WaypointCommand,addCreationPoint,false)
RegisterKeyMapping(Config.WaypointCommand,'Save offroad trail waypoint','keyboard',Config.WaypointKey)
RegisterCommand('finishcreatetrail',finishCreation,false)
RegisterCommand('cancelcreatetrail',cancelCreation,false)

CreateThread(function()
    while true do
        if CreatingTrail then
            Wait(0); local c=GetEntityCoords(PlayerPedId()); local t=math.floor((GetGameTimer()-CreatingTrail.startedAt)/1000)
            drawCenter('~y~OFFROAD TRAIL CREATION ACTIVE~w~',.045,.48); drawCenter(('~y~%s~w~ | Waypoints: ~g~%d~w~ | Time: %02d:%02d'):format(CreatingTrail.name,#CreatingTrail.route,math.floor(t/60),t%60),.075,.33)
            drawCenter(('~b~[%s]~w~ /%s waypoint | ~g~/finishcreatetrail~w~ finish | ~r~/cancelcreatetrail~w~ cancel'):format(Config.WaypointKey,Config.WaypointCommand),.105,.27)
            DrawMarker(1,CreatingTrail.start.x,CreatingTrail.start.y,CreatingTrail.start.z-1,0,0,0,0,0,0,3,3,1,0,255,0,150,false,false,2,false,nil,nil,false)
            local prev=CreatingTrail.start
            for i,p in ipairs(CreatingTrail.route) do
                DrawMarker(1,p.x,p.y,p.z-1,0,0,0,0,0,0,1.2,1.2,.6,255,200,0,180,false,false,2,false,nil,nil,false); drawText3D(vector3(p.x,p.y,p.z+1),('~y~WP #%d'):format(i)); DrawLine(prev.x,prev.y,prev.z+.5,p.x,p.y,p.z+.5,255,200,0,220); prev=p
            end
            DrawLine(prev.x,prev.y,prev.z+.5,c.x,c.y,c.z+.5,0,200,255,220)
        else Wait(250) end
    end
end)

RegisterCommand('traillist',function()
    print('^3===== OFFROAD TRAILS =====^7'); for _,t in ipairs(Trails) do print(('[%s] %s | required waypoints: %d'):format(t.id,t.name,checkpointCount(t))) end; print('^3===========================^7')
end,false)

AddEventHandler('onResourceStop',function(resourceName)
    if resourceName~=GetCurrentResourceName() then return end
    clearBlips(); if CreatingTrail then clearCreationBlips() end
    for _,scene in pairs(TrailheadScenes) do deleteScene(scene) end
end)
