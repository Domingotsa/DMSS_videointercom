local qbx = exports.qbx_core

local lastCaller = {
    src = nil,
    name = nil,
}

local function getOnDutyPolice()
    local onDuty = {}

    for _, policeSrc in ipairs(qbx:GetPlayersByJob('police')) do
        local policePlayer = qbx:GetPlayer(policeSrc)

        if policePlayer and policePlayer.PlayerData.job.onduty then
            onDuty[#onDuty + 1] = policeSrc
        end
    end

    return onDuty
end

local function notifyOnDutyPolice(event, ...)
    for _, policeSrc in ipairs(getOnDutyPolice()) do
        TriggerClientEvent(event, policeSrc, ...)
    end
end

local function clearPolicePendingCall()
    notifyOnDutyPolice('intercom:client:clearPendingCall')
end

local function isPoliceOnDuty(src)
    local player = qbx:GetPlayer(src)
    return player
        and player.PlayerData.job.name == 'police'
        and player.PlayerData.job.onduty
end

RegisterNetEvent('intercom:server:ringDoorbell', function()
    local src = source
    local player = qbx:GetPlayer(src)

    if not player then return end

    local charInfo = player.PlayerData.charinfo
    local callerName = charInfo.firstname .. ' ' .. charInfo.lastname

    lastCaller = { src = src, name = callerName }

    notifyOnDutyPolice('intercom:client:incomingCall', callerName)
end)

RegisterNetEvent('intercom:server:answerCall', function()
    local src = source

    if not isPoliceOnDuty(src) then return end
    if not lastCaller.src then
        exports.ox_lib:notify(src, { title = 'Citofono', description = 'Nessuna chiamata in corso.', type = 'error' })
        return
    end

    TriggerClientEvent('intercom:client:callAnswered', lastCaller.src)
    TriggerClientEvent('intercom:client:playSound', src, 'answer')
    TriggerClientEvent('intercom:client:playSound', lastCaller.src, 'answer')

    clearPolicePendingCall()
    TriggerClientEvent('intercom:client:openMonitor', src, lastCaller.name, true)
end)

RegisterNetEvent('intercom:server:unlockDoor', function(doorId)
    local src = source

    if not isPoliceOnDuty(src) then return end

    exports.ox_doorlock:setDoorState(doorId, 0)

    TriggerClientEvent('intercom:client:playSound', src, 'unlock')

    if lastCaller.src then
        TriggerClientEvent('intercom:client:playSound', lastCaller.src, 'unlock')
        TriggerClientEvent('intercom:client:callEnded', lastCaller.src)
    end

    lastCaller = { src = nil, name = nil }
end)

RegisterNetEvent('intercom:server:monitorClosed', function()
    if lastCaller.src then
        TriggerClientEvent('intercom:client:callEnded', lastCaller.src)
    end

    lastCaller = { src = nil, name = nil }
    clearPolicePendingCall()
end)

RegisterNetEvent('intercom:server:callTimeout', function()
    local src = source

    if lastCaller.src == src then
        lastCaller = { src = nil, name = nil }
        clearPolicePendingCall()
    end
end)

lib.addCommand('citofono', {
    help = 'Rispondi al citofono e apri il feed video (alternativa al monitor)',
    restricted = 'group.police',
}, function(source)
    if not isPoliceOnDuty(source) then
        exports.ox_lib:notify(source, { title = 'Errore', description = 'Questo comando è riservato alla polizia in servizio.', type = 'error' })
        return
    end

    if not lastCaller.src then
        exports.ox_lib:notify(source, { title = 'Citofono', description = 'Nessuna chiamata in corso.', type = 'error' })
        return
    end

    TriggerClientEvent('intercom:client:callAnswered', lastCaller.src)
    TriggerClientEvent('intercom:client:playSound', source, 'answer')
    TriggerClientEvent('intercom:client:playSound', lastCaller.src, 'answer')

    clearPolicePendingCall()
    TriggerClientEvent('intercom:client:openMonitor', source, lastCaller.name, true)
end)
