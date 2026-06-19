local intercomCam = nil
local intercomProp = nil
local isViewingCam = false
local isVisitorUiOpen = false
local visitorCallAnswered = false
local hasAnsweredCall = false
local pendingCall = nil
local monitorZoneActive = false
local propZoneActive = false
local visitorHintActive = false

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
    return playerData.job
        and playerData.job.name == 'police'
        and playerData.job.onduty
end

local function sendNui(action, data)
    SendNUIMessage({
        action = action,
        location = data and data.location,
        caller = data and data.caller,
        camera = data and data.camera,
        canUnlock = data and data.canUnlock,
        sound = data and data.sound,
    })
end

local function showVisitorHint()
    if visitorHintActive then return end
    visitorHintActive = true
    lib.showTextUI('[BACKSPACE] Riaggancia  ·  [ESC] Chiudi chiamata', {
        position = 'bottom-center',
        icon = 'phone-slash',
    })
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

    DoScreenFadeIn(300)

    if not skipServer then
        TriggerServerEvent('intercom:server:monitorClosed')
    end
end

local function unlockDoorFromMonitor()
    if not isViewingCam or not hasAnsweredCall then
        exports.ox_lib:notify({ title = 'Citofono', description = 'Devi prima rispondere al citofono.', type = 'error' })
        return
    end

    TriggerServerEvent('intercom:server:unlockDoor', Config.DoorlockId)
    playIntercomSound('unlock')
    sendNui('playSound', { sound = 'unlock' })
    exports.ox_lib:notify({ title = 'Citofono', description = 'Serratura sbloccata!', type = 'success' })
    closeMonitor()
end

local function openPoliceMonitorMenu()
    if not isPoliceOnDuty() then
        exports.ox_lib:notify({ title = 'Citofono', description = 'Accesso riservato alla polizia in servizio.', type = 'error' })
        return
    end

    local options = {}

    if pendingCall then
        options[#options + 1] = {
            title = 'Rispondi al Citofono',
            description = ('%s sta suonando all\'ingresso'):format(pendingCall),
            icon = 'phone',
            onSelect = function()
                TriggerServerEvent('intercom:server:answerCall')
            end,
        }
    end

    if isViewingCam and hasAnsweredCall then
        options[#options + 1] = {
            title = 'Sblocca Porta',
            description = 'Apri la serratura mentre guardi il feed CCTV',
            icon = 'door-open',
            onSelect = unlockDoorFromMonitor,
        }
        options[#options + 1] = {
            title = 'Chiudi Monitor',
            description = 'Termina la visualizzazione del feed video',
            icon = 'xmark',
            onSelect = function()
                playIntercomSound('callEnd')
                closeMonitor()
            end,
        }
    end

    if #options == 0 then
        options[#options + 1] = {
            title = 'Nessuna chiamata in corso',
            description = 'In attesa di un visitatore al citofono',
            icon = 'bell-slash',
            disabled = true,
        }
    end

    lib.registerContext({
        id = 'intercom_police_station_menu',
        title = 'Monitor Centralino',
        options = options,
    })
    lib.showContext('intercom_police_station_menu')
end

-- ── Prop ────────────────────────────────────────────────────────────

local function getPropCoords()
    local p = Config.IntercomProp
    local o = Config.PropOffset or vec3(0.0, 0.0, 0.0)
    local world = GetOffsetFromCoordAndHeadingInWorldCoords(p.x, p.y, p.z, p.w, o.x, o.y, o.z)
    return world.x, world.y, world.z, p.w
end

local function isNearIntercom()
    local p = Config.IntercomProp
    return #(GetEntityCoords(cache.ped) - vec3(p.x, p.y, p.z)) <= (Config.SpawnDistance or 80.0)
end

local function applyPropRotation(entity, heading)
    local rot = Config.PropRotation or vec3(0.0, 0.0, 0.0)
    if rot.x ~= 0.0 or rot.y ~= 0.0 then
        SetEntityRotation(entity, rot.x, rot.y, heading + rot.z, 2, true)
    else
        SetEntityHeading(entity, heading)
    end
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
    propZoneActive = false
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

local function getIntercomTargetOptions()
    local distance = Config.InteractRadius or 1.2
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
            onSelect = hangUpCall,
        },
    }
end

local function setupPropZone()
    cleanupPropZone()

    local x, y, z = getPropCoords()
    exports.ox_target:addSphereZone({
        name = 'intercom_prop_zone',
        coords = vec3(x, y, z),
        radius = Config.InteractRadius or 1.2,
        debug = Config.Debug,
        options = getIntercomTargetOptions(),
    })
    propZoneActive = true
end

local function spawnProp()
    if not Config.UseVisualProp then return false end
    if intercomProp and DoesEntityExist(intercomProp) then return true end
    if not isNearIntercom() then return false end

    deleteProp()

    local x, y, z, heading = getPropCoords()
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
    ResetEntityAlpha(intercomProp)
    SetEntityVisible(intercomProp, true, false)
    SetEntityCollision(intercomProp, false, false)
    FreezeEntityPosition(intercomProp, true)
    SetEntityInvincible(intercomProp, true)
    SetEntityLodDist(intercomProp, 500)
    linkPropToInterior(intercomProp, x, y, z)
    SetModelAsNoLongerNeeded(Config.IntercomModel)

    if Config.Debug then
        print(('[DMSS_videointercom] Prop spawnato a %.2f, %.2f, %.2f'):format(x, y, z))
    end

    return true
end

local function getCamPosition()
    local x, y, z, heading = getPropCoords()

    if intercomProp and DoesEntityExist(intercomProp) then
        local camPos = GetOffsetFromEntityInWorldCoords(intercomProp, Config.CamOffset.x, Config.CamOffset.y, Config.CamOffset.z)
        return vec4(camPos.x, camPos.y, camPos.z, heading)
    end

    local camWorld = GetOffsetFromCoordAndHeadingInWorldCoords(
        x, y, z, heading,
        Config.CamOffset.x, Config.CamOffset.y, Config.CamOffset.z
    )
    return vec4(camWorld.x, camWorld.y, camWorld.z, heading)
end

local function setupPoliceMonitor()
    if monitorZoneActive then return end

    local m = Config.PoliceMonitor
    local size = Config.PoliceMonitorSize or vec3(0.8, 0.8, 1.2)

    exports.ox_target:addBoxZone({
        name = 'intercom_police_monitor',
        coords = vec3(m.x, m.y, m.z),
        size = size,
        rotation = m.w,
        debug = Config.Debug,
        options = {
            {
                name = 'intercom_monitor_use',
                icon = 'fa-solid fa-desktop',
                label = 'Monitor Centralino',
                canInteract = isPoliceOnDuty,
                onSelect = openPoliceMonitorMenu,
            },
        },
    })

    monitorZoneActive = true
end

local function cleanupPoliceMonitor()
    if not monitorZoneActive then return end
    pcall(function()
        exports.ox_target:removeZone('intercom_police_monitor')
    end)
    monitorZoneActive = false
end

local function openMonitor(callerName, answered)
    if isViewingCam then return end

    isViewingCam = true
    hasAnsweredCall = answered == true

    DoScreenFadeOut(400)
    Wait(400)

    local camPos = getCamPosition()
    intercomCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, 0.0, 0.0, camPos.w, 60.0, false, 0)
    SetCamActive(intercomCam, true)
    RenderScriptCams(true, false, 0, true, true)
    SetTimecycleModifier('scanline_cam_cheap')
    SetTimecycleModifierStrength(1.2)
    DoScreenFadeIn(400)

    playIntercomSound('cctvOn')
    sendNui('showPolice', {
        caller = callerName or 'Sconosciuto',
        camera = Config.CameraLabel,
        canUnlock = hasAnsweredCall,
    })
    sendNui('playSound', { sound = 'cctvOn' })
    SetNuiFocus(true, true)
end

local function refreshAll()
    deleteProp()
    cleanupPoliceMonitor()
    cleanupPropZone()
    setupPoliceMonitor()
    setupPropZone()
    if isNearIntercom() then
        spawnProp()
    end
end

local function cleanupIntercom()
    if isViewingCam then closeMonitor(true) end
    closeVisitorUi()
    SetNuiFocus(false, false)
    deleteProp()
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

    while true do
        if Config.UseVisualProp and isNearIntercom() then
            if not intercomProp or not DoesEntityExist(intercomProp) then
                spawnProp()
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
    setupPropZone()
    spawnProp()
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
        description = ('**%s** sta suonando! Vai al monitor e rispondi.'):format(callerName),
        type = 'warning',
        duration = 10000,
    })
end)

RegisterNetEvent('intercom:client:clearPendingCall', function() pendingCall = nil end)
RegisterNetEvent('intercom:client:openMonitor', openMonitor)
RegisterNetEvent('intercom:client:closeMonitor', closeMonitor)

RegisterNetEvent('intercom:client:callAnswered', function()
    visitorCallAnswered = true
    playIntercomSound('answer')
    sendNui('visitorAnswered')
    sendNui('playSound', { sound = 'answer' })
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
    if pendingCall then TriggerServerEvent('intercom:server:answerCall') end
    cb('ok')
end)
