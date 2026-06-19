local intercomCam = nil
local intercomProp = nil
local isViewingCam = false
local isVisitorUiOpen = false
local hasAnsweredCall = false
local pendingCall = nil

local Config = {
    IntercomProp = vec4(5629.6636, -3136.2673, 12.1455, 275.2273),
    IntercomModel = `hei_prop_hei_keypad_03`,
    -- Monitor polizia: punto dove aprire il menu (regola se serve)
    PoliceMonitor = vec4(5627.8, -3135.5, 12.1455, 275.0),
    CamOffset = vec3(0.5, -2.8, 1.6),
    DoorlockId = 1,
    LocationLabel = 'Centralino',
    CameraLabel = 'CAM-01 · INGRESSO PRINCIPALE',
    VisitorTimeout = 60000,
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
    return playerData.job
        and playerData.job.name == 'police'
        and playerData.job.onduty
end

local function getCamPosition()
    if intercomProp and DoesEntityExist(intercomProp) then
        local camPos = GetOffsetFromEntityInWorldCoords(intercomProp, Config.CamOffset.x, Config.CamOffset.y, Config.CamOffset.z)
        return vec4(camPos.x, camPos.y, camPos.z, Config.IntercomProp.w)
    end

    return vec4(
        Config.IntercomProp.x + Config.CamOffset.x,
        Config.IntercomProp.y + Config.CamOffset.y,
        Config.IntercomProp.z + Config.CamOffset.z,
        Config.IntercomProp.w
    )
end

local function sendNui(action, data)
    SendNUIMessage({
        action = action,
        location = data and data.location,
        caller = data and data.caller,
        camera = data and data.camera,
        canUnlock = data and data.canUnlock,
    })
end

local function openVisitorUi()
    if isVisitorUiOpen then return end
    isVisitorUiOpen = true

    playIntercomSound('ring')
    sendNui('showVisitor', { location = Config.LocationLabel })
    sendNui('playSound', { sound = 'ring' })

    SetTimeout(Config.VisitorTimeout, function()
        if isVisitorUiOpen then
            closeVisitorUi()
            TriggerServerEvent('intercom:server:callTimeout')
            playIntercomSound('callEnd')
            exports.ox_lib:notify({ title = 'Citofono', description = 'Nessuna risposta dal centralino.', type = 'error' })
        end
    end)
end

local function closeVisitorUi()
    if not isVisitorUiOpen then return end
    isVisitorUiOpen = false
    sendNui('hideVisitor')
end

local function closeMonitor()
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
    TriggerServerEvent('intercom:server:monitorClosed')
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

local function spawnIntercomProp()
    lib.requestModel(Config.IntercomModel)

    local coords = Config.IntercomProp
    intercomProp = CreateObject(Config.IntercomModel, coords.x, coords.y, coords.z, false, false, false)

    SetEntityHeading(intercomProp, coords.w)
    FreezeEntityPosition(intercomProp, true)
    SetEntityInvincible(intercomProp, true)

    exports.ox_target:addLocalEntity(intercomProp, {
        {
            name = 'intercom_ring',
            icon = 'fa-solid fa-bell',
            label = 'Suona Citofono',
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
    })
end

local function setupPoliceMonitor()
    local monitor = Config.PoliceMonitor

    exports.ox_target:addBoxZone({
        name = 'intercom_police_monitor',
        coords = vec3(monitor.x, monitor.y, monitor.z),
        size = vec3(1.2, 1.2, 1.5),
        rotation = monitor.w,
        debug = false,
        options = {
            {
                name = 'intercom_monitor_use',
                icon = 'fa-solid fa-desktop',
                label = 'Monitor Centralino',
                canInteract = function()
                    return isPoliceOnDuty()
                end,
                onSelect = openPoliceMonitorMenu,
            },
        },
    })
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

CreateThread(function()
    spawnIntercomProp()
    setupPoliceMonitor()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    if intercomProp and DoesEntityExist(intercomProp) then
        exports.ox_target:removeLocalEntity(intercomProp)
        DeleteEntity(intercomProp)
        intercomProp = nil
    end
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

RegisterNetEvent('intercom:client:clearPendingCall', function()
    pendingCall = nil
end)

RegisterNetEvent('intercom:client:openMonitor', function(callerName, answered)
    openMonitor(callerName, answered)
end)

RegisterNetEvent('intercom:client:closeMonitor', closeMonitor)

RegisterNetEvent('intercom:client:callAnswered', function()
    playIntercomSound('answer')
    sendNui('visitorAnswered')
    sendNui('playSound', { sound = 'answer' })
end)

RegisterNetEvent('intercom:client:callEnded', function()
    playIntercomSound('callEnd')
    sendNui('playSound', { sound = 'callEnd' })
    closeVisitorUi()
end)

RegisterNetEvent('intercom:client:playSound', function(soundKey)
    playIntercomSound(soundKey)
end)

RegisterNUICallback('unlockDoor', function(_, cb)
    unlockDoorFromMonitor()
    cb('ok')
end)

RegisterNUICallback('closeMonitor', function(_, cb)
    playIntercomSound('callEnd')
    closeMonitor()
    cb('ok')
end)

RegisterNUICallback('answerCall', function(_, cb)
    if pendingCall then
        TriggerServerEvent('intercom:server:answerCall')
    end
    cb('ok')
end)
