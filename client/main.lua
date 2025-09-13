local QBCore = exports['qb-core']:GetCoreObject()

local TaxiSystem = {
    isWorking = false,
    isInTaxiVehicle = false,
    currentVehicle = nil,
    currentPassenger = nil,
    currentDestination = nil,
    totalEarnings = 0,
    totalTrips = 0,
    startPosition = nil,
    cameraHandle = nil,
    isInCinematic = false,
    destinationBlip = nil,
    routeSet = false
}

local NPCManager = {
    activeNPCs = {},
    spawnedNPCs = 0
}

function TaxiSystem:Init()
    self:CreateThreads()
    self:RegisterEvents()
end

function TaxiSystem:CreateThreads()
    CreateThread(function()
        while true do
            local sleep = 1000
            local playerPed = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(playerPed, false)

            if vehicle ~= 0 then
                local model = GetEntityModel(vehicle)
                local isDriver = GetPedInVehicleSeat(vehicle, -1) == playerPed
                local isTaxiVehicle = self:IsTaxiVehicle(model)

                if isTaxiVehicle and isDriver then
                    if not self.isInTaxiVehicle then
                        self:EnterTaxiVehicle(vehicle)
                    end
                    self.currentVehicle = vehicle
                    sleep = 0
                else
                    if self.isInTaxiVehicle then
                        self:ExitTaxiVehicle()
                    end
                end
            else
                if self.isInTaxiVehicle then
                    self:ExitTaxiVehicle()
                end
            end

            Wait(sleep)
        end
    end)

    CreateThread(function()
        while true do
            local sleep = 0

            if self.isInTaxiVehicle and not self.isInCinematic then
                if IsControlJustPressed(0, Config.StartKey) then
                    if self:CanStartWorking() then
                        if not self.isWorking then
                            self:StartWorking()
                        else
                            self:StopWorking()
                        end
                    end
                end
            else
                sleep = 1000
            end

            Wait(sleep)
        end
    end)

    CreateThread(function()
        while true do
            local sleep = 2000

            if self.isWorking and not self.currentPassenger then
                if NPCManager.spawnedNPCs >= Config.NPCSettings.maxActiveNPCs then
                    sleep = 5000
                else
                    local playerPed = PlayerPedId()
                    local playerCoords = GetEntityCoords(playerPed)
                    local vehicle = GetVehiclePedIsIn(playerPed, false)

                    if vehicle ~= 0 and self:IsTaxiVehicle(GetEntityModel(vehicle)) then
                        local availableSeats = self:GetAvailableSeats(vehicle)
                        if #availableSeats > 0 then
                            NPCManager:SpawnNearbyPassenger(playerCoords, availableSeats[1])
                        end
                    end
                end
            else
                sleep = 5000
            end

            Wait(sleep)
        end
    end)

    CreateThread(function()
        while true do
            local sleep = 500

            if self.currentPassenger and self.currentDestination then
                local vehicleCoords = GetEntityCoords(self.currentVehicle)
                local destCoords = self.currentDestination.coords
                local distance = #(vehicleCoords - destCoords)

                if distance < 15.0 then
                    local vehicleSpeed = GetEntitySpeed(self.currentVehicle) * 3.6

                    if vehicleSpeed < 5.0 and distance < 10.0 then
                        self:CompleteTrip()
                        sleep = 1000
                    else
                        self:UpdateTripProgress()
                    end
                else
                    self:UpdateTripProgress()
                end
            end

            Wait(sleep)
        end
    end)
end

function TaxiSystem:RegisterEvents()
    RegisterNetEvent('taxi:client:paymentReceived', function(amount)
        self.totalEarnings = self.totalEarnings + amount
        self:UpdateUI()
        QBCore.Functions.Notify('Trip completed! Earned: $' .. amount, 'success')
    end)
end

function TaxiSystem:IsTaxiVehicle(model)
    for _, vehicleModel in ipairs(Config.TaxiVehicles) do
        if model == GetHashKey(vehicleModel) then
            return true
        end
    end
    return false
end

function TaxiSystem:CanStartWorking()
    local vehicle = self.currentVehicle
    if not vehicle then return false end

    local passengers = 0
    for i = 0, 3 do
        if i ~= -1 then
            local ped = GetPedInVehicleSeat(vehicle, i)
            if ped and ped ~= 0 then
                passengers = passengers + 1
            end
        end
    end

    return passengers == 0
end

function TaxiSystem:GetAvailableSeats(vehicle)
    local availableSeats = {}
    local seatPositions = {
        {seat = 0, side = 'right'},
        {seat = 1, side = 'left'},
        {seat = 2, side = 'right'}
    }

    for _, seatData in ipairs(seatPositions) do
        local ped = GetPedInVehicleSeat(vehicle, seatData.seat)
        if not ped or ped == 0 then
            table.insert(availableSeats, seatData)
        end
    end

    return availableSeats
end

function TaxiSystem:EnterTaxiVehicle(vehicle)
    self.isInTaxiVehicle = true
    self.currentVehicle = vehicle

    SendNUIMessage({
        action = 'showTaxiInfo',
        show = true
    })

    self:UpdateUI()
end

function TaxiSystem:ExitTaxiVehicle()
    self.isInTaxiVehicle = false
    self.currentVehicle = nil

    if self.isWorking then
        self:StopWorking()
    end

    SendNUIMessage({
        action = 'showTaxiInfo',
        show = false
    })

    SendNUIMessage({
        action = 'showPassenger',
        show = false
    })
end

function TaxiSystem:StartWorking()
    self.isWorking = true
    SetWaypointOff()

    SendNUIMessage({
        action = 'updateStatus',
        working = true
    })

    QBCore.Functions.Notify('Started taxi service', 'success')
end

function TaxiSystem:StopWorking()
    self.isWorking = false

    if self.currentPassenger then
        self:RemoveCurrentPassenger()
    end

    self:ClearDestinationRoute()
    NPCManager:CleanupAllNPCs()

    SetWaypointOff()

    SendNUIMessage({
        action = 'updateStatus',
        working = false
    })

    SendNUIMessage({
        action = 'showPassenger',
        show = false
    })

    QBCore.Functions.Notify('Stopped taxi service', 'error')
end

function TaxiSystem:UpdateUI()
    SendNUIMessage({
        action = 'updateStats',
        earnings = self.totalEarnings,
        trips = self.totalTrips
    })
end

function TaxiSystem:PickupPassenger(npcData, seatData)

    if not self.isWorking then
        return
    end

    if self.currentPassenger then
        return
    end

    self.currentPassenger = npcData
    self.currentDestination = npcData.destination
    self.startPosition = GetEntityCoords(self.currentVehicle)

    local distance = math.floor(#(self.startPosition - npcData.destination.coords) / 10) / 100
    local estimatedFare = Config.Payment.basePrice + (distance * Config.Payment.pricePerKm)

    if Config.Cinematic.enabled then
        self:StartCinematicBoarding(npcData, seatData, distance, estimatedFare)
    else
        self:BoardPassengerDirectly(npcData, seatData, distance, estimatedFare)
    end
end

function TaxiSystem:StartCinematicBoarding(npcData, seatData, distance, estimatedFare)
    self.isInCinematic = true

    local vehicle = self.currentVehicle
    local vehicleCoords = GetEntityCoords(vehicle)
    local vehicleHeading = GetEntityHeading(vehicle)
    local npcCoords = GetEntityCoords(npcData.ped)

    local doorIndex = self:GetDoorIndex(seatData.seat, seatData.side)
    SetVehicleDoorOpen(vehicle, doorIndex, false, false)

    local offsetX = seatData.side == 'right' and 2.2 or -2.2
    local sideCoords = GetOffsetFromEntityInWorldCoords(vehicle, offsetX, -0.5, 0.0)

    TaskGoStraightToCoord(npcData.ped, sideCoords.x, sideCoords.y, sideCoords.z, 1.2, -1, vehicleHeading, 0.5)
    SetPedDesiredHeading(npcData.ped, vehicleHeading + (seatData.side == 'right' and 90.0 or -90.0))

    local midPoint = vector3(
        (npcCoords.x + vehicleCoords.x) / 2,
        (npcCoords.y + vehicleCoords.y) / 2,
        math.max(npcCoords.z, vehicleCoords.z) + Config.Cinematic.cameraHeight
    )

    local cameraAngle = vehicleHeading + (seatData.side == 'right' and 45.0 or -45.0)
    local cameraOffset = vector3(
        midPoint.x + math.cos(math.rad(cameraAngle)) * Config.Cinematic.cameraDistance,
        midPoint.y + math.sin(math.rad(cameraAngle)) * Config.Cinematic.cameraDistance,
        midPoint.z
    )

    self.cameraHandle = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(self.cameraHandle, cameraOffset.x, cameraOffset.y, cameraOffset.z)

    if Config.Cinematic.focusOnNPC then
        PointCamAtEntity(self.cameraHandle, npcData.ped, 0.0, 0.0, 0.0, true)
    else
        SetCamRot(self.cameraHandle, Config.Cinematic.cameraRotation.x, Config.Cinematic.cameraRotation.y, cameraAngle, 2)
    end

    SetCamFov(self.cameraHandle, 50.0)
    SetCamActive(self.cameraHandle, true)
    RenderScriptCams(true, Config.Cinematic.smoothTransition, 1500, true, false)

    CreateThread(function()
        Wait(Config.Cinematic.approachDuration)

        local approachTimeout = 0
        while approachTimeout < 50 do
            local currentNpcCoords = GetEntityCoords(npcData.ped)
            if #(currentNpcCoords - sideCoords) < 2.0 then
                break
            end
            approachTimeout = approachTimeout + 1
            Wait(100)
        end

        ClearPedTasks(npcData.ped)

        if Config.Cinematic.focusOnNPC then
            local doorCoords = GetOffsetFromEntityInWorldCoords(vehicle, offsetX * 0.8, 0.0, 0.5)
            local newCameraPos = vector3(
                doorCoords.x + math.cos(math.rad(cameraAngle + 180)) * 3.0,
                doorCoords.y + math.sin(math.rad(cameraAngle + 180)) * 3.0,
                doorCoords.z + 1.5
            )

            SetCamCoord(self.cameraHandle, newCameraPos.x, newCameraPos.y, newCameraPos.z)
            PointCamAtCoord(self.cameraHandle, doorCoords.x, doorCoords.y, doorCoords.z)
        end

        TaskEnterVehicle(npcData.ped, vehicle, -1, seatData.seat, 1.5, 1, 0)

        Wait(Config.Cinematic.boardingDuration - Config.Cinematic.approachDuration)

        SetVehicleDoorShut(vehicle, doorIndex, false)

        RenderScriptCams(false, Config.Cinematic.smoothTransition, 2000, true, false)

        Wait(2000)

        if self.cameraHandle then
            DestroyCam(self.cameraHandle, false)
            self.cameraHandle = nil
        end

        self.isInCinematic = false
        self:ShowPassengerInfo(npcData, distance, estimatedFare)
        self:SetDestinationRoute(npcData.destination)
    end)
end

function TaxiSystem:BoardPassengerDirectly(npcData, seatData, distance, estimatedFare)
    TaskEnterVehicle(npcData.ped, self.currentVehicle, -1, seatData.seat, 1.0, 1, 0)
    self:ShowPassengerInfo(npcData, distance, estimatedFare)

    CreateThread(function()
        Wait(3000)
        self:SetDestinationRoute(npcData.destination)
    end)
end

function TaxiSystem:GetDoorIndex(seat, side)

    local doorIndex
    if seat == 0 then
        doorIndex = 1
    elseif seat == 1 then
        doorIndex = 2
    elseif seat == 2 then
        doorIndex = 3
    else
        doorIndex = 1
    end

    return doorIndex
end

function TaxiSystem:SetDestinationRoute(destination)
    if self.destinationBlip then
        RemoveBlip(self.destinationBlip)
    end

    self.destinationBlip = AddBlipForCoord(destination.coords.x, destination.coords.y, destination.coords.z)
    SetBlipSprite(self.destinationBlip, 1)
    SetBlipColour(self.destinationBlip, 5)
    SetBlipScale(self.destinationBlip, 1.2)
    SetBlipAsShortRange(self.destinationBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Taxi Destination: " .. destination.name)
    EndTextCommandSetBlipName(self.destinationBlip)

    SetNewWaypoint(destination.coords.x, destination.coords.y)
    self.routeSet = true

    QBCore.Functions.Notify('GPS route set to ' .. destination.name, 'success', 3000)
end

function TaxiSystem:ClearDestinationRoute()
    if self.destinationBlip then
        RemoveBlip(self.destinationBlip)
        self.destinationBlip = nil
    end
    self.routeSet = false
end

function TaxiSystem:ShowPassengerInfo(npcData, distance, estimatedFare)
    SendNUIMessage({
        action = 'showPassenger',
        show = true,
        passenger = {
            name = npcData.name,
            destination = npcData.destination.name,
            distance = string.format("%.1f", distance),
            fare = math.floor(estimatedFare)
        }
    })
end

function TaxiSystem:UpdateTripProgress()
    if not self.currentDestination or not self.startPosition then return end

    local vehicleCoords = GetEntityCoords(self.currentVehicle)
    local totalDistance = #(self.startPosition - self.currentDestination.coords)
    local remainingDistance = #(vehicleCoords - self.currentDestination.coords)
    local progress = 1 - (remainingDistance / totalDistance)

    progress = math.max(0, math.min(1, progress))

    local distanceKm = remainingDistance / 1000
    local currentFare = Config.Payment.basePrice + ((totalDistance - remainingDistance) / 1000 * Config.Payment.pricePerKm)

    SendNUIMessage({
        action = 'updateTrip',
        progress = progress,
        distance = string.format("%.1f", distanceKm),
        fare = math.floor(currentFare)
    })
end

function TaxiSystem:CompleteTrip()
    if not self.currentPassenger or not self.currentDestination then return end

    local totalDistance = #(self.startPosition - self.currentDestination.coords) / 1000
    local finalFare = Config.Payment.basePrice + (totalDistance * Config.Payment.pricePerKm)

    self:ClearDestinationRoute()

    local vehicle = self.currentVehicle
    local passenger = self.currentPassenger.ped
    local passengerSeat = nil

    for i = 0, 3 do
        if GetPedInVehicleSeat(vehicle, i) == passenger then
            passengerSeat = i
            break
        end
    end

    if passengerSeat then
        local doorIndex
        if passengerSeat == 0 then
            doorIndex = 1
        elseif passengerSeat == 1 then
            doorIndex = 2
        elseif passengerSeat == 2 then
            doorIndex = 3
        else
            doorIndex = 1
        end

        SetVehicleDoorOpen(vehicle, doorIndex, false, false)
        TaskLeaveVehicle(passenger, vehicle, 0)

        CreateThread(function()
            Wait(2000)
            SetVehicleDoorShut(vehicle, doorIndex, false)

            Wait(2000)
            if DoesEntityExist(passenger) then
                local exitCoords = GetEntityCoords(passenger)
                TaskWanderStandard(passenger, 10.0, 10)

                Wait(5000)
                NPCManager:RemoveNPC(passenger)
            end
        end)
    end

    TriggerServerEvent('taxi:server:completeTrip', math.floor(finalFare))

    self.totalTrips = self.totalTrips + 1

    QBCore.Functions.Notify('Trip completed! Passenger paid $' .. math.floor(finalFare), 'success', 4000)

    SendNUIMessage({
        action = 'showPassenger',
        show = false
    })

    self.currentPassenger = nil
    self.currentDestination = nil
    self.startPosition = nil
end

function TaxiSystem:RemoveCurrentPassenger()
    if self.currentPassenger then
        self:ClearDestinationRoute()
        NPCManager:RemoveNPC(self.currentPassenger.ped)
        self.currentPassenger = nil
        self.currentDestination = nil
        self.startPosition = nil
    end
end

function NPCManager:SpawnNearbyPassenger(playerCoords, seatData)
    if self.spawnedNPCs >= Config.NPCSettings.maxActiveNPCs then
        return false
    end

    if math.random() > Config.NPCSettings.spawnChance then
        return false
    end

    local spawnCoords = self:GetRandomSpawnPoint(playerCoords)
    if not spawnCoords then
        return false
    end

    local modelHash = GetHashKey(Config.NPCModels[math.random(#Config.NPCModels)])

    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 50 do
        timeout = timeout + 1
        Wait(100)
    end

    if not HasModelLoaded(modelHash) then
        return false
    end

    local ped = CreatePed(4, modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, math.random(0, 360), false, true)

    if not DoesEntityExist(ped) then
        SetModelAsNoLongerNeeded(modelHash)
        return false
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetPedRandomComponentVariation(ped, false)
    SetPedRandomProps(ped)

    local destination = Config.Destinations[math.random(#Config.Destinations)]
    local names = Config.Names

    TaskStartScenarioInPlace(ped, "WORLD_HUMAN_HAILING_TAXI", 0, true)

    local npcData = {
        ped = ped,
        name = names[math.random(#names)],
        destination = destination,
        coords = spawnCoords
    }

    table.insert(self.activeNPCs, npcData)
    self.spawnedNPCs = self.spawnedNPCs + 1

    self:CreateNPCInteraction(npcData, seatData)

    SetModelAsNoLongerNeeded(modelHash)
    return true
end

function NPCManager:GetRandomSpawnPoint(playerCoords)
    local bestSpawnArea = self:FindBestSpawnArea(playerCoords)

    local attempts = 0
    while attempts < 15 do
        local spawnCoords

        if bestSpawnArea and math.random() < bestSpawnArea.weight then
            local angle = math.random() * 2 * math.pi
            local distance = math.random(10, bestSpawnArea.radius * 0.8)
            spawnCoords = vector3(
                bestSpawnArea.coords.x + math.cos(angle) * distance,
                bestSpawnArea.coords.y + math.sin(angle) * distance,
                bestSpawnArea.coords.z
            )
        else
            local angle = math.random() * 2 * math.pi
            local distance = math.random(Config.NPCSettings.minDistanceFromPlayer, Config.NPCSettings.maxDistanceFromPlayer)
            spawnCoords = vector3(
                playerCoords.x + math.cos(angle) * distance,
                playerCoords.y + math.sin(angle) * distance,
                playerCoords.z
            )
        end

        local sidewalkCoords = self:FindNearestSidewalk(spawnCoords)
        if sidewalkCoords then
            if not self:IsNearTraffic(sidewalkCoords) then
                if self:IsValidSpawnLocation(sidewalkCoords, playerCoords) then
                    return sidewalkCoords
                end
            end
        end
        attempts = attempts + 1
    end

    local angle = math.random() * 2 * math.pi
    local distance = 30.0
    local fallbackCoords = vector3(
        playerCoords.x + math.cos(angle) * distance,
        playerCoords.y + math.sin(angle) * distance,
        playerCoords.z
    )

    local found, groundZ = GetGroundZFor_3dCoord(fallbackCoords.x, fallbackCoords.y, fallbackCoords.z + 10, false)
    if found then
        fallbackCoords = vector3(fallbackCoords.x, fallbackCoords.y, groundZ)
        return fallbackCoords
    end

    return nil
end

function NPCManager:FindBestSpawnArea(playerCoords)
    local bestArea = nil
    local bestScore = 0

    for _, area in ipairs(Config.PreferredSpawnAreas) do
        local distance = #(playerCoords - area.coords)
        if distance < area.radius then
            local score = area.weight * (1 - (distance / area.radius))
            if score > bestScore then
                bestScore = score
                bestArea = area
            end
        end
    end

    return bestArea
end

function NPCManager:FindNearestSidewalk(coords)
    local sidewalkFound, sidewalkCoords = GetClosestVehicleNodeWithHeading(coords.x, coords.y, coords.z, 1, 3.0, 0)

    if sidewalkFound then
        local offset = math.floor(Config.NPCSettings.sidewalkOffset or 2.5)
        local offsetCoords = vector3(
            sidewalkCoords.x + math.random(-offset, offset),
            sidewalkCoords.y + math.random(-offset, offset),
            sidewalkCoords.z
        )

        local found, groundZ = GetGroundZFor_3dCoord(offsetCoords.x, offsetCoords.y, offsetCoords.z + 10, false)
        if found then
            return vector3(offsetCoords.x, offsetCoords.y, groundZ)
        end
    end

    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 10, false)
    if found then
        return vector3(coords.x, coords.y, groundZ)
    end

    return coords
end

function NPCManager:IsValidSpawnLocation(coords, playerCoords)
    local distance = #(coords - playerCoords)

    if distance < Config.NPCSettings.minDistanceFromPlayer or distance > Config.NPCSettings.maxDistanceFromPlayer then
        return false
    end

    return true
end

function NPCManager:IsNearTraffic(coords)
    local nearbyVehicles = GetGamePool('CVehicle')
    for _, vehicle in ipairs(nearbyVehicles) do
        local vehicleCoords = GetEntityCoords(vehicle)
        if #(coords - vehicleCoords) < 5.0 then
            return true
        end
    end
    return false
end

function NPCManager:CreateNPCInteraction(npcData, seatData)
    local hasInteracted = false
    local fallbackBlip = nil

    CreateThread(function()
        SetWaypointOff()
        Wait(100)

        SetNewWaypoint(npcData.coords.x, npcData.coords.y)
        Wait(500)

        local isWaypointActive = IsWaypointActive()

        if not isWaypointActive then
            fallbackBlip = AddBlipForCoord(npcData.coords.x, npcData.coords.y, npcData.coords.z)
            SetBlipSprite(fallbackBlip, 1)
            SetBlipColour(fallbackBlip, 5)
            SetBlipScale(fallbackBlip, 0.8)
            SetBlipAsShortRange(fallbackBlip, false)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString("Taxi Customer")
            EndTextCommandSetBlipName(fallbackBlip)
        end

        while DoesEntityExist(npcData.ped) and not hasInteracted do
            local playerPed = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(playerPed, false)

            if vehicle ~= 0 then
                local vehicleCoords = GetEntityCoords(vehicle)
                local npcCoords = GetEntityCoords(npcData.ped)
                local distance = #(vehicleCoords - npcCoords)
                local vehicleSpeed = GetEntitySpeed(vehicle)

                if distance < 15.0 then
                    TaskGoToEntity(npcData.ped, vehicle, -1, 2.0, 1.5, 1073741824, 0)

                    if distance < 6.0 and vehicleSpeed < 8.0 then
                        SetWaypointOff()

                        if fallbackBlip and DoesBlipExist(fallbackBlip) then
                            RemoveBlip(fallbackBlip)
                        end

                        hasInteracted = true
                        TaxiSystem:PickupPassenger(npcData, seatData)
                        break
                    end
                elseif distance < 25.0 then
                    TaskLookAtEntity(npcData.ped, vehicle, 2000, 2048, 3)
                end
            end

            Wait(500)
        end
    end)

    CreateThread(function()
        Wait(60000)
        if not hasInteracted and DoesEntityExist(npcData.ped) then
            if fallbackBlip and DoesBlipExist(fallbackBlip) then
                RemoveBlip(fallbackBlip)
            end

            SetWaypointOff()
            self:RemoveNPC(npcData.ped)
        end
    end)
end

function NPCManager:RemoveNPC(ped)
    for i, npcData in ipairs(self.activeNPCs) do
        if npcData.ped == ped then

            if DoesEntityExist(ped) then
                DeleteEntity(ped)
            end

            table.remove(self.activeNPCs, i)
            self.spawnedNPCs = self.spawnedNPCs - 1
            break
        end
    end
end

function NPCManager:CleanupAllNPCs()
    for i, npcData in ipairs(self.activeNPCs) do
        if DoesEntityExist(npcData.ped) then
            DeleteEntity(npcData.ped)
        end
    end

    self.activeNPCs = {}
    self.spawnedNPCs = 0
end

CreateThread(function()
    TaxiSystem:Init()
end)