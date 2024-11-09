-- qb-dogfight.lua

-- Initialize the QBCore object
local QBCore = exports['qb-core']:GetCoreObject()

-- Tables to store jet information and missile tracking
local spawnedJets = {}
local isInRestrictedAirspace = false
local trackedMissiles = {}

-- Define the missile model and max distance at which jets will disengage
local missileModel = `VEHICLE_MISSILE`
local maxDistance = 1500.0 -- Distance at which jets will stop following the player

-- Function to track missiles and create blips for them
function trackMissile(missile)
    table.insert(trackedMissiles, missile)
    print("Missile tracked:", missile)

    -- Create a blip for the missile
    local missileBlip = AddBlipForEntity(missile)
    SetBlipSprite(missileBlip, 1) -- Missile icon
    SetBlipColour(missileBlip, 5) -- Green color for the missile
    SetBlipScale(missileBlip, 0.5)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Missile")
    EndTextCommandSetBlipName(missileBlip)

    -- Remove the blip when the missile is destroyed
    Citizen.CreateThread(function()
        while DoesEntityExist(missile) do
            Citizen.Wait(1000) -- Check every second if the missile exists
        end
        -- Remove the blip when the missile is destroyed
        RemoveBlip(missileBlip)
    end)
end

-- Function to upgrade the jet to its maximum capacity
function upgradeJet(jet)
    SetVehicleModKit(jet, 0)
    ToggleVehicleMod(jet, 18, true) -- Turbo
    SetVehicleMod(jet, 16, GetNumVehicleMods(jet, 16) - 1, false)
    SetVehicleMod(jet, 12, GetNumVehicleMods(jet, 12) - 1, false)
    SetVehicleMod(jet, 13, GetNumVehicleMods(jet, 13) - 1, false)
    SetVehicleMod(jet, 14, GetNumVehicleMods(jet, 14) - 1, false)
    SetVehicleMod(jet, 15, GetNumVehicleMods(jet, 15) - 1, false)
    SetVehicleTyresCanBurst(jet, false)

    -- Change the jet's color to blue
    SetVehicleColours(jet, 38, 38) -- Blue color
end

-- Function to check for all missile entities in the game world
function GetAllMissiles()
    local missiles = {}
    -- Look for vehicles that are identified as missiles
    for _, vehicle in ipairs(GetAllVehicles()) do
        if GetEntityModel(vehicle) == missileModel then
            table.insert(missiles, vehicle)
        end
    end
    return missiles
end

-- Function to retrieve all vehicles in the game
function GetAllVehicles()
    local vehicles = {}
    for vehicle in EnumerateVehicles() do
        table.insert(vehicles, vehicle)
    end
    return vehicles
end

-- Function to enumerate all vehicles in the game
function EnumerateVehicles()
    return coroutine.wrap(function()
        local handle, vehicle = FindFirstVehicle()
        local success
        repeat
            coroutine.yield(vehicle)
            success, vehicle = FindNextVehicle(handle)
        until not success
        EndFindVehicle(handle)
    end)
end

-- Function to initiate a dogfight by spawning enemy jets
function initiateDogfight()
    local player = PlayerPedId()
    local playerPos = GetEntityCoords(player)
    local jetModel = `Lazer`
    local pilotModel = `s_m_y_blackops_01`
    local spawnRadius = 1200.0

    print("Initiating dogfight - spawning enemy jets...")

    -- Alert the player about incoming jets
    TriggerEvent('chat:addMessage', { args = {"^1Alert: Enemy jets are approaching! Prepare yourself!"} })

    RequestModel(jetModel)
    RequestModel(pilotModel)
    while not HasModelLoaded(jetModel) or not HasModelLoaded(pilotModel) do
        Citizen.Wait(100)
    end

    -- Spawn 5 enemy jets in a circular formation around the player
    for i = 1, 5 do
        local angle = math.rad((i - 1) * (360 / 5))
        local spawnX = playerPos.x + math.cos(angle) * spawnRadius
        local spawnY = playerPos.y + math.sin(angle) * spawnRadius
        local spawnZ = playerPos.z + 500

        local jet = CreateVehicle(jetModel, spawnX, spawnY, spawnZ, 0.0, true, false)
        
        if DoesEntityExist(jet) then
            SetEntityAsMissionEntity(jet, true, true)
            table.insert(spawnedJets, {jet = jet, hitCount = 0})
            print("Spawned jet at", spawnX, spawnY, spawnZ)

            -- Create a blue blip for the jet
            local jetBlip = AddBlipForEntity(jet)
            SetBlipSprite(jetBlip, 16) -- Jet icon
            SetBlipColour(jetBlip, 3) -- Blue color
            SetBlipScale(jetBlip, 0.8)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString("Enemy Jet")
            EndTextCommandSetBlipName(jetBlip)
        else
            print("Failed to create jet at", spawnX, spawnY, spawnZ)
            return
        end

        local pilot = CreatePedInsideVehicle(jet, 1, pilotModel, -1, true, false)
        
        if DoesEntityExist(pilot) then
            SetEntityAsMissionEntity(pilot, true, true)
            SetPedIntoVehicle(pilot, jet, -1)
            SetPedNeverLeavesGroup(pilot, true)
            print("Pilot created successfully")
        else
            print("Failed to create pilot")
            return
        end

        -- Upgrade the jet to maximum capacity
        upgradeJet(jet)

        -- Close the landing gear and set max speed
        ControlLandingGear(jet, 3)
        SetVehicleForwardSpeed(jet, 1000.0)
        SetVehicleForceAfterburner(jet, true)

        -- Disable invincibility and restrict weapon switching
        SetEntityInvincible(jet, false) -- Remove invincibility
        SetCurrentPedWeapon(pilot, `WEAPON_VEHICLE_ROCKET`, true) -- Only rockets
        SetPedCanSwitchWeapon(pilot, false) -- Prevent switching weapons

        -- Aggressive combat behavior towards the player
        TaskCombatPed(pilot, player, 0, 16)
        SetPedCombatAttributes(pilot, 46, true)
        SetPedCombatAttributes(pilot, 5, true)
        SetPedCombatAttributes(pilot, 20, true)
        SetPedAccuracy(pilot, 100)

        Citizen.CreateThread(function()
            while DoesEntityExist(jet) and not IsPedDeadOrDying(pilot) do
                -- Ensure the jet only uses rockets for attacks
                SetCurrentPedWeapon(pilot, `WEAPON_VEHICLE_ROCKET`, true)
                TaskCombatPed(pilot, player, 0, 16)
                Citizen.Wait(2000)
            end
        end)

        Citizen.Wait(500)
    end

    SetModelAsNoLongerNeeded(jetModel)
    SetModelAsNoLongerNeeded(pilotModel)

    -- Timer to delete all jets after 80 seconds (1 minute and 20 seconds)
    Citizen.SetTimeout(70000, function()
        -- Alert the player about the 10-second warning before jets disengage
        TriggerEvent('chat:addMessage', { args = {"^1Warning: Enemy jets will disengage in 10 seconds!"} })
    end)

    Citizen.SetTimeout(80000, function()
        print("80 seconds passed. Deleting all jets.")
        TriggerEvent('chat:addMessage', { args = {"^1Enemy jets are disengaging. You are safe... for now."} })
        deleteAllJets()
    end)

    TriggerEvent('chat:addMessage', {
        args = {"^1Warning: 25 enemy jets approaching with aggression!"}
    })
end

-- Function to check if the player is within the restricted airspace
function isPlayerInRangeOfAirspace()
    local player = PlayerPedId()
    local playerPos = GetEntityCoords(player)
    local airspaceCenter = vector3(-2000.0, 3250.0, 0.0) -- Center of the restricted airspace

    local distance = #(playerPos - airspaceCenter) -- Calculate the distance

    if distance > maxDistance then
        return false
    else
        return true
    end
end

-- Function to delete all jets when the player leaves the airspace
function deleteJetsIfOutOfRange()
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(1000) -- Check every second

            if not isPlayerInRangeOfAirspace() then
                -- If the player is out of range, jets will disengage
                print("Player is out of range, jets are disengaging.")
                deleteAllJets() -- Delete all jets
                break
            end
        end
    end)
end

-- Delete all spawned jets
function deleteAllJets()
    Citizen.CreateThread(function()
        print("Attempting to delete all jets...")
        for _, data in ipairs(spawnedJets) do
            Citizen.CreateThread(function()
                while DoesEntityExist(data.jet) do
                    forceDeleteJet(data.jet)
                    Citizen.Wait(1000) -- Make sure deletion is continuous
                end
            end)
        end
        spawnedJets = {} -- Reset the list after deleting all jets
        print("All jets marked for deletion.")
    end)
end

-- Delete individual jet
function forceDeleteJet(jet)
    if DoesEntityExist(jet) then
        NetworkRequestControlOfEntity(jet)
        Citizen.Wait(10)
        SetEntityAsMissionEntity(jet, true, true)
        Citizen.Wait(10)
        SetEntityAsNoLongerNeeded(jet)
        Citizen.Wait(10)
        DeleteEntity(jet)
    end
end

-- Monitor player's position in the restricted airspace
Citizen.CreateThread(function()
    local blip = AddBlipForRadius(-2000.0, 3250.0, 0.0, 1500.0)
    SetBlipHighDetail(blip, true)
    SetBlipColour(blip, 1)
    SetBlipAlpha(blip, 128)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Restricted Airspace")
    EndTextCommandSetBlipName(blip)
    print("Restricted airspace blip created on map.")

    while true do
        Citizen.Wait(5000)
        if isPlayerInRangeOfAirspace() and not isInRestrictedAirspace then
            isInRestrictedAirspace = true
            initiateDogfight()
        elseif not isPlayerInRangeOfAirspace() and isInRestrictedAirspace then
            isInRestrictedAirspace = false
            print("Player exited restricted airspace.")
        end
    end
end)
