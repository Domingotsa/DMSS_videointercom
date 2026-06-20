local intercomCam = nil
local intercomProp = nil
local cctvPropEntities = {}
local isViewingCam = false
local activeMonitorCamIndex = 1
local isVisitorUiOpen = false
local visitorCallAnswered = false
local hasAnsweredCall = false
local pendingCall = nil
local monitorViewMode = nil
local monitorZoneActive = false
local propZoneActive = false
local visitorHintActive = false
local policeVoiceHintActive = false
local voiceCallActive = false
local voiceInputActive = false
local voiceProximityThreadActive = false
local dualCamPreviewActive = false

-- Controlli microfono da tenere attivi con NUI monitor aperto (PTT pma-voice)
local VOICE_INPUT_CONTROLS = {
    249, -- INPUT_PUSH_TO_TALK
    46,  -- INPUT_SPEECH_ABORT / voce
}

local Sounds = {
    doorbell = { 'Door_Bell', 'DLC_HEIST_HACKING_SNAKE_SOUNDS' },
    answer = { 'Phone_Generic_Key_03', 'Phone_SoundSet_Default' },
    cctvOn = { 'FocusIn', 'HintCamSounds' },
    unlock = { 'Hack_Success', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS' },
    callEnd = { 'Hang_Up', 'Phone_SoundSet_Default' },
    ring = { 'Ring.Ring', 'Phone_SoundSet_Default' },
}

local function playIntercomSound(key)
    local sound = Sounds[key]
    if not sound then return end
    PlaySoundFrontend(-1, sound[1], sound[2], true)
end

local function isPoliceOnDuty()
    local playerData = exports.qbx_core:GetPlayerData()
    if not playerData or not playerData.job then return false end

    local jobName = Config.PoliceJob or 'police'
    local job = playerData.job
    local nameMatch = job.name == jobName or job.type == jobName
    if not nameMatch then return false end

    if Config.PoliceRequireDuty == false then return true end

    return job.onduty == true or job.onDuty == true
end

local function sendNui(action, data)
    local msg = { action = action }
    if data then
        for key, value in pairs(data) do
            msg[key] = value
        end
    end
    SendNUIMessage(msg)
end

local function showVisitorHint()
    if visitorHintActive then
        lib.hideTextUI()
        visitorHintActive = false
    end

    visitorHintActive = true
    local message = visitorCallAnswered
        and 'In linea · parla al microfono  ·  [BACKSPACE] Riaggancia'
        or '[BACKSPACE] Riaggancia  ·  [ESC] Chiudi chiamata'

    lib.showTextUI(message, {
        position = 'bottom-center',
        icon = visitorCallAnswered and 'microphone' or 'phone-slash',
    })
end

local function showPoliceVoiceHint()
    if policeVoiceHintActive then return end
    policeVoiceHintActive = true
    lib.showTextUI('Citofono attivo · parla al microfono  ·  [ESC] Chiudi', {
        position = 'bottom-center',
        icon = 'microphone',
    })
end

local function hidePoliceVoiceHint()
    if not policeVoiceHintActive then return end
    policeVoiceHintActive = false
    lib.hideTextUI()
end

local function getVoiceResource()
    return Config.VoiceResource or 'pma-voice'
end

local function isVoiceResourceReady()
    return Config.VoiceEnabled ~= false and GetResourceState(getVoiceResource()) == 'started'
end

-- Il canale call lo imposta il server (setPlayerCall). Il client limita solo la proximity
-- così la voce non esce anche in chat vocale normale verso player vicini/lontani.
local function applyPrivateProximityOverride()
    if not isVoiceResourceReady() then return end

    local resource = getVoiceResource()
    pcall(function()
        exports[resource]:overrideProximityRange(Config.VoiceProximityOverride or 0.01, true)
    end)
end

local function clearPrivateProximityOverride()
    if not isVoiceResourceReady() then return end

    pcall(function()
        exports[getVoiceResource()]:clearProximityOverride()
    end)
end

local function leaveClientCallChannel()
    if not isVoiceResourceReady() then return end

    pcall(function()
        exports[getVoiceResource()]:removePlayerFromCall()
    end)
end

local function startPrivateProximityGuard()
    if voiceProximityThreadActive then return end
    voiceProximityThreadActive = true

    CreateThread(function()
        while voiceProximityThreadActive and voiceCallActive do
            applyPrivateProximityOverride()
            Wait(1500)
        end
        voiceProximityThreadActive = false
    end)
end

local function stopPrivateProximityGuard()
    voiceProximityThreadActive = false
end

local function enterPrivateCallMode(_channel)
    if not isVoiceResourceReady() then return end

    local resource = getVoiceResource()
    pcall(function()
        if exports[resource].setCallVolume then
            exports[resource]:setCallVolume(Config.VoiceCallVolume or 100)
        end
    end)

    applyPrivateProximityOverride()
    startPrivateProximityGuard()
end

local function exitPrivateCallMode()
    stopPrivateProximityGuard()
    clearPrivateProximityOverride()
    leaveClientCallChannel()
end

local function setMonitorNuiFocus(enabled)
    if enabled then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(true)
    else
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
    end
end

local function startVoiceInputLoop()
    if voiceInputActive then return end
    voiceInputActive = true

    CreateThread(function()
        while voiceInputActive and voiceCallActive do
            for i = 1, #VOICE_INPUT_CONTROLS do
                local control = VOICE_INPUT_CONTROLS[i]
                EnableControlAction(0, control, true)
                EnableControlAction(1, control, true)
                EnableControlAction(2, control, true)
            end
            Wait(0)
        end
        voiceInputActive = false
    end)
end

local function stopVoiceInputLoop()
    voiceInputActive = false
end

local function hideVisitorHint()
    if not visitorHintActive then return end
    visitorHintActive = false
    lib.hideTextUI()
end

local function releasePlayerControls()
    local ped = cache.ped
    if not ped or ped == 0 then return end
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
end

local function closeVisitorUi()
    if not isVisitorUiOpen then return end
    isVisitorUiOpen = false
    visitorCallAnswered = false
    hideVisitorHint()
    releasePlayerControls()
    sendNui('hideVisitor')
end

local function openVisitorUi()
    if isVisitorUiOpen then return end
    isVisitorUiOpen = true
    visitorCallAnswered = false

    playIntercomSound('ring')
    sendNui('showVisitor', { location = Config.LocationLabel })
    sendNui('playSound', { sound = 'ring' })
    showVisitorHint()

    SetTimeout(Config.VisitorTimeout, function()
        if isVisitorUiOpen then
            closeVisitorUi()
            TriggerServerEvent('intercom:server:callTimeout')
            playIntercomSound('callEnd')
            exports['ss-libs']:Notify('Nessuna risposta dal centralino.', 'error')
        end
    end)
end

local function hangUpCall()
    if not isVisitorUiOpen then return end

    TriggerServerEvent('intercom:server:hangUpCall')
    playIntercomSound('callEnd')
    sendNui('playSound', { sound = 'callEnd' })
    closeVisitorUi()
    exports['ss-libs']:Notify('Hai riagganciato.', 'inform')
end

local function closeMonitor(skipServer)
    if not isViewingCam then return end

    stopDualCamPreview()
    sendNui('hidePolice')
    setMonitorNuiFocus(false)

    DoScreenFadeOut(300)
    Wait(300)

    ClearTimecycleModifier()
    DestroyCam(intercomCam, false)
    RenderScriptCams(false, false, 0, true, true)
    intercomCam = nil
    isViewingCam = false
    hasAnsweredCall = false
    activeMonitorCamIndex = 1

    DoScreenFadeIn(300)

    if not skipServer and monitorViewMode == 'intercom' then
        TriggerServerEvent('intercom:server:monitorClosed')
    end

    hidePoliceVoiceHint()
    monitorViewMode = nil
end

local function unlockDoorFromMonitor()
    if monitorViewMode ~= 'intercom' or not isViewingCam or not hasAnsweredCall then
        exports['ss-libs']:Notify('Devi prima rispondere al citofono.', 'error')
        return
    end

    TriggerServerEvent('intercom:server:unlockDoor', Config.DoorlockId)
    playIntercomSound('unlock')
    sendNui('playSound', { sound = 'unlock' })
    closeMonitor()
end

local function answerPoliceCall()
    if not isPoliceOnDuty() then
        exports['ss-libs']:Notify('Accesso riservato alla polizia in servizio.', 'error')
        return
    end
    if not pendingCall then
        exports['ss-libs']:Notify('Nessuna chiamata in corso.', 'error')
        return
    end
    TriggerServerEvent('intercom:server:answerCall')
end

-- ── Prop ────────────────────────────────────────────────────────────

local function getWorldFromBase(base, offset, headingDelta)
    local o = offset or vec3(0.0, 0.0, 0.0)
    local world = GetOffsetFromCoordAndHeadingInWorldCoords(base.x, base.y, base.z, base.w, o.x, o.y, o.z)
    return world.x, world.y, world.z, (base.w + (headingDelta or 0.0)) % 360.0
end

local function getWorldFromIntercomBase(offset, headingDelta)
    return getWorldFromBase(Config.IntercomProp, offset, headingDelta)
end

local function getPropDepth()
    if Config.PropDepth ~= nil then
        return Config.PropDepth
    end
    local o = Config.PropOffset or vec3(0.0, 0.0, 0.0)
    return (Config.PropWallDepth or 0.0) + o.x
end

local function getPropBaseCoords()
    local o = Config.PropOffset or vec3(0.0, 0.0, 0.0)
    return getWorldFromIntercomBase(vec3(0.0, o.y, o.z), 0.0)
end

local function applyEntityDepth(entity, depth)
    if not depth or depth == 0.0 or not entity or not DoesEntityExist(entity) then return end
    local pos = GetOffsetFromEntityInWorldCoords(entity, depth, 0.0, 0.0)
    SetEntityCoordsNoOffset(entity, pos.x, pos.y, pos.z, false, false, false)
end

local function applyPropDepth(entity)
    applyEntityDepth(entity, getPropDepth())
end

local function getPropCoords()
    if intercomProp and DoesEntityExist(intercomProp) then
        local pos = GetEntityCoords(intercomProp)
        return pos.x, pos.y, pos.z, GetEntityHeading(intercomProp)
    end

    local x, y, z, heading = getPropBaseCoords()
    local depth = getPropDepth()
    if depth ~= 0.0 then
        local pushed = GetOffsetFromCoordAndHeadingInWorldCoords(x, y, z, heading, depth, 0.0, 0.0)
        x, y, z = pushed.x, pushed.y, pushed.z
    end
    return x, y, z, heading
end

local function isNearIntercom()
    local p = Config.IntercomProp
    return #(GetEntityCoords(cache.ped) - vec3(p.x, p.y, p.z)) <= (Config.SpawnDistance or 80.0)
end

local function applyEntityRotation(entity, heading, rotation)
    local rot = rotation or Config.PropRotation or vec3(0.0, 0.0, 0.0)
    if rot.x ~= 0.0 or rot.y ~= 0.0 then
        SetEntityRotation(entity, rot.x, rot.y, heading + rot.z, 2, true)
    else
        SetEntityHeading(entity, heading)
    end
end

local function applyPropRotation(entity, heading)
    applyEntityRotation(entity, heading, Config.PropRotation)
end

local function deleteProp()
    if intercomProp and DoesEntityExist(intercomProp) then
        DeleteEntity(intercomProp)
    end
    intercomProp = nil
end

local function cleanupPropZone()
    if not propZoneActive then return end
    pcall(function()
        exports.ox_target:removeZone('intercom_prop_zone')
    end)
    if intercomProp and DoesEntityExist(intercomProp) then
        pcall(function()
            exports.ox_target:removeLocalEntity(intercomProp)
        end)
    end
    propZoneActive = false
end

local function getIntercomTargetOptions()
    local distance = Config.InteractRadius or 2.0
    return {
        {
            name = 'intercom_ring',
            icon = 'fa-solid fa-bell',
            label = 'Suona Citofono',
            distance = distance,
            canInteract = function()
                return not isVisitorUiOpen
            end,
            onSelect = function()
                if isVisitorUiOpen then return end
                if LocalPlayer.state.intercomCooldown then
                    exports['ss-libs']:Notify('Hai già suonato, attendi un momento.', 'error')
                    return
                end

                TriggerServerEvent('intercom:server:ringDoorbell')
                openVisitorUi()

                LocalPlayer.state:set('intercomCooldown', true, false)
                SetTimeout(8000, function()
                    LocalPlayer.state:set('intercomCooldown', false, false)
                end)
            end,
        },
        {
            name = 'intercom_hangup',
            icon = 'fa-solid fa-phone-slash',
            label = 'Riaggancia',
            distance = distance,
            canInteract = function()
                return isVisitorUiOpen
            end,
            onSelect = function()
                if not isVisitorUiOpen then return end
                hangUpCall()
            end,
        },
    }
end

local function refreshIntercomTarget()
    cleanupPropZone()

    local x, y, z = getPropCoords()
    local distance = Config.InteractRadius or 2.0

    exports.ox_target:addSphereZone({
        name = 'intercom_prop_zone',
        coords = vec3(x, y, z),
        radius = distance,
        debug = Config.Debug,
        options = getIntercomTargetOptions(),
    })
    propZoneActive = true
end

local function waitAreaReady(x, y, z)
    RequestCollisionAtCoord(x, y, z)

    local interior = GetInteriorAtCoords(x, y, z)
    if interior ~= 0 then
        PinInteriorInMemory(interior)
        local deadline = GetGameTimer() + (Config.InteriorLoadTimeout or 15000)
        while not IsInteriorReady(interior) and GetGameTimer() < deadline do
            Wait(50)
        end
    end

    local deadline = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(cache.ped) and GetGameTimer() < deadline do
        Wait(50)
    end
end

local function linkPropToInterior(entity, x, y, z)
    if not entity or not DoesEntityExist(entity) then return end

    local interior = GetInteriorAtCoords(x, y, z)
    if interior == 0 then return end

    PinInteriorInMemory(interior)

    local room = GetRoomKeyFromEntity(cache.ped)
    if room ~= 0 then
        ForceRoomForEntity(entity, interior, room)
    end

    ResetEntityAlpha(entity)
    SetEntityVisible(entity, true, false)
end

local function propEntityExists(entity)
    return entity and DoesEntityExist(entity)
end

local function setupPropZone()
    refreshIntercomTarget()
end

local function spawnProp()
    if not Config.UseVisualProp then return false end
    if not isNearIntercom() then return false end

    local x, y, z, heading = getPropBaseCoords()

    if propEntityExists(intercomProp) then
        linkPropToInterior(intercomProp, x, y, z)
        return true
    end

    cleanupPropZone()
    deleteProp()
    waitAreaReady(x, y, z)

    if not lib.requestModel(Config.IntercomModel, 10000) then
        print(('[DMSS_videointercom] Modello non caricato: %s'):format(Config.IntercomModel))
        return false
    end

    intercomProp = CreateObject(Config.IntercomModel, x, y, z, false, false, false)
    if not intercomProp or intercomProp == 0 or not DoesEntityExist(intercomProp) then
        print('[DMSS_videointercom] CreateObject fallito')
        SetModelAsNoLongerNeeded(Config.IntercomModel)
        return false
    end

    SetEntityAsMissionEntity(intercomProp, true, true)
    SetEntityCoordsNoOffset(intercomProp, x, y, z, false, false, false)
    applyPropRotation(intercomProp, heading)
    applyPropDepth(intercomProp)

    local finalPos = GetEntityCoords(intercomProp)
    ResetEntityAlpha(intercomProp)
    SetEntityVisible(intercomProp, true, false)
    SetEntityCollision(intercomProp, true, false)
    FreezeEntityPosition(intercomProp, true)
    SetEntityInvincible(intercomProp, true)
    SetEntityLodDist(intercomProp, 500)
    linkPropToInterior(intercomProp, finalPos.x, finalPos.y, finalPos.z)
    SetModelAsNoLongerNeeded(Config.IntercomModel)

    setupPropZone()

    if Config.Debug then
        print(('[DMSS_videointercom] Prop spawnato a %.2f, %.2f, %.2f (depth %.2f)'):format(
            finalPos.x, finalPos.y, finalPos.z, getPropDepth()
        ))
    end

    return true
end

local function deleteCctvProps()
    for _, entity in pairs(cctvPropEntities) do
        if entity and DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end
    cctvPropEntities = {}
end

local function isVirtualCctvEntry(entry)
    return entry and (entry.virtual == true or entry.noProp == true)
end

local function getCctvPropPlacement(entry)
    local base = entry.coords
    local o = entry.propOffset or vec3(0.0, 0.0, 0.0)
    local x, y, z, heading = getWorldFromBase(base, vec3(0.0, o.y, o.z), 0.0)
    return x, y, z, heading, entry.depth or 0.0
end

local function getCctvFeedPlacement(entry)
    if isVirtualCctvEntry(entry) then
        if entry.feedView or entry.feedCoords then
            local feed = entry.feedView or entry.feedCoords
            return feed.x, feed.y, feed.z, feed.w
        end

        local base = Config.IntercomProp
        local o = entry.feedOffset or vec3(0.0, 0.10, 1.42)
        return getWorldFromBase(base, o, entry.feedHeadingOffset or 0.0)
    end

    if entry.feedView or entry.feedCoords then
        local feed = entry.feedView or entry.feedCoords
        return feed.x, feed.y, feed.z, feed.w
    end

    local base = entry.coords
    local o = entry.feedOffset or vec3(0.0, 0.0, 0.0)
    return getWorldFromBase(base, o, 0.0)
end

local function buildCctvFeed(entry, index)
    if isVirtualCctvEntry(entry) or entry.feedView or entry.feedCoords or entry.feedOffset then
        local x, y, z, heading = getCctvFeedPlacement(entry)
        return {
            x = x,
            y = y,
            z = z,
            heading = heading,
            pitch = entry.feedPitch or 0.0,
            fov = entry.feedFov or 60.0,
            label = entry.label or 'CAM-01',
        }
    end

    local entity = index and cctvPropEntities[index]
    if entity and DoesEntityExist(entity) then
        local pos = GetEntityCoords(entity)
        return {
            x = pos.x,
            y = pos.y,
            z = pos.z,
            heading = GetEntityHeading(entity),
            pitch = entry.feedPitch or 0.0,
            fov = entry.feedFov or 60.0,
            label = entry.label or 'CAM-01',
        }
    end

    local x, y, z, heading = getCctvPropPlacement(entry)
    return {
        x = x,
        y = y,
        z = z,
        heading = heading,
        pitch = entry.feedPitch or 0.0,
        fov = entry.feedFov or 60.0,
        label = entry.label or 'CAM-01',
    }
end

local function getIntercomCallFeed()
    if Config.CctvProps then
        for i = 1, #Config.CctvProps do
            if Config.CctvProps[i].intercomFeed then
                return buildCctvFeed(Config.CctvProps[i], i)
            end
        end

        local idx = Config.IntercomCameraIndex or 1
        local entry = Config.CctvProps[idx]
        if entry then
            return buildCctvFeed(entry, idx)
        end
    end

    local x, y, z, heading = getPropCoords()
    return {
        x = x,
        y = y,
        z = z,
        heading = heading,
        pitch = 0.0,
        fov = 60.0,
        label = 'CAM-01 · INGRESSO',
    }
end

local function getMonitorFeeds()
    local feeds = {}

    if Config.CctvProps then
        local hasMonitorFlag = false
        for i = 1, #Config.CctvProps do
            if Config.CctvProps[i].monitorFeed then
                hasMonitorFlag = true
                break
            end
        end

        for i = 1, #Config.CctvProps do
            local entry = Config.CctvProps[i]
            local include = entry.monitorFeed
                or (not hasMonitorFlag and (entry.feedView or entry.feedCoords or entry.feedOffset))

            if include then
                local feed = buildCctvFeed(entry, i)
                feed.index = i
                feeds[#feeds + 1] = feed
            end
        end
    end

    if #feeds == 0 then
        local x, y, z, heading = getPropCoords()
        feeds[1] = {
            x = x,
            y = y,
            z = z,
            heading = heading,
            pitch = 0.0,
            fov = 60.0,
            label = 'CAM-01 · INGRESSO',
            index = 1,
        }
    end

    return feeds
end

local function getMonitorFeed(index)
    local feeds = getMonitorFeeds()
    index = index or activeMonitorCamIndex or 1
    if index < 1 then index = 1 end
    if index > #feeds then index = #feeds end
    return feeds[index], feeds
end

local function buildMonitorCameraList(feeds)
    local cameras = {}
    for i = 1, #feeds do
        cameras[i] = {
            index = i,
            label = feeds[i].label,
        }
    end
    return cameras
end

local function findMonitorFeedIndex(matcher)
    local feeds = getMonitorFeeds()
    for i = 1, #feeds do
        local entry = Config.CctvProps and Config.CctvProps[feeds[i].index]
        if entry and matcher(entry, feeds[i]) then
            return i
        end
    end
    return 1
end

local function getIntegratedMonitorFeedIndex()
    return findMonitorFeedIndex(function(entry)
        return entry.intercomFeed == true
    end)
end

local function getPrimaryWideMonitorFeedIndex()
    return findMonitorFeedIndex(function(entry)
        return entry.monitorFeed and not isVirtualCctvEntry(entry)
    end)
end

local function stopDualCamPreview()
    dualCamPreviewActive = false
end

local function startDualCamPreview()
    if Config.DualCamPreviewOnRing == false then return end
    if dualCamPreviewActive then return end
    if not pendingCall or not isViewingCam or monitorViewMode ~= 'cctv' then return end

    local integratedIdx = getIntegratedMonitorFeedIndex()
    local wideIdx = getPrimaryWideMonitorFeedIndex()
    if integratedIdx == wideIdx then return end

    dualCamPreviewActive = true

    CreateThread(function()
        local showIntegrated = false
        while dualCamPreviewActive do
            if not pendingCall or not isViewingCam or monitorViewMode ~= 'cctv' then break end

            showIntegrated = not showIntegrated
            local idx = showIntegrated and integratedIdx or wideIdx
            applyMonitorCamera(idx)
            refreshMonitorUi({
                hasPendingCall = true,
                activeCamera = idx,
                dualCamPreview = true,
            })

            Wait(Config.DualCamPreviewInterval or 3000)
        end

        dualCamPreviewActive = false
    end)
end

local function focusMonitorOnRing(callerName)
    if not isViewingCam or monitorViewMode ~= 'cctv' then return end

    local integratedIdx = getIntegratedMonitorFeedIndex()
    activeMonitorCamIndex = integratedIdx
    applyMonitorCamera(integratedIdx)
    refreshMonitorUi({
        caller = callerName or pendingCall,
        hasPendingCall = true,
        activeCamera = integratedIdx,
    })
    startDualCamPreview()
end

local function applyMonitorCamera(index)
    if monitorViewMode ~= 'cctv' then return end

    local feed, feeds = getMonitorFeed(index)
    if not feed then return end

    activeMonitorCamIndex = index

    if intercomCam and DoesCamExist(intercomCam) then
        SetCamCoord(intercomCam, feed.x, feed.y, feed.z)
        SetCamRot(intercomCam, feed.pitch, 0.0, feed.heading, 2)
        SetCamFov(intercomCam, feed.fov)
    end

    sendNui('updateCamera', {
        camera = feed.label,
        activeCamera = index,
        cameras = buildMonitorCameraList(feeds),
        dualCamPreview = dualCamPreviewActive,
    })
end

local function getIntercomMonitorFeed()
    return getIntercomCallFeed()
end

local function applyFeedToCamera(feed)
    if not feed then return end

    if intercomCam and DoesCamExist(intercomCam) then
        SetCamCoord(intercomCam, feed.x, feed.y, feed.z)
        SetCamRot(intercomCam, feed.pitch, 0.0, feed.heading, 2)
        SetCamFov(intercomCam, feed.fov)
    end
end

local function buildMonitorUiPayload(opts)
    opts = opts or {}
    local feeds = getMonitorFeeds()
    local feedIndex = opts.activeCamera or activeMonitorCamIndex or 1
    local feed = opts.feed or feeds[feedIndex] or feeds[1]
    local onIntercomCall = monitorViewMode == 'intercom'
    local hasPending = opts.hasPendingCall
    if hasPending == nil then
        hasPending = pendingCall ~= nil and not onIntercomCall
    end

    return {
        caller = opts.caller or pendingCall or 'Nessuna chiamata',
        hasPendingCall = hasPending,
        canUnlock = opts.canUnlock == true or onIntercomCall,
        camera = feed and feed.label or 'CAM-01',
        activeCamera = feedIndex,
        cameras = buildMonitorCameraList(feeds),
        lockCameras = onIntercomCall,
        dualCamPreview = opts.dualCamPreview == true or dualCamPreviewActive,
    }
end

local function refreshMonitorUi(opts)
    sendNui('updateIntercom', buildMonitorUiPayload(opts))
end

local function openPoliceMonitor()
    if isViewingCam then return end
    if not isPoliceOnDuty() then
        exports['ss-libs']:Notify('Accesso riservato alla polizia in servizio.', 'error')
        return
    end

    monitorViewMode = 'cctv'
    isViewingCam = true
    hasAnsweredCall = false
    activeMonitorCamIndex = pendingCall and getIntegratedMonitorFeedIndex() or 1

    DoScreenFadeOut(400)
    Wait(400)

    local feed, feeds = getMonitorFeed(activeMonitorCamIndex)
    intercomCam = CreateCamWithParams(
        'DEFAULT_SCRIPTED_CAMERA',
        feed.x, feed.y, feed.z,
        feed.pitch, 0.0, feed.heading,
        feed.fov, false, 0
    )
    SetCamActive(intercomCam, true)
    RenderScriptCams(true, false, 0, true, true)
    SetTimecycleModifier('scanline_cam_cheap')
    SetTimecycleModifierStrength(1.2)
    DoScreenFadeIn(400)

    playIntercomSound('cctvOn')
    sendNui('showPolice', buildMonitorUiPayload({
        hasPendingCall = pendingCall ~= nil,
        activeCamera = activeMonitorCamIndex,
    }))
    sendNui('playSound', { sound = 'cctvOn' })
    setMonitorNuiFocus(true)

    if pendingCall then
        startDualCamPreview()
    end
end

local function activateIntercomCallView(callerName)
    stopDualCamPreview()
    monitorViewMode = 'intercom'
    hasAnsweredCall = true

    local feed = getIntercomCallFeed()
    applyFeedToCamera(feed)

    sendNui('showPolice', buildMonitorUiPayload({
        caller = callerName or 'Sconosciuto',
        answeredName = callerName,
        hasPendingCall = false,
        canUnlock = true,
        feed = feed,
    }))
    setMonitorNuiFocus(true)
    startVoiceInputLoop()
    showPoliceVoiceHint()
end

local function openIntercomCall(callerName)
    if isViewingCam and monitorViewMode == 'intercom' then return end

    if isViewingCam and monitorViewMode == 'cctv' then
        activateIntercomCallView(callerName)
        return
    end

    stopDualCamPreview()
    monitorViewMode = 'intercom'
    isViewingCam = true
    hasAnsweredCall = true
    activeMonitorCamIndex = 1

    DoScreenFadeOut(400)
    Wait(400)

    local feed = getIntercomCallFeed()
    intercomCam = CreateCamWithParams(
        'DEFAULT_SCRIPTED_CAMERA',
        feed.x, feed.y, feed.z,
        feed.pitch, 0.0, feed.heading,
        feed.fov, false, 0
    )
    SetCamActive(intercomCam, true)
    RenderScriptCams(true, false, 0, true, true)
    SetTimecycleModifier('scanline_cam_cheap')
    SetTimecycleModifierStrength(1.2)
    DoScreenFadeIn(400)

    playIntercomSound('cctvOn')
    sendNui('showPolice', buildMonitorUiPayload({
        caller = callerName or 'Sconosciuto',
        answeredName = callerName,
        hasPendingCall = false,
        canUnlock = true,
        feed = feed,
    }))
    sendNui('playSound', { sound = 'cctvOn' })
    setMonitorNuiFocus(true)
    startVoiceInputLoop()
    showPoliceVoiceHint()
end

local function openCctvMonitor()
    openPoliceMonitor()
end

local function spawnSingleCctvProp(index, entry)
    if not entry or isVirtualCctvEntry(entry) or not entry.coords then return false end

    local x, y, z, heading, depth = getCctvPropPlacement(entry)

    if not lib.requestModel(entry.model, 10000) then
        print(('[DMSS_videointercom] CCTV modello non caricato: %s'):format(entry.model))
        return false
    end

    local entity = CreateObject(entry.model, x, y, z, false, false, false)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        SetModelAsNoLongerNeeded(entry.model)
        return false
    end

    SetEntityAsMissionEntity(entity, true, true)
    SetEntityCoordsNoOffset(entity, x, y, z, false, false, false)
    applyEntityRotation(entity, heading, entry.rotation)
    applyEntityDepth(entity, depth)

    local finalPos = GetEntityCoords(entity)
    ResetEntityAlpha(entity)
    SetEntityVisible(entity, true, false)
    SetEntityCollision(entity, false, false)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    SetEntityLodDist(entity, 500)
    linkPropToInterior(entity, finalPos.x, finalPos.y, finalPos.z)
    cctvPropEntities[index] = entity
    SetModelAsNoLongerNeeded(entry.model)

    if Config.Debug then
        print(('[DMSS_videointercom] CCTV [%d] prop a %.2f, %.2f, %.2f'):format(
            index, finalPos.x, finalPos.y, finalPos.z
        ))
    end

    return true
end

local function spawnCctvProps()
    if not Config.UseVisualProp or not Config.CctvProps then return end

    local baseX, baseY, baseZ = getPropBaseCoords()
    waitAreaReady(baseX, baseY, baseZ)

    for i = 1, #Config.CctvProps do
        local entry = Config.CctvProps[i]
        if isVirtualCctvEntry(entry) then
            goto continue_cctv
        end
        if not entry.coords then
            print(('[DMSS_videointercom] CCTV [%d] senza coords in config'):format(i))
        elseif not propEntityExists(cctvPropEntities[i]) then
            spawnSingleCctvProp(i, entry)
        else
            local x, y, z = getCctvPropPlacement(entry)
            linkPropToInterior(cctvPropEntities[i], x, y, z)
        end
        ::continue_cctv::
    end
end

local function arePropsSpawned()
    if not Config.UseVisualProp then return true end
    if not propEntityExists(intercomProp) then return false end
    if not Config.CctvProps then return true end

    for i = 1, #Config.CctvProps do
        local entry = Config.CctvProps[i]
        if isVirtualCctvEntry(entry) or not entry.coords then
            goto continue_spawn_check
        end
        if not propEntityExists(cctvPropEntities[i]) then
            return false
        end
        ::continue_spawn_check::
    end

    return true
end

local function maintainVisualProps()
    if not Config.UseVisualProp or not isNearIntercom() then return end

    spawnProp()
    spawnCctvProps()
end

local function bootstrapProps()
    CreateThread(function()
        local attempts = Config.SpawnMaxAttempts or 15
        local delay = Config.SpawnRetryDelay or 2500

        for _ = 1, attempts do
            if isNearIntercom() then
                maintainVisualProps()
                setupPropZone()

                if arePropsSpawned() then
                    if Config.Debug then
                        print('[DMSS_videointercom] Prop inizializzati correttamente')
                    end
                    return
                end
            end

            Wait(delay)
        end

        if Config.Debug then
            print('[DMSS_videointercom] Bootstrap prop terminato, manutenzione automatica attiva')
        end
    end)
end

local function getCamPosition()
    local feed = getIntercomMonitorFeed()
    return vec4(feed.x, feed.y, feed.z, feed.heading), feed.pitch, feed.fov, feed.label
end

local function getPoliceMonitorCoords()
    local m = Config.PoliceMonitor
    local o = Config.PoliceMonitorOffset or vec3(0.0, 0.0, 0.0)
    local x, y, z = getWorldFromBase(m, o, 0.0)
    return vec3(x, y, z)
end

local function getPoliceMonitorTargetOptions()
    local distance = Config.PoliceMonitorRadius or 2.5
    return {
        {
            name = 'intercom_monitor_cctv',
            icon = 'fa-solid fa-desktop',
            label = 'Apri Monitor Centralino',
            distance = distance,
            onSelect = openPoliceMonitor,
        },
        {
            name = 'intercom_monitor_answer',
            icon = 'fa-solid fa-phone',
            label = 'Rispondi al Citofono',
            distance = distance,
            canInteract = function()
                return pendingCall ~= nil
            end,
            onSelect = answerPoliceCall,
        },
    }
end

local function cleanupPoliceMonitor()
    if not monitorZoneActive then return end
    pcall(function()
        exports.ox_target:removeZone('intercom_police_monitor')
    end)
    monitorZoneActive = false
end

local function setupPoliceMonitor()
    cleanupPoliceMonitor()

    local coords = getPoliceMonitorCoords()
    local radius = Config.PoliceMonitorRadius or 2.5

    exports.ox_target:addSphereZone({
        name = 'intercom_police_monitor',
        coords = coords,
        radius = radius,
        debug = Config.Debug,
        options = getPoliceMonitorTargetOptions(),
    })

    monitorZoneActive = true
end

local function refreshAll()
    deleteProp()
    deleteCctvProps()
    cleanupPoliceMonitor()
    cleanupPropZone()
    setupPoliceMonitor()
    setupPropZone()
    if isNearIntercom() then
        spawnProp()
        spawnCctvProps()
    end
end

local function cleanupIntercom()
    if isViewingCam then closeMonitor(true) end
    closeVisitorUi()
    setMonitorNuiFocus(false)
    stopVoiceInputLoop()
    exitPrivateCallMode()
    hidePoliceVoiceHint()
    voiceCallActive = false
    deleteProp()
    deleteCctvProps()
    cleanupPropZone()
    cleanupPoliceMonitor()
end

-- ── Init ────────────────────────────────────────────────────────────

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    while GetResourceState('ox_target') ~= 'started' do Wait(100) end
    while not cache.ped or cache.ped == 0 do Wait(500) end

    setupPoliceMonitor()
    setupPropZone()
    bootstrapProps()

    while true do
        if Config.UseVisualProp and isNearIntercom() then
            maintainVisualProps()
            Wait(Config.SpawnMaintainInterval or 2000)
        else
            Wait(3000)
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    bootstrapProps()
end)

RegisterNetEvent('qbx_core:client:playerLoaded', function()
    bootstrapProps()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if not NetworkIsSessionStarted() then return end

    CreateThread(function()
        Wait(1500)
        bootstrapProps()
    end)
end)

-- Tasti riaggancia durante chiamata (player libero di muoversi)
CreateThread(function()
    while true do
        if isVisitorUiOpen then
            if IsControlJustPressed(0, 194) or IsControlJustPressed(0, 322) then
                hangUpCall()
            end
            Wait(0)
        else
            Wait(400)
        end
    end
end)

RegisterCommand('intercomrespawn', function()
    deleteProp()
    deleteCctvProps()
    setupPropZone()
    spawnProp()
    spawnCctvProps()
end, false)

RegisterCommand('intercomrefresh', function()
    refreshAll()
    exports['ss-libs']:Notify('Citofono aggiornato', 'success')
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanupIntercom()
end)

RegisterNetEvent('intercom:client:incomingCall', function(callerName)
    pendingCall = callerName
    playIntercomSound('doorbell')
    sendNui('playSound', { sound = 'doorbell' })
    exports['ss-libs']:Notify(('🔔 CITOFONO · %s sta suonando! Apri il monitor e rispondi.'):format(callerName), 'warning', 10000)

    if isViewingCam and monitorViewMode == 'cctv' then
        focusMonitorOnRing(callerName)
    end
end)

RegisterNetEvent('intercom:client:clearPendingCall', function()
    pendingCall = nil
    stopDualCamPreview()

    if isViewingCam and monitorViewMode == 'cctv' then
        refreshMonitorUi({
            caller = 'Nessuna chiamata',
            hasPendingCall = false,
        })
    end
end)
RegisterNetEvent('intercom:client:openMonitor', openIntercomCall)
RegisterNetEvent('intercom:client:closeMonitor', closeMonitor)

RegisterNetEvent('intercom:client:voiceCallStarted', function(channel)
    voiceCallActive = true
    enterPrivateCallMode(channel)
    startVoiceInputLoop()
    if isViewingCam then
        setMonitorNuiFocus(true)
    end
end)

RegisterNetEvent('intercom:client:voiceCallEnded', function()
    voiceCallActive = false
    stopVoiceInputLoop()
    exitPrivateCallMode()
    hidePoliceVoiceHint()
end)

RegisterNetEvent('intercom:client:callAnswered', function()
    visitorCallAnswered = true
    playIntercomSound('answer')
    sendNui('visitorAnswered')
    sendNui('playSound', { sound = 'answer' })
    showVisitorHint()
end)

RegisterNetEvent('intercom:client:callEnded', function()
    playIntercomSound('callEnd')
    sendNui('playSound', { sound = 'callEnd' })
    closeVisitorUi()
end)

RegisterNetEvent('intercom:client:playSound', playIntercomSound)

RegisterNetEvent('intercom:client:forceCloseMonitor', function()
    if not isViewingCam then return end
    playIntercomSound('callEnd')
    closeMonitor(true)
    exports['ss-libs']:Notify('Il visitatore ha riagganciato.', 'inform')
end)

RegisterNetEvent('intercom:client:visitorHungUp', function()
    pendingCall = nil
    if not isViewingCam then
        exports['ss-libs']:Notify('Il visitatore ha riagganciato.', 'inform')
    end
end)

RegisterNUICallback('hangUpCall', function(_, cb) hangUpCall() cb('ok') end)
RegisterNUICallback('unlockDoor', function(_, cb) unlockDoorFromMonitor() cb('ok') end)
RegisterNUICallback('closeMonitor', function(_, cb) playIntercomSound('callEnd') closeMonitor() cb('ok') end)
RegisterNUICallback('answerCall', function(_, cb)
    if not isPoliceOnDuty() then
        exports['ss-libs']:Notify('Accesso riservato alla polizia in servizio.', 'error')
        cb('ok')
        return
    end
    if pendingCall then TriggerServerEvent('intercom:server:answerCall') end
    cb('ok')
end)
RegisterNUICallback('switchCamera', function(data, cb)
    if not isViewingCam then cb('ok') return end
    stopDualCamPreview()
    applyMonitorCamera(tonumber(data.index) or 1)
    cb('ok')
end)
