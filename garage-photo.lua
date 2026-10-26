-- Modo local para capturar imagens padronizadas dos veiculos do catalogo.
-- /fotocar <spawn> cria um veiculo temporario; /fotocar sem argumento usa
-- o veiculo atual. ESC ou /fotocaroff encerra a captura.

local photoMode = false
local photoCamera = nil
local photoVehicle = nil
local spawnedForPhoto = false
local previousVehicleState = nil
local playerSnapshot = nil
local previousRadarState = true
local photoFocusActive = false
local garagePreview = {
    active = false,
    generation = 0,
    vehicle = nil,
    camera = nil,
    retiredVehicles = {},
    playerSnapshot = nil,
    focusActive = false,
    previousRadarState = true
}

-- Trecho aberto de Fort Zancudo usado como ponto fixo das capturas.
local PHOTO_SPAWN = vector4(-2243.3835, 3214.0742, 32.8102, 0.0)

local function notifyPhotoHelp(message)
    print(('[apexnui:garage-photo] %s'):format(message))
end

local function loadPhotoModel(modelName, previewGeneration)
    local model = type(modelName) == 'number' and modelName or joaat(modelName)
    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then
        return nil
    end

    RequestModel(model)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(model) and GetGameTimer() < timeout
        and (previewGeneration == nil or previewGeneration == garagePreview.generation) do
        Wait(0)
    end

    if not HasModelLoaded(model) or (previewGeneration ~= nil and previewGeneration ~= garagePreview.generation) then
        SetModelAsNoLongerNeeded(model)
        return nil
    end
    return model
end

local function sendGaragePreviewStatus(active, model, message)
    SendNUIMessage({
        action = 'apexGaragePreviewStatus',
        active = active == true,
        model = model or '',
        message = message or ''
    })
end

local function deletePreviewVehicle(vehicle)
    if vehicle and DoesEntityExist(vehicle) then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteEntity(vehicle)
    end
end

local function stopGaragePreview(instant)
    garagePreview.generation = garagePreview.generation + 1
    local hadPreview = garagePreview.active or garagePreview.vehicle or garagePreview.camera or garagePreview.playerSnapshot
    garagePreview.active = false

    if garagePreview.camera then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(garagePreview.camera, false)
        garagePreview.camera = nil
    end

    deletePreviewVehicle(garagePreview.vehicle)
    garagePreview.vehicle = nil
    for _, vehicle in ipairs(garagePreview.retiredVehicles) do
        deletePreviewVehicle(vehicle)
    end
    garagePreview.retiredVehicles = {}

    if garagePreview.focusActive then
        ClearFocus()
        garagePreview.focusActive = false
    end

    if garagePreview.playerSnapshot then
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, garagePreview.playerSnapshot.frozen)
        SetEntityVisible(ped, garagePreview.playerSnapshot.visible, false)
        SetEntityCollision(ped, garagePreview.playerSnapshot.collision, true)
        garagePreview.playerSnapshot = nil
    end

    if hadPreview then
        DisplayRadar(garagePreview.previousRadarState)
        sendGaragePreviewStatus(false, '', 'PRÉVIA ENCERRADA')
    end
end

local function previewGarageVehicle(modelName)
    local cleanedModel = type(modelName) == 'string' and modelName:match('^[%w_%-]+$') and modelName or nil
    if not cleanedModel then
        sendGaragePreviewStatus(false, '', 'MODELO INVÁLIDO')
        return
    end

    garagePreview.generation = garagePreview.generation + 1
    local generation = garagePreview.generation
    sendGaragePreviewStatus(false, cleanedModel, 'CARREGANDO VEÍCULO')

    CreateThread(function()
        local model = loadPhotoModel(cleanedModel, generation)
        if not model then
            if garagePreview.generation == generation then
                stopGaragePreview(true)
                sendGaragePreviewStatus(false, cleanedModel, 'PRÉVIA INDISPONÍVEL — MOSTRANDO IMAGEM')
            end
            return
        end

        if garagePreview.generation ~= generation then
            SetModelAsNoLongerNeeded(model)
            return
        end

        local position = vector3(PHOTO_SPAWN.x, PHOTO_SPAWN.y, PHOTO_SPAWN.z)
        if not garagePreview.playerSnapshot then
            local ped = PlayerPedId()
            garagePreview.playerSnapshot = {
                frozen = IsEntityPositionFrozen(ped),
                visible = IsEntityVisible(ped),
                collision = GetEntityCollisionDisabled(ped) == false
            }
            garagePreview.previousRadarState = IsRadarEnabled()
            FreezeEntityPosition(ped, true)
            SetEntityVisible(ped, false, false)
            SetEntityCollision(ped, false, false)
            DisplayRadar(false)
        end

        if not garagePreview.focusActive then
            SetFocusPosAndVel(position.x, position.y, position.z, 0.0, 0.0, 0.0)
            garagePreview.focusActive = true
        end
        RequestCollisionAtCoord(position.x, position.y, position.z)
        Wait(120)

        if garagePreview.generation ~= generation then
            SetModelAsNoLongerNeeded(model)
            return
        end

        local foundGround, groundZ = GetGroundZFor_3dCoord(position.x, position.y, position.z + 20.0, false)
        if foundGround then
            position = vector3(position.x, position.y, groundZ + 0.15)
        end

        if garagePreview.vehicle and DoesEntityExist(garagePreview.vehicle) then
            SetEntityVisible(garagePreview.vehicle, false, false)
        end
        local vehicle = CreateVehicle(model, position.x, position.y, position.z, PHOTO_SPAWN.w, false, false)
        SetModelAsNoLongerNeeded(model)
        if not DoesEntityExist(vehicle) then
            if garagePreview.generation == generation then
                stopGaragePreview(true)
                sendGaragePreviewStatus(false, cleanedModel, 'PRÉVIA INDISPONÍVEL — MOSTRANDO IMAGEM')
            end
            return
        end

        SetEntityAsMissionEntity(vehicle, true, true)
        SetVehicleOnGroundProperly(vehicle)
        SetVehicleDirtLevel(vehicle, 0.0)
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleDoorsLocked(vehicle, 2)
        SetEntityInvincible(vehicle, true)
        FreezeEntityPosition(vehicle, true)

        if garagePreview.generation ~= generation then
            deletePreviewVehicle(vehicle)
            return
        end

        local minimum, maximum = GetModelDimensions(model)
        local width = math.max(1.8, maximum.x - minimum.x)
        local length = math.max(3.5, maximum.y - minimum.y)
        local height = math.max(1.4, maximum.z - minimum.z)
        local cameraPosition = GetOffsetFromEntityInWorldCoords(vehicle, (minimum.x + maximum.x) * 0.5 + width * 1.75, maximum.y + length * 0.72, minimum.z + height * 0.82)
        local targetPosition = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, minimum.z + height * 0.48)
        local camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamCoord(camera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
        PointCamAtCoord(camera, targetPosition.x, targetPosition.y, targetPosition.z)
        SetCamFov(camera, 38.0)
        SetCamActive(camera, true)

        local oldVehicle = garagePreview.vehicle
        local oldCamera = garagePreview.camera
        for _, retiredVehicle in ipairs(garagePreview.retiredVehicles) do
            deletePreviewVehicle(retiredVehicle)
        end
        garagePreview.retiredVehicles = {}
        garagePreview.vehicle = vehicle
        garagePreview.camera = camera
        garagePreview.active = true

        if oldCamera and DoesCamExist(oldCamera) then
            SetCamActiveWithInterp(camera, oldCamera, 520, 1, 1)
            Wait(560)
            DestroyCam(oldCamera, false)
            deletePreviewVehicle(oldVehicle)
        else
            RenderScriptCams(true, false, 0, true, true)
        end

        if garagePreview.generation == generation then
            sendGaragePreviewStatus(true, cleanedModel, 'PRÉVIA AO VIVO  /  ESCOLHA UM VEÍCULO')
        end
    end)
end

RegisterNetEvent('apexnui:previewGarageVehicle', previewGarageVehicle)
RegisterNetEvent('apexnui:stopGaragePreview', stopGaragePreview)

CreateThread(function()
    while true do
        if not garagePreview.active then
            Wait(250)
        else
            Wait(0)
            HideHudAndRadarThisFrame()
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 75, true)
        end
    end
end)

local function createPhotoVehicle(modelName)
    local model = loadPhotoModel(modelName)
    if not model then
        notifyPhotoHelp(('Nao foi possivel carregar o spawn "%s".'):format(modelName))
        return nil
    end

    local position = vector3(PHOTO_SPAWN.x, PHOTO_SPAWN.y, PHOTO_SPAWN.z)
    SetFocusPosAndVel(position.x, position.y, position.z, 0.0, 0.0, 0.0)
    photoFocusActive = true
    RequestCollisionAtCoord(position.x, position.y, position.z)
    Wait(500)
    local foundGround, groundZ = GetGroundZFor_3dCoord(position.x, position.y, position.z + 20.0, false)
    if foundGround then
        position = vector3(position.x, position.y, groundZ + 0.15)
    end

    local vehicle = CreateVehicle(model, position.x, position.y, position.z, PHOTO_SPAWN.w, false, false)
    SetModelAsNoLongerNeeded(model)
    if not DoesEntityExist(vehicle) then
        ClearFocus()
        photoFocusActive = false
        notifyPhotoHelp('Falha ao criar o veiculo temporario.')
        return nil
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    return vehicle
end

local function stopPhotoMode()
    if not photoMode then return end
    photoMode = false

    if photoCamera then
            RenderScriptCams(false, true, 300, true, true)
        DestroyCam(photoCamera, false)
        photoCamera = nil
    end
    if photoFocusActive then
        ClearFocus()
        photoFocusActive = false
    end

    if photoVehicle and DoesEntityExist(photoVehicle) then
        if spawnedForPhoto then
            DeleteEntity(photoVehicle)
        elseif previousVehicleState then
            FreezeEntityPosition(photoVehicle, previousVehicleState.frozen)
            SetVehicleEngineOn(photoVehicle, previousVehicleState.engineOn, true, true)
        end
    end
    photoVehicle = nil
    spawnedForPhoto = false
    previousVehicleState = nil

    if playerSnapshot then
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, playerSnapshot.frozen)
        SetEntityVisible(ped, playerSnapshot.visible, false)
        SetEntityCollision(ped, playerSnapshot.collision, true)
        playerSnapshot = nil
    end
    DisplayRadar(previousRadarState)
end

local function startPhotoMode(vehicle, wasSpawned)
    if not DoesEntityExist(vehicle) then return end

    local ped = PlayerPedId()
    photoVehicle = vehicle
    spawnedForPhoto = wasSpawned
    if not wasSpawned then
        previousVehicleState = {
            frozen = IsEntityPositionFrozen(vehicle),
            engineOn = GetIsVehicleEngineRunning(vehicle)
        }
    end

    playerSnapshot = {
        frozen = IsEntityPositionFrozen(ped),
        visible = IsEntityVisible(ped),
        collision = GetEntityCollisionDisabled(ped) == false
    }
    previousRadarState = IsRadarEnabled()

    FreezeEntityPosition(vehicle, true)
    SetVehicleEngineOn(vehicle, false, true, true)
    SetVehicleDoorsLocked(vehicle, 2)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    DisplayRadar(false)

    local minimum, maximum = GetModelDimensions(GetEntityModel(vehicle))
    local width = math.max(1.8, maximum.x - minimum.x)
    local length = math.max(3.5, maximum.y - minimum.y)
    local height = math.max(1.4, maximum.z - minimum.z)
    local localCamX = (minimum.x + maximum.x) * 0.5 + width * 2.0
    local localCamY = maximum.y + length * 0.65
    local localCamZ = minimum.z + height * 0.85
    local cameraPosition = GetOffsetFromEntityInWorldCoords(vehicle, localCamX, localCamY, localCamZ)
    local targetPosition = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, minimum.z + height * 0.48)

    photoCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(photoCamera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
    PointCamAtCoord(photoCamera, targetPosition.x, targetPosition.y, targetPosition.z)
    SetCamFov(photoCamera, 38.0)
    SetCamActive(photoCamera, true)
    RenderScriptCams(true, true, 500, true, true)

    photoMode = true
    notifyPhotoHelp('Captura ativa. Tire a foto manualmente; pressione ESC para sair.')
end

RegisterCommand('fotocar', function(_, args)
    if photoMode then stopPhotoMode() end

    local modelName = args[1]
    if modelName and modelName ~= '' then
        local vehicle = createPhotoVehicle(modelName)
        if vehicle then startPhotoMode(vehicle, true) end
        return
    end

    local ped = PlayerPedId()
    local currentVehicle = GetVehiclePedIsIn(ped, false)
    if currentVehicle == 0 then
        notifyPhotoHelp('Entre no veiculo que deseja fotografar ou use /fotocar <spawn>.')
        return
    end
    local vehicle = createPhotoVehicle(GetEntityModel(currentVehicle))
    if vehicle then startPhotoMode(vehicle, true) end
end, false)

RegisterCommand('fotocaroff', stopPhotoMode, false)

CreateThread(function()
    while true do
        if not photoMode then
            Wait(500)
        else
            Wait(0)
            HideHudAndRadarThisFrame()
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 75, true)

            if IsControlJustPressed(0, 200) or IsControlJustPressed(0, 177) then
                stopPhotoMode()
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        stopGaragePreview(true)
        stopPhotoMode()
    end
end)
