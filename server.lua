local QBCore = exports['qbx-core']:GetCoreObject()
local participants = {}
local raceData = {
    isActive = false,
    buyIn = 0,
    coords = nil
}

local function resetRace()
    for _, data in pairs(participants) do
        local src = data.src
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            Player.Functions.SetMetaData('inrace', false)
        end
        TriggerClientEvent('qbx-street-racing:unlockPlayer', src)
        TriggerClientEvent('qbx-street-racing:resetInviteFlag', src)
    end
    participants = {}
    raceData = { isActive = false, buyIn = 0, coords = nil }
    TriggerClientEvent('qbx-street-racing:resetRace', -1)
end



RegisterNetEvent('qbx-street-racing:startRaceRadial', function(buyIn)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if raceData.isActive then
        TriggerClientEvent('QBCore:Notify', src, 'The streets are too hot, try again in a few.', 'error')
        return
    end

    if Player.PlayerData.metadata['inrace'] then
        TriggerClientEvent('QBCore:Notify', src, 'You are already in a race.', 'error')
        return
    end

    if not buyIn or type(buyIn) ~= "number" or buyIn < Config.MinBuyIn or buyIn > Config.MaxBuyIn then
        TriggerClientEvent('QBCore:Notify', src, 'Buy-in must be between $'..Config.MinBuyIn..' and $'..Config.MaxBuyIn, 'error')
        return
    end

    if not Player.Functions.RemoveMoney('cash', buyIn, "street-race-buyin") then
        TriggerClientEvent('QBCore:Notify', src, 'Insufficient funds for buy-in.', 'error')
        return
    end

    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local success, nodeX, nodeY, nodeZ = GetNthClosestVehicleNodeWithHeading(playerCoords.x, playerCoords.y, playerCoords.z, Config.RaceDistance, 0, 3.0, 0.0)
    if not success then
        Player.Functions.AddMoney('cash', buyIn, "street-race-buyin-refund")
        TriggerClientEvent('QBCore:Notify', src, 'Failed to find a race destination.', 'error')
        return
    end

    raceData = {
        isActive = true,
        buyIn = buyIn,
        coords = vector3(nodeX, nodeY, nodeZ),
        confirmationOpen = true 
    }

    participants = {}

    -- Add initiator first
    Player.Functions.SetMetaData('inrace', true)
    table.insert(participants, { src = src, name = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname, confirmed = true })

    local players = QBCore.Functions.GetPlayers()
    for _, id in pairs(players) do
        if id ~= src then
            local ped = GetPlayerPed(id)
            local other = QBCore.Functions.GetPlayer(id)
            if other and not other.PlayerData.metadata['inrace'] and IsPedInAnyVehicle(ped, false) then
                local dist = #(GetEntityCoords(ped) - playerCoords)
                if dist <= Config.JoinRadius then
                    if #participants < Config.MaxRacers then
                        table.insert(participants, { src = id, confirmed = false })
                        other.Functions.SetMetaData('inrace', true)
                        TriggerClientEvent('qbx-street-racing:inviteToRace', id)
                    else
                        TriggerClientEvent('QBCore:Notify', src, 'Maximum racers reached.', 'info')
                        break
                    end
                end
            end
        end
    end

    -- Start confirmation timeout thread
    CreateThread(function()
        Wait(Config.ConfirmationTimeout * 1000)

        raceData.confirmationOpen = false 

        local confirmedParticipants = {}
        for _, data in pairs(participants) do
            if data.confirmed then
                table.insert(confirmedParticipants, data)
            else
                local p = QBCore.Functions.GetPlayer(data.src)
                if p then
                    p.Functions.SetMetaData('inrace', false)
                end
                TriggerClientEvent('QBCore:Notify', data.src, 'You declined or did not confirm the race.', 'error')
                TriggerClientEvent('qbx-street-racing:unlockPlayer', data.src)
                TriggerClientEvent('qbx-street-racing:resetInviteFlag', data.src)
            end
        end
        participants = confirmedParticipants

        if #participants < 2 then
            for _, data in pairs(participants) do
                local p = QBCore.Functions.GetPlayer(data.src)
                if p then
                    if data.confirmed then
                        p.Functions.AddMoney('cash', buyIn, "street-race-buyin-refund")
                    end
                    p.Functions.SetMetaData('inrace', false)
                end
                TriggerClientEvent('QBCore:Notify', data.src, 'Not enough racers confirmed. Race canceled.', 'error')
                TriggerClientEvent('qbx-street-racing:unlockPlayer', data.src)
                TriggerClientEvent('qbx-street-racing:resetInviteFlag', data.src)
            end

            raceData.confirmationOpen = false  -- <-- Explicitly ensure this is false here as well
            raceData.isActive = false
            raceData.buyIn = 0
            raceData.coords = nil

            participants = {}
            return
        end

        for _, data in pairs(participants) do
            TriggerClientEvent('qbx-street-racing:lockPlayer', data.src)
            TriggerClientEvent('qbx-street-racing:startCountdown', data.src)
        end
    end)
end)



RegisterNetEvent('qbx-street-racing:confirmRace', function()
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    if not raceData.confirmationOpen then
        TriggerClientEvent('QBCore:Notify', src, 'Race confirmation has expired.', 'error')
        return
    end

    for i, p in pairs(participants) do
        if p.src == src then
            if p.confirmed then
                TriggerClientEvent('QBCore:Notify', src, 'You have already confirmed.', 'error')
                return
            end

            if player.Functions.RemoveMoney('cash', raceData.buyIn, "street-race-buyin") then
                participants[i].confirmed = true
                player.Functions.SetMetaData('inrace', true)
                TriggerClientEvent('QBCore:Notify', src, 'You have joined the race!', 'success')
            else
                TriggerClientEvent('QBCore:Notify', src, 'Insufficient funds for buy-in.', 'error')
            end
            return
        end
    end

    TriggerClientEvent('QBCore:Notify', src, 'You were not invited to this race.', 'error')
end)





RegisterNetEvent('qbx-street-racing:declineRace', function()
    local src = source
    for i, p in pairs(participants) do
        if p.src == src then
            participants[i].confirmed = false
            break
        end
    end

    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        Player.Functions.SetMetaData('inrace', false)
    end
end)

RegisterNetEvent('qbx-street-racing:unlockPlayer', function()
    local src = source
    TriggerClientEvent('qbx-street-racing:unlockPlayer', src)
end)

RegisterNetEvent('qbx-street-racing:finishRace', function() 
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)

    if not Player then
        print(("qbx-street-racing:finishRace - Player not found for source %s"):format(src))
        return
    end

    local winnings = raceData.buyIn * #participants
    local tax = Config.RaceTax * winnings
    local payout = math.floor(winnings - tax)

    -- Prevent negative or zero payout
    if payout <= 0 then
        payout = 0
        TriggerClientEvent('QBCore:Notify', src, 'You won, but after tax ($'..tax..'), you receive no payout.', 'error')
    else
        Player.Functions.AddMoney('cash', payout)
        TriggerClientEvent('QBCore:Notify', src, 'You won the race! Payout: $'..payout, 'success')
    end

    -- Always record the win, even with zero payout
    local wins = Player.PlayerData.metadata['racewins'] or 0
    Player.Functions.SetMetaData('racewins', wins + 1)

    resetRace()
end)


AddEventHandler('playerDropped', function()
    local src = source

    -- Remove from participants if in race
    for i = #participants, 1, -1 do
        if participants[i].src == src then
            table.remove(participants, i)
        end
    end

    -- Release metadata if race is active
    if raceData.isActive then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            Player.Functions.SetMetaData('inrace', false)
        end

        -- Cancel the race if too few participants remain
        if #participants < 2 then
            for _, data in pairs(participants) do
                local p = QBCore.Functions.GetPlayer(data.src)
                if p then
                    p.Functions.SetMetaData('inrace', false)
                    p.Functions.AddMoney('cash', raceData.buyIn, "street-race-buyin-refund")
                    TriggerClientEvent('QBCore:Notify', data.src, 'Race canceled. Not enough racers.', 'error')
                    TriggerClientEvent('qbx-street-racing:unlockPlayer', data.src)
                    TriggerClientEvent('qbx-street-racing:resetInviteFlag', data.src)
                end
            end

            -- Fully reset race state
            raceData = { isActive = false, buyIn = 0, coords = nil, confirmationOpen = false }
            participants = {}
        end
    end
end)



RegisterNetEvent('qbx-street-racing:requestLeaderboard', function()
    local src = source
    local results = MySQL.query.await('SELECT name, metadata FROM players')
    local leaderboard = {}

    for _, result in pairs(results) do
        local metadata = json.decode(result.metadata or '{}')
        local rpName = "Unknown"
        if metadata['charinfo'] and metadata['charinfo']['firstname'] and metadata['charinfo']['lastname'] then
            rpName = metadata['charinfo']['firstname'] .. ' ' .. metadata['charinfo']['lastname']
        else
            rpName = result.name or "Unknown"
        end

        local wins = metadata['racewins'] or 0
        if wins > 0 then
            table.insert(leaderboard, {
                name = rpName,
                wins = wins
            })
        end
    end

    table.sort(leaderboard, function(a, b) return a.wins > b.wins end)
    TriggerClientEvent('qbx-street-racing:showLeaderboard', src, leaderboard)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    local players = QBCore.Functions.GetPlayers()
    for _, src in pairs(players) do
        TriggerClientEvent('qbx-street-racing:resetInviteFlag', src)
    end
end)

AddEventHandler('playerSpawned', function()
    local src = source
    TriggerClientEvent('qbx-street-racing:resetInviteFlag', src)
end)
