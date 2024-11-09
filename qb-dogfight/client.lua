local QBCore = exports['qb-core']:GetCoreObject()
local spawnedJets = {} -- רשימה לאחסון כל המטוסים והמידע שלהם
local isInRestrictedAirspace = false -- משתנה לבדיקת מצב המרחב האווירי
local trackedMissiles = {} -- רשימה לאחסון טילים שנעקבים
local missileModel = `VEHICLE_MISSILE` -- מודל הטיל, תחליף במודל הנכון במידת הצורך
local maxDistance = 20.0 -- המרחק המקסימלי שבו המטוסים יתחילו לעזוב את השחקן

-- פונקציה לעקוב אחרי טילים
function trackMissile(missile)
    table.insert(trackedMissiles, missile)
    print("Missile tracked:", missile)

    -- יצירת בליפ עבור הטיל
    local missileBlip = AddBlipForEntity(missile)
    SetBlipSprite(missileBlip, 1) -- אייקון של טיל
    SetBlipColour(missileBlip, 5) -- צבע ירוק
    SetBlipScale(missileBlip, 0.5)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Missile")
    EndTextCommandSetBlipName(missileBlip)

    -- הסרת הבליפ לאחר שהטיל מתפוצץ
    Citizen.CreateThread(function()
        while DoesEntityExist(missile) do
            Citizen.Wait(1000) -- כל שנייה בודק אם הטיל קיים
        end
        -- הסרת הבליפ לאחר שהטיל הושמד
        RemoveBlip(missileBlip)
    end)
end

-- פונקציה לשדרוג המטוס במלואו
function upgradeJet(jet)
    SetVehicleModKit(jet, 0)
    ToggleVehicleMod(jet, 18, true) -- טורבו
    SetVehicleMod(jet, 16, GetNumVehicleMods(jet, 16) - 1, false)
    SetVehicleMod(jet, 12, GetNumVehicleMods(jet, 12) - 1, false)
    SetVehicleMod(jet, 13, GetNumVehicleMods(jet, 13) - 1, false)
    SetVehicleMod(jet, 14, GetNumVehicleMods(jet, 14) - 1, false)
    SetVehicleMod(jet, 15, GetNumVehicleMods(jet, 15) - 1, false)
    SetVehicleTyresCanBurst(jet, false)

    -- שינוי צבע המטוס לכחול
    SetVehicleColours(jet, 38, 38) -- 38 הוא הצבע הכחול במערכת הצבעים של GTA V
end

-- פונקציה לחיפוש טילים במשחק
function GetAllMissiles()
    local missiles = {}
    -- חיפוש אחר כל הרכבים שמזוהים כטילים (צריך לוודא שהמודל הנכון נמצא)
    for _, vehicle in ipairs(GetAllVehicles()) do
        if GetEntityModel(vehicle) == missileModel then
            table.insert(missiles, vehicle)
        end
    end
    return missiles
end

-- פונקציה שמחזירה את כל הרכבים במשחק
function GetAllVehicles()
    local vehicles = {}
    for vehicle in EnumerateVehicles() do
        table.insert(vehicles, vehicle)
    end
    return vehicles
end

-- פונקציה לספור את הרכבים במשחק
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

-- פונקציית שיגור מטוסים, בליפים וזיהוי כניסה למרחב
function initiateDogfight()
    local player = PlayerPedId()
    local playerPos = GetEntityCoords(player)
    local jetModel = `Lazer`
    local pilotModel = `s_m_y_blackops_01`
    local spawnRadius = 1200.0

    print("Initiating dogfight - spawning enemy jets...")

    -- התראה על שיגור מטוסים
    TriggerEvent('chat:addMessage', { args = {"^1Alert: Enemy jets are approaching! Prepare yourself!"} })

    RequestModel(jetModel)
    RequestModel(pilotModel)
    while not HasModelLoaded(jetModel) or not HasModelLoaded(pilotModel) do
        Citizen.Wait(100)
    end

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

            -- שינוי צבע הבליפ של המטוס לכחול
            local jetBlip = AddBlipForEntity(jet)
            SetBlipSprite(jetBlip, 16) -- אייקון של מטוס
            SetBlipColour(jetBlip, 3) -- צבע כחול
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

        -- שדרוג המטוס למקסימום
        upgradeJet(jet)

        -- סוגר את הגלגלים ומפעיל מהירות מרבית
        ControlLandingGear(jet, 3)
        SetVehicleForwardSpeed(jet, 1000.0)
        SetVehicleForceAfterburner(jet, true)

        -- ביטול חסינות והגבלת שימוש בכלי נשק
        SetEntityInvincible(jet, false) -- הסרת חסינות
        SetCurrentPedWeapon(pilot, `WEAPON_VEHICLE_ROCKET`, true) -- טילים בלבד
        SetPedCanSwitchWeapon(pilot, false) -- מניעת החלפת נשק

        -- הפעלת תגובה אגרסיבית על השחקן
        TaskCombatPed(pilot, player, 0, 16)
        SetPedCombatAttributes(pilot, 46, true)
        SetPedCombatAttributes(pilot, 5, true)
        SetPedCombatAttributes(pilot, 20, true)
        SetPedAccuracy(pilot, 100)

        Citizen.CreateThread(function()
            while DoesEntityExist(jet) and not IsPedDeadOrDying(pilot) do
                -- ווידוא שהמטוס יתקוף רק עם טילים
                SetCurrentPedWeapon(pilot, `WEAPON_VEHICLE_ROCKET`, true)
                TaskCombatPed(pilot, player, 0, 16)
                Citizen.Wait(2000)
            end
        end)

        Citizen.Wait(500)
    end

    SetModelAsNoLongerNeeded(jetModel)
    SetModelAsNoLongerNeeded(pilotModel)

    -- טיימר למחיקת כל המטוסים לאחר 80 שניות (דקה ו-20 שניות)
    Citizen.SetTimeout(70000, function()
        -- התראה על 10 שניות אחרונות לפני מחיקה
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

-- זיהוי כניסה למרחב האווירי ושיגור מטוסים
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
        if isPlayerInPaletoAirspace() and not isInRestrictedAirspace then
            isInRestrictedAirspace = true
            initiateDogfight()
        elseif not isPlayerInPaletoAirspace() and isInRestrictedAirspace then
            isInRestrictedAirspace = false
            print("Player exited restricted airspace.")
        end
    end
end)

-- מעקב אחרי טילים
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000) -- בדוק כל שנייה

        for _, missile in ipairs(trackedMissiles) do
            if not DoesEntityExist(missile) then
                print("Missile destroyed or no longer exists:", missile)
                -- מחיקת הטיל מהרשימה אם הוא הושמד
                table.remove(trackedMissiles, _)
            end
        end
-- פונקציה לבדוק אם השחקן נמצא במרחב האווירי של פליטו ביי
function isPlayerInPaletoAirspace()
    local player = PlayerPedId()
    local playerPos = GetEntityCoords(player)

    -- טווח קואורדינטות המרחב האווירי של פליטו ביי
    local minX, maxX = -3000.0, -1000.0
    local minY, maxY = 2000.0, 4500.0
    local minZ, maxZ = 0.0, 800.0

    -- בדיקת אם השחקן נמצא בתוך המרחב האווירי
    local inAirspace = playerPos.x > minX and playerPos.x < maxX and playerPos.y > minY and playerPos.y < maxY and playerPos.z > minZ and playerPos.z < maxZ

    -- בודק אם השחקן נמצא במטוס קרב (Lazer או Hydra)
    local vehicle = GetVehiclePedIsIn(player, false)
    local isInFighterJet = (vehicle ~= 0 and (GetEntityModel(vehicle) == `Lazer` or GetEntityModel(vehicle) == `Hydra`))

    return inAirspace and isInFighterJet
end

        -- חיפוש טילים חדשים
        local missiles = GetAllMissiles() -- פונקציה שתחפש את כל הטילים
        for _, missile in ipairs(missiles) do
            if not table.contains(trackedMissiles, missile) then
                trackMissile(missile)
            end
        end
    end
end)
