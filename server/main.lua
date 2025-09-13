local QBCore = exports['qb-core']:GetCoreObject()

RegisterNetEvent('taxi:server:completeTrip', function(fare)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)

    if not Player then return end

    local finalAmount = math.max(1, fare)

    Player.Functions.AddMoney('cash', finalAmount)

    TriggerClientEvent('taxi:client:paymentReceived', src, finalAmount)

    local logData = {
        playerName = Player.PlayerData.name,
        citizenid = Player.PlayerData.citizenid,
        amount = finalAmount,
        timestamp = os.date('%Y-%m-%d %H:%M:%S')
    }
end)

QBCore.Functions.CreateCallback('taxi:server:getTaxiData', function(source, cb)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)

    if not Player then
        cb(false)
        return
    end

    cb({
        playerName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
        citizenid = Player.PlayerData.citizenid
    })
end)