local qbx = exports.qbx_core

local lastCaller = {
    src = nil,
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
        if GetConvarInt('voice_enableCalls', 1) ~= 1 then
            print('[DMSS_videointercom] ATTENZIONE: voice_enableCalls non attivo nel server.cfg (serve setr voice_enableCalls 1)')
        end

        local resource = getVoiceResource()
        local okCaller, errCaller = pcall(function()
            exports[resource]:setPlayerCall(callerSrc, channel)
        end)
        local okPolice, errPolice = pcall(function()
            exports[resource]:setPlayerCall(policeSrc, channel)
        end)

        if not okCaller or not okPolice then
            print(('[DMSS_videointercom] Errore setPlayerCall canale %s: caller=%s police=%s'):format(
                channel, tostring(errCaller), tostring(errPolice)
            ))
        end
    end

    SetTimeout(150, function()
        if not activeVoiceCall or activeVoiceCall.channel ~= channel then return end
        TriggerClientEvent('intercom:client:voiceCallStarted', callerSrc, channel)
        TriggerClientEvent('intercom:client:voiceCallStarted', policeSrc, channel)
    end)
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

    lastCaller = { src = nil }
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

    local callerSrc = lastCaller.src

    TriggerClientEvent('intercom:client:callAnswered', callerSrc)
    TriggerClientEvent('intercom:client:playSound', policeSrc, 'answer')
    TriggerClientEvent('intercom:client:playSound', callerSrc, 'answer')

    clearPolicePendingCall()
    answeredByPolice = policeSrc
    startVoiceCall(callerSrc, policeSrc)

    -- Apri il monitor dopo l'avvio del canale vocale (evita race con pma-voice / PTT)
    SetTimeout(250, function()
        if answeredByPolice ~= policeSrc then return end
        TriggerClientEvent('intercom:client:openMonitor', policeSrc)
    end)

    return true
end

RegisterNetEvent('intercom:server:ringDoorbell', function()
    local src = source
    local player = qbx:GetPlayer(src)

    if not player then return end

    -- Stesso visitatore: aggiorna la chiamata in attesa (evita blocco se UI chiusa per desync)
    if lastCaller.src == src then
        notifyOnDutyPolice('intercom:client:incomingCall')
        return
    end

    lastCaller = { src = src }
    answeredByPolice = nil

    notifyOnDutyPolice('intercom:client:incomingCall')
end)

RegisterNetEvent('intercom:server:answerCall', function()
    local src = source

    if not isPoliceOnDuty(src) then return end
    if not lastCaller.src then
        lib.notify(src, { title = 'Citofono', description = 'Nessuna chiamata in corso.', type = 'error' })
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

RegisterNetEvent('intercom:server:unlockDoor', function(_doorId)
    local src = source

    if not isPoliceOnDuty(src) then return end

    local doorId = Config.DoorlockId
    if not doorId then
        lib.notify(src, { title = 'Citofono', description = 'DoorlockId non configurato.', type = 'error' })
        return
    end

    local door = exports.ox_doorlock:getDoor(doorId)
    if not door then
        lib.notify(src, {
            title = 'Citofono',
            description = ('Porta ox_doorlock #%s non trovata. Verifica Config.DoorlockId.'):format(doorId),
            type = 'error',
        })
        return
    end

    -- ox_doorlock: 0 = sbloccata, 1 = bloccata
    exports.ox_doorlock:setDoorState(doorId, 0)

    lib.notify(src, { title = 'Citofono', description = 'Porta sbloccata.', type = 'success' })

    TriggerClientEvent('intercom:client:playSound', src, 'unlock')

    if lastCaller.src then
        TriggerClientEvent('intercom:client:playSound', lastCaller.src, 'unlock')
        TriggerClientEvent('intercom:client:doorUnlocked', lastCaller.src)
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
        lib.notify(source, { title = 'Errore', description = 'Questo comando è riservato alla polizia in servizio.', type = 'error' })
        return
    end

    if not lastCaller.src then
        lib.notify(source, { title = 'Citofono', description = 'Nessuna chiamata in corso.', type = 'error' })
        return
    end

    connectIntercomCall(source)
end)
