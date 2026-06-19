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

local function setClientCallChannel(channel)
    if Config.VoiceEnabled == false then return end

    local resource = Config.VoiceResource or 'pma-voice'
    if GetResourceState(resource) ~= 'started' then return end

    pcall(function()
        if channel and channel > 0 then
            exports[resource]:setCallChannel(channel)
        else
            exports[resource]:setCallChannel(0)
        end
    end)
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
            exports.ox_lib:notify({ title = 'Citofono', description = 'Nessuna risposta dal centralino.', type = 'error' })
        end
    end)
end

local function hangUpCall()
    if not isVisitorUiOpen then return end

    TriggerServerEvent('intercom:server:hangUpCall')
    playIntercomSound('callEnd')
    sendNui('playSound', { sound = 'callEnd' })
    closeVisitorUi()
    exports.ox_lib:notify({ title = 'Citofono', description = 'Hai riagganciato.', type = 'inform' })
end

local function closeMonitor(skipServer)
    if not isViewingCam then return end

    sendNui('hidePolice')
    SetNuiFocus(false, false)

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
        exports.ox_lib:notify({ title = 'Citofono', description = 'Devi prima rispondere al citofono.', type = 'error' })
        return
    end

    TriggerServerEvent('intercom:server:unlockDoor', Config.DoorlockId)
    playIntercomSound('unlock')
    sendNui('playSound', { sound = 'unlock' })
    exports.ox_lib:notify({ title = 'Citofono', description = 'Serratura sbloccata!', type = 'success' })
    closeMonitor()
end

local function answerPoliceCall()
    if not isPoliceOnDuty() then
        exports.ox_lib:notify({ title = 'Citofono', description = 'Accesso riservato alla polizia in servizio.', type = 'error' })
        return
    end
    if not pendingCall then
        exports.ox_lib:notify({ title = 'Citofono', description = 'Nessuna chiamata in corso.', type = 'error' })
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
                    exports.ox_lib:notify({ title = 'Citofono', description = 'Hai già suonato, attendi un momento.', type = 'error' })
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
        local deadline = GetGameTimer() + 5000
        while not IsInteriorReady(interior) and GetGameTimer() < deadline do
            Wait(50)
        end
    end

    local deadline = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(cache.ped) and GetGameTimer() < deadline do
        Wait(50)
    end
end

local function linkPropToInterior(entity, x, y, z)
    local interior = GetInteriorAtCoords(x, y, z)
    if interior == 0 then return end

    local room = GetRoomKeyFromEntity(cache.ped)
    if room ~= 0 then
        ForceRoomForEntity(entity, interior, room)
    end
end

local function setupPropZone()
    refreshIntercomTarget()
end

local function spawnProp()
    if not Config.UseVisualProp then return false end
    if intercomProp and DoesEntityExist(intercomProp) then return true end
    if not isNearIntercom() then return false end

    cleanupPropZone()
    deleteProp()

    local x, y, z, heading = getPropBaseCoords()
    waitAreaReady(x, y, z)

    if not lib.requestModel(Config.IntercomModel, 5000) then
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

local function cctvPropsReady()
    if not Config.CctvProps or #Config.CctvProps == 0 then return true end
    for i = 1, #Config.CctvProps do
        local entity = cctvPropEntities[i]
        if not entity or not DoesEntityExist(entity) then
            return false
        end
    end
    return true
end

local function getCctvPropPlacement(entry)
    local base = entry.coords
    local o = entry.propOffset or vec3(0.0, 0.0, 0.0)
    local x, y, z, heading = getWorldFromBase(base, vec3(0.0, o.y, o.z), 0.0)
    return x, y, z, heading, entry.depth or 0.0
end

local function getCctvFeedPlacement(entry)
    if entry.feedView or entry.feedCoords then
        local feed = entry.feedView or entry.feedCoords
        return feed.x, feed.y, feed.z, feed.w
    end

    local base = entry.coords
    local o = entry.feedOffset or vec3(0.0, 0.0, 0.0)
    return getWorldFromBase(base, o, 0.0)
end

local function buildCctvFeed(entry, index)
    local feed = entry.feedView or entry.feedCoords
    if feed or entry.feedOffset then
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
    }
end

local function refreshMonitorUi(opts)
    sendNui('updateIntercom', buildMonitorUiPayload(opts))
end

local function openPoliceMonitor()
    if isViewingCam then return end
    if not isPoliceOnDuty() then
        exports.ox_lib:notify({ title = 'Citofono', description = 'Accesso riservato alla polizia in servizio.', type = 'error' })
        return
    end

    monitorViewMode = 'cctv'
    isViewingCam = true
    hasAnsweredCall = false
    activeMonitorCamIndex = 1

    DoScreenFadeOut(400)
    Wait(400)

    local feed, feeds = getMonitorFeed(1)
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
    }))
    sendNui('playSound', { sound = 'cctvOn' })
    SetNuiFocus(true, true)
end

local function activateIntercomCallView(callerName)
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
    showPoliceVoiceHint()
end

local function openIntercomCall(callerName)
    if isViewingCam and monitorViewMode == 'intercom' then return end

    if isViewingCam and monitorViewMode == 'cctv' then
        activateIntercomCallView(callerName)
        return
    end

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
    SetNuiFocus(true, true)
    showPoliceVoiceHint()
end

local function openCctvMonitor()
    openPoliceMonitor()
end

local function spawnCctvProps()
    if not Config.UseVisualProp or not Config.CctvProps then return end

    deleteCctvProps()

    for i = 1, #Config.CctvProps do
        local entry = Config.CctvProps[i]
        if not entry.coords then
            print(('[DMSS_videointercom] CCTV [%d] senza coords in config'):format(i))
        else
            local x, y, z, heading, depth = getCctvPropPlacement(entry)

            if lib.requestModel(entry.model, 5000) then
                local entity = CreateObject(entry.model, x, y, z, false, false, false)
                if entity and entity ~= 0 and DoesEntityExist(entity) then
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
                    cctvPropEntities[i] = entity

                    if Config.Debug then
                        print(('[DMSS_videointercom] CCTV [%d] prop a %.2f, %.2f, %.2f'):format(
                            i, finalPos.x, finalPos.y, finalPos.z
                        ))
                    end
                end
                SetModelAsNoLongerNeeded(entry.model)
            else
                print(('[DMSS_videointercom] CCTV modello non caricato: %s'):format(entry.model))
            end
        end
    end
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
    SetNuiFocus(false, false)
    setClientCallChannel(0)
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

    if isNearIntercom() then
        spawnProp()
        spawnCctvProps()
    end

    while true do
        if Config.UseVisualProp and isNearIntercom() then
            if not intercomProp or not DoesEntityExist(intercomProp) then
                spawnProp()
            end
            if not cctvPropsReady() then
                spawnCctvProps()
            end
            Wait(2000)
        else
            Wait(3000)
        end
    end
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
    exports.ox_lib:notify({ title = 'Citofono', description = 'Citofono aggiornato', type = 'success' })
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanupIntercom()
end)

RegisterNetEvent('intercom:client:incomingCall', function(callerName)
    pendingCall = callerName
    playIntercomSound('doorbell')
    sendNui('playSound', { sound = 'doorbell' })
    exports.ox_lib:notify({
        title = '🔔 CITOFONO CENTRALINO',
        description = ('**%s** sta suonando! Apri il monitor e rispondi.'):format(callerName),
        type = 'warning',
        duration = 10000,
    })

    if isViewingCam and monitorViewMode == 'cctv' then
        refreshMonitorUi({
            caller = callerName,
            hasPendingCall = true,
        })
    end
end)

RegisterNetEvent('intercom:client:clearPendingCall', function()
    pendingCall = nil

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
    setClientCallChannel(channel)
end)

RegisterNetEvent('intercom:client:voiceCallEnded', function()
    voiceCallActive = false
    setClientCallChannel(0)
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
    exports.ox_lib:notify({ title = 'Citofono', description = 'Il visitatore ha riagganciato.', type = 'inform' })
end)

RegisterNetEvent('intercom:client:visitorHungUp', function()
    pendingCall = nil
    if not isViewingCam then
        exports.ox_lib:notify({ title = 'Citofono', description = 'Il visitatore ha riagganciato.', type = 'inform' })
    end
end)

RegisterNUICallback('hangUpCall', function(_, cb) hangUpCall() cb('ok') end)
RegisterNUICallback('unlockDoor', function(_, cb) unlockDoorFromMonitor() cb('ok') end)
RegisterNUICallback('closeMonitor', function(_, cb) playIntercomSound('callEnd') closeMonitor() cb('ok') end)
RegisterNUICallback('answerCall', function(_, cb)
    if not isPoliceOnDuty() then
        exports.ox_lib:notify({ title = 'Citofono', description = 'Accesso riservato alla polizia in servizio.', type = 'error' })
        cb('ok')
        return
    end
    if pendingCall then TriggerServerEvent('intercom:server:answerCall') end
    cb('ok')
end)
RegisterNUICallback('switchCamera', function(data, cb)
    if not isViewingCam then cb('ok') return end
    applyMonitorCamera(tonumber(data.index) or 1)
    cb('ok')
end)
