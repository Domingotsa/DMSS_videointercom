local qbx = exports.qbx_core

local lastCaller = {
    src = nil,
    name = nil,
}

local answeredByPolice = nil
local activeVoiceCall = nil
local callChannelSeq = 50000

local function allocCallChannel()
    callChannelSeq = callChannelSeq + 1
    if callChannelSeq > 65530 then
        callChannelSeq = 50001
    end
    return callChannelSeq
end

local function getVoiceResource()
    return Config.VoiceResource or 'pma-voice'
end

local function isVoiceAvailable()
    return Config.VoiceEnabled ~= false and GetResourceState(getVoiceResource()) == 'started'
end

local function endVoiceCall()
    if not activeVoiceCall then return end

    local caller = activeVoiceCall.caller
    local police = activeVoiceCall.police
    activeVoiceCall = nil

    if isVoiceAvailable() then
        local resource = getVoiceResource()
        pcall(function()
            if caller and GetPlayerPing(caller) > 0 then
                exports[resource]:setPlayerCall(caller, 0)
            end
            if police and GetPlayerPing(police) > 0 then
                exports[resource]:setPlayerCall(police, 0)
            end
        end)
    end

    if caller then
        TriggerClientEvent('intercom:client:voiceCallEnded', caller)
    end
    if police then
        TriggerClientEvent('intercom:client:voiceCallEnded', police)
    end
end

local function startVoiceCall(callerSrc, policeSrc)
    if not callerSrc or not policeSrc then return end

    endVoiceCall()

    local channel = allocCallChannel()
    activeVoiceCall = {
        caller = callerSrc,
        police = policeSrc,
        channel = channel,
    }

    if isVoiceAvailable() then
        local resource = getVoiceResource()
        pcall(function()
            exports[resource]:setPlayerCall(callerSrc, channel)
            exports[resource]:setPlayerCall(policeSrc, channel)
        end)
    end

    TriggerClientEvent('intercom:client:voiceCallStarted', callerSrc, channel)
    TriggerClientEvent('intercom:client:voiceCallStarted', policeSrc, channel)
end

local function getOnDutyPolice()
    local _, players = exports.qbx_core:GetDutyCountJob('police')
    return players or {}
end

local function notifyOnDutyPolice(event, ...)
    for _, policeSrc in ipairs(getOnDutyPolice()) do
        TriggerClientEvent(event, policeSrc, ...)
    end
end

local function clearPolicePendingCall()
    notifyOnDutyPolice('intercom:client:clearPendingCall')
end

local function resetCallState(opts)
    opts = opts or {}
    endVoiceCall()

    if opts.notifyVisitorEnded and lastCaller.src then
        TriggerClientEvent('intercom:client:callEnded', lastCaller.src)
    end

    if opts.forceClosePolice and answeredByPolice then
        TriggerClientEvent('intercom:client:forceCloseMonitor', answeredByPolice)
    end

    lastCaller = { src = nil, name = nil }
    answeredByPolice = nil
    clearPolicePendingCall()
end

local function isPoliceOnDuty(src)
    local player = qbx:GetPlayer(src)
    if not player or not player.PlayerData.job then return false end

    local jobName = Config.PoliceJob or 'police'
    local job = player.PlayerData.job
    local nameMatch = job.name == jobName or job.type == jobName
    if not nameMatch then return false end

    if Config.PoliceRequireDuty == false then return true end

    return job.onduty == true or job.onDuty == true
end

local function connectIntercomCall(policeSrc)
    if not lastCaller.src then return false end

    TriggerClientEvent('intercom:client:callAnswered', lastCaller.src)
    TriggerClientEvent('intercom:client:playSound', policeSrc, 'answer')
    TriggerClientEvent('intercom:client:playSound', lastCaller.src, 'answer')

    clearPolicePendingCall()
    answeredByPolice = policeSrc
    startVoiceCall(lastCaller.src, policeSrc)
    TriggerClientEvent('intercom:client:openMonitor', policeSrc, lastCaller.name)

    return true
end

RegisterNetEvent('intercom:server:ringDoorbell', function()
    local src = source
    local player = qbx:GetPlayer(src)

    if not player then return end

    local charInfo = player.PlayerData.charinfo
    local callerName = charInfo.firstname .. ' ' .. charInfo.lastname

    lastCaller = { src = src, name = callerName }
    answeredByPolice = nil

    notifyOnDutyPolice('intercom:client:incomingCall', callerName)
end)

RegisterNetEvent('intercom:server:answerCall', function()
    local src = source

    if not isPoliceOnDuty(src) then return end
    if not lastCaller.src then
        exports.ox_lib:notify(src, { title = 'Citofono', description = 'Nessuna chiamata in corso.', type = 'error' })
        return
    end

    connectIntercomCall(src)
end)

RegisterNetEvent('intercom:server:hangUpCall', function()
    local src = source

    if lastCaller.src ~= src then return end

    notifyOnDutyPolice('intercom:client:visitorHungUp')
    resetCallState({ forceClosePolice = true })
end)

RegisterNetEvent('intercom:server:unlockDoor', function(doorId)
    local src = source

    if not isPoliceOnDuty(src) then return end

    exports.ox_doorlock:setDoorState(doorId, 0)

    TriggerClientEvent('intercom:client:playSound', src, 'unlock')

    if lastCaller.src then
        TriggerClientEvent('intercom:client:playSound', lastCaller.src, 'unlock')
    end

    resetCallState({ notifyVisitorEnded = true })
end)

RegisterNetEvent('intercom:server:monitorClosed', function()
    resetCallState({ notifyVisitorEnded = true })
end)

RegisterNetEvent('intercom:server:callTimeout', function()
    local src = source

    if lastCaller.src == src then
        resetCallState({ forceClosePolice = answeredByPolice ~= nil })
    end
end)

AddEventHandler('playerDropped', function()
    local src = source

    if lastCaller.src == src and not activeVoiceCall then
        notifyOnDutyPolice('intercom:client:visitorHungUp')
        resetCallState({})
        return
    end

    if not activeVoiceCall then return end

    if activeVoiceCall.caller == src or activeVoiceCall.police == src then
        if activeVoiceCall.caller == src and answeredByPolice then
            TriggerClientEvent('intercom:client:forceCloseMonitor', answeredByPolice)
        end

        if activeVoiceCall.police == src and lastCaller.src then
            TriggerClientEvent('intercom:client:callEnded', lastCaller.src)
        end

        resetCallState({})
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

    connectIntercomCall(source)
end)
