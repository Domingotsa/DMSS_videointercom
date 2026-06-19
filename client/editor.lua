local editorMode = nil
local editorBackup = nil
local editorEntity = nil
local editorDragging = false
local lastHitCoords = nil

local SCROLL_STEP = 0.05
local ROTATE_STEP = 2.0

local function sendEditorNui(action, data)
    SendNUIMessage({ action = action, text = data and data.text, mode = data and data.mode })
end

local function setEditorFocus(state)
    SetNuiFocus(state, state)
    SetNuiFocusKeepInput(false)
end

local function formatPropConfig()
    local p = Config.IntercomProp
    local o = Config.PropOffset
    return ([[
Config.IntercomProp = vec4(%.4f, %.4f, %.4f, %.4f)
Config.PropOffset = vec3(%.4f, %.4f, %.4f)]]):format(p.x, p.y, p.z, p.w, o.x, o.y, o.z)
end

local function formatMonitorConfig()
    local m = Config.PoliceMonitor
    return ([[Config.PoliceMonitor = vec4(%.4f, %.4f, %.4f, %.4f)]]):format(m.x, m.y, m.z, m.w)
end

local function exportConfig(mode)
    local text = mode == 'monitor' and formatMonitorConfig() or formatPropConfig()
    print('========== DMSS INTERCOM EDITOR ==========')
    print(text)
    print('==========================================')
    if lib.setClipboard then lib.setClipboard(text) end
    lib.notify({ title = 'Editor', description = 'Config in F8 e appunti', type = 'success' })
end

local function worldToPropOffset(worldX, worldY, worldZ)
    local p = Config.IntercomProp
    local h = math.rad(p.w)
    local cosH, sinH = math.cos(h), math.sin(h)
    local relX, relY, relZ = worldX - p.x, worldY - p.y, worldZ - p.z
    return vec3(relX * cosH + relY * sinH, -relX * sinH + relY * cosH, relZ)
end

local function headingFromNormal(normal)
    if not normal then return Config.IntercomProp.w end
    return (math.deg(math.atan(-normal.x, -normal.y)) + 360.0) % 360.0
end

local function deleteEditorEntity()
    if editorEntity and DoesEntityExist(editorEntity) then DeleteEntity(editorEntity) end
    editorEntity = nil
end

local function rotationToDirection(rot)
    local rotX, rotZ = math.rad(rot.x), math.rad(rot.z)
    return vec3(-math.sin(rotZ) * math.abs(math.cos(rotX)), math.cos(rotZ) * math.abs(math.cos(rotX)), math.sin(rotX))
end

local function raycastFromScreen(screenX, screenY, maxDistance, ignoreEntity)
    maxDistance = maxDistance or 25.0
    local camCoord = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local fov = GetGameplayCamFov()
    local resX, resY = GetActiveScreenResolution()
    local relX = (screenX / resX - 0.5) * 2.0
    local relY = (0.5 - screenY / resY) * 2.0
    local tanFov = math.tan(math.rad(fov * 0.5))
    local forward = rotationToDirection(camRot)
    local right = vec3(forward.y, -forward.x, 0.0)
    local up = vec3(right.y * forward.z - right.z * forward.y, right.z * forward.x - right.x * forward.z, right.x * forward.y - right.y * forward.x)
    local direction = forward + right * relX * tanFov * (resX / resY) + up * relY * tanFov
    direction = direction / #direction
    local dest = camCoord + direction * maxDistance
    local handle = StartShapeTestLosProbe(camCoord.x, camCoord.y, camCoord.z, dest.x, dest.y, dest.z, 1, ignoreEntity or 0, 4)
    local status = 1
    local hit, endCoords, surfaceNormal
    while status == 1 do
        Wait(0)
        status, hit, endCoords, surfaceNormal = GetShapeTestResult(handle)
    end
    return hit == 1 or hit == true, endCoords, surfaceNormal
end

local function updateEditorPreview()
    if not editorEntity or not DoesEntityExist(editorEntity) then return end
    local x, y, z, heading = EditorAPI.getPropCoords()
    SetEntityCoordsNoOffset(editorEntity, x, y, z, false, false, false)
    EditorAPI.applyPropRotation(editorEntity, heading)
end

local function spawnEditorProp()
    deleteEditorEntity()
    EditorAPI.deleteProp()
    if not lib.requestModel(Config.IntercomModel, 5000) then return false end
    local x, y, z, heading = EditorAPI.getPropCoords()
    editorEntity = CreateObject(Config.IntercomModel, x, y, z, false, false, false)
    if not editorEntity or not DoesEntityExist(editorEntity) then return false end
    SetEntityAsMissionEntity(editorEntity, true, true)
    SetEntityCoordsNoOffset(editorEntity, x, y, z, false, false, false)
    EditorAPI.applyPropRotation(editorEntity, heading)
    FreezeEntityPosition(editorEntity, true)
    SetEntityAlpha(editorEntity, 220, false)
    return true
end

local function placePropAtWorld(wx, wy, wz, normal, updateHeading)
    if updateHeading and normal then
        local p = Config.IntercomProp
        Config.IntercomProp = vec4(p.x, p.y, p.z, headingFromNormal(normal))
    end
    Config.PropOffset = worldToPropOffset(wx, wy, wz)
    updateEditorPreview()
end

local function applyPointerHit(screenX, screenY, updateHeading)
    local hit, coords, normal = raycastFromScreen(screenX, screenY, 30.0, editorEntity or cache.ped)
    if not hit or not coords then
        sendEditorNui('editorHitLabel', { text = 'Nessuna superficie' })
        return false
    end
    local wx, wy, wz = coords.x + (normal.x * 0.03), coords.y + (normal.y * 0.03), coords.z + (normal.z * 0.03)
    lastHitCoords = vec3(wx, wy, wz)
    if editorMode == 'monitor' then
        Config.PoliceMonitor = vec4(wx, wy, wz, updateHeading and headingFromNormal(normal) or Config.PoliceMonitor.w)
    else
        placePropAtWorld(wx, wy, wz, normal, updateHeading)
    end
    sendEditorNui('editorHitLabel', { text = ('%.2f, %.2f, %.2f'):format(wx, wy, wz) })
    return true
end

local function stopEditor(revert)
    if revert and editorBackup then
        Config.IntercomProp = editorBackup.IntercomProp
        Config.PropOffset = editorBackup.PropOffset
        Config.PoliceMonitor = editorBackup.PoliceMonitor
    end
    editorDragging = false
    lastHitCoords = nil
    deleteEditorEntity()
    editorMode = nil
    editorBackup = nil
    EditorAPI.setEditorActive(false)
    setEditorFocus(false)
    lib.hideTextUI()
    sendEditorNui('hideEditor')
    EditorAPI.refreshAll()
end

local function saveEditor()
    exportConfig(editorMode)
    editorBackup = nil
    deleteEditorEntity()
    editorMode = nil
    EditorAPI.setEditorActive(false)
    setEditorFocus(false)
    lib.hideTextUI()
    sendEditorNui('hideEditor')
    EditorAPI.refreshAll()
end

local function snapEditorToWall()
    if editorMode ~= 'prop' then return end

    local resX, resY = GetActiveScreenResolution()
    local hit, coords, normal = raycastFromScreen(resX * 0.5, resY * 0.5, 30.0, editorEntity or cache.ped)
    if not hit or not coords or not normal then
        lib.notify({ title = 'Editor', description = 'Nessun muro inquadrato al centro', type = 'error' })
        return
    end

    local wx = coords.x + (normal.x * 0.03)
    local wy = coords.y + (normal.y * 0.03)
    local wz = coords.z + (normal.z * 0.03)
    lastHitCoords = vec3(wx, wy, wz)
    placePropAtWorld(wx, wy, wz, normal, true)
    sendEditorNui('editorHitLabel', { text = ('%.2f, %.2f, %.2f'):format(wx, wy, wz) })
    lib.notify({ title = 'Editor', description = ('Snap muro: %.2f, %.2f, %.2f'):format(wx, wy, wz), type = 'success' })
end

local function showEditorHelp(mode)
    local text = mode == 'monitor'
        and '[Click] Posiziona  [Trascina] Sposta  [Rotella] Altezza  [Shift+Rotella] Ruota'
        or '[Click] Sul muro  [Trascina] Sposta  [Rotella] Altezza  [Click destro] Base qui'
    lib.showTextUI(text, { position = 'right-center', icon = 'mouse-pointer' })
end

local function editorPreviewLoop()
    while editorMode do
        Wait(0)
        if lastHitCoords then
            DrawMarker(28, lastHitCoords.x, lastHitCoords.y, lastHitCoords.z, 0,0,0,0,0,0, 0.1,0.1,0.1, 0,220,255,180, false,false,2,false,nil,nil,false)
        end
        if editorMode == 'monitor' then
            local m = Config.PoliceMonitor
            DrawMarker(1, m.x, m.y, m.z - 1.0, 0,0,0,0,0,0, 0.8,0.8,1.2, 255,100,100,120, false,false,2,false,nil,nil,false)
        end
    end
end

local function startEditor(mode)
    if editorMode then return end
    editorBackup = {
        IntercomProp = vec4(Config.IntercomProp.x, Config.IntercomProp.y, Config.IntercomProp.z, Config.IntercomProp.w),
        PropOffset = vec3(Config.PropOffset.x, Config.PropOffset.y, Config.PropOffset.z),
        PoliceMonitor = vec4(Config.PoliceMonitor.x, Config.PoliceMonitor.y, Config.PoliceMonitor.z, Config.PoliceMonitor.w),
    }
    EditorAPI.setEditorActive(true)
    editorMode = mode
    if mode == 'prop' and not spawnEditorProp() then stopEditor(true) return end
    showEditorHelp(mode)
    sendEditorNui('showEditor', { mode = mode })
    setEditorFocus(true)
    CreateThread(editorPreviewLoop)
end

RegisterNUICallback('editorPointer', function(data, cb)
    if not editorMode then cb('ok') return end
    if data.type == 'move' then
        local hit, coords, normal = raycastFromScreen(data.x, data.y, 30.0, editorEntity or cache.ped)
        if hit and coords then
            lastHitCoords = vec3(coords.x + normal.x * 0.03, coords.y + normal.y * 0.03, coords.z + normal.z * 0.03)
        end
        if data.dragging then applyPointerHit(data.x, data.y, false) end
    elseif data.type == 'down' then
        if data.button == 2 and editorMode == 'prop' then
            local ped = cache.ped
            local c = GetEntityCoords(ped)
            Config.IntercomProp = vec4(c.x, c.y, c.z, GetEntityHeading(ped))
            Config.PropOffset = vec3(0.08, 0.0, 1.1)
            updateEditorPreview()
        elseif data.button == 0 then
            editorDragging = true
            applyPointerHit(data.x, data.y, true)
        end
    elseif data.type == 'up' and data.button == 0 then
        editorDragging = false
    elseif data.type == 'scroll' then
        if editorMode == 'prop' then
            if data.shift then
                local p = Config.IntercomProp
                Config.IntercomProp = vec4(p.x, p.y, p.z, (p.w + (data.delta > 0 and -ROTATE_STEP or ROTATE_STEP)) % 360)
            else
                local o = Config.PropOffset
                Config.PropOffset = vec3(o.x, o.y, o.z + (data.delta > 0 and -SCROLL_STEP or SCROLL_STEP))
            end
            updateEditorPreview()
        else
            local m = Config.PoliceMonitor
            if data.shift then
                Config.PoliceMonitor = vec4(m.x, m.y, m.z, (m.w + (data.delta > 0 and -ROTATE_STEP or ROTATE_STEP)) % 360)
            else
                Config.PoliceMonitor = vec4(m.x, m.y, m.z + (data.delta > 0 and -SCROLL_STEP or SCROLL_STEP), m.w)
            end
        end
    end
    cb('ok')
end)

RegisterNUICallback('editorAction', function(data, cb)
    if editorMode then
        if data.action == 'save' then saveEditor()
        elseif data.action == 'cancel' then stopEditor(true)
        elseif data.action == 'snap' then snapEditorToWall() end
    end
    cb('ok')
end)

local function openEditorMenu()
    lib.registerContext({
        id = 'dmss_intercom_editor',
        title = 'Editor Citofono DMSS',
        options = {
            { title = 'Editor Prop (mouse)', icon = 'bell', onSelect = function() startEditor('prop') end },
            { title = 'Editor Monitor (mouse)', icon = 'desktop', onSelect = function() startEditor('monitor') end },
            { title = 'Esporta config', icon = 'copy', onSelect = function() exportConfig('prop') exportConfig('monitor') end },
        },
    })
    lib.showContext('dmss_intercom_editor')
end

RegisterNetEvent('intercom:client:openEditor', openEditorMenu)
RegisterCommand('intercomeditor', function() TriggerServerEvent('intercom:server:requestEditor') end, false)
