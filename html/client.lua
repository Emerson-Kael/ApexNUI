local SETTINGS_KVP = 'apexnui:settings'

local DEFAULT_SETTINGS = {
    hudEnabled = true,
    speedometerType = 'svg',
    speedUnit = 'kmh'
}

local DEFAULT_RADIAL_MENU_CONFIG = {
    rootPage = 'root',
    pages = {
        root = {
            defaultItem = 'tuning',
            items = {
                {
                    id = 'tuning',
                    label = 'Tunagem',
                    kicker = 'Apex',
                    icon = 'fa-screwdriver-wrench',
                    page = 'tuning'
                }
            }
        },
        tuning = {
            parent = 'root',
            parentItem = 'tuning',
            defaultItem = 'antilag',
            items = {
                {
                    id = 'antilag',
                    label = 'Antilag',
                    kicker = 'Tunagem',
                    icon = 'fa-fire',
                    page = 'antilag'
                },
                {
                    id = 'nitro',
                    label = 'Nitro',
                    kicker = 'Tunagem',
                    icon = 'fa-bolt',
                    action = 'nitro_placeholder'
                }
            }
        },
        antilag = {
            parent = 'tuning',
            parentItem = 'antilag',
            defaultItem = 'antilag_install',
            builder = 'buildSmpAntilagItems'
        }
    }
}

local DEFAULT_ANTILAG_MENU_ITEMS = {
    {
        id = 'antilag_install',
        label = 'Aplicar',
        kicker = 'Veiculo',
        icon = 'fa-plus',
        action = 'antilag_install'
    },
    {
        id = 'antilag_toggle',
        label = 'Ativar',
        kicker = 'Sistema',
        icon = 'fa-power-off',
        action = 'antilag_toggle'
    },
    {
        id = 'antilag_remove',
        label = 'Remover',
        kicker = 'Veiculo',
        icon = 'fa-minus',
        action = 'antilag_remove'
    }
}

local notify
local setRadialPage
local refreshEscMenuContext

local hintState = {
    visible = nil
}

local escMenuState = {
    open = false,
    selectedItem = 'continue'
}

local escProfileState = {
    loading = false,
    data = nil,
    lastRequestAt = 0
}

local radialMenuState = {
    open = false,
    page = 'root',
    selectedItem = nil
}

local raceState = {
    active = false
}

local speedState = {
    visible = nil,
    speed = nil,
    gear = nil,
    unit = nil,
    rpm = nil,
    absActive = nil,
    handbrakeActive = nil
}

local hudSettings = {
    hudEnabled = DEFAULT_SETTINGS.hudEnabled,
    speedometerType = DEFAULT_SETTINGS.speedometerType,
    speedUnit = DEFAULT_SETTINGS.speedUnit
}

local HIDDEN_NATIVE_HUD_COMPONENTS = {
    6, -- VehicleName
    7, -- AreaName
    8, -- VehicleClass
    9  -- StreetName
}

local squareMapLoaded = false
local minimapScaleform = 0
local PAUSE_FRONTEND_MENU_HASH = GetHashKey('FE_MENU_VERSION_MP_PAUSE')
local PAUSE_FRONTEND_COMPONENT_MAP = -1
local PAUSE_FRONTEND_COMPONENT_SETTINGS = 6

local function cloneDefaultSettings()
    return {
        hudEnabled = DEFAULT_SETTINGS.hudEnabled,
        speedometerType = DEFAULT_SETTINGS.speedometerType,
        speedUnit = DEFAULT_SETTINGS.speedUnit
    }
end

local function normalizeSpeedometerType(value)
    if value == 'svg' or value == 'hologramspeed' then
        return 'svg'
    end

    return 'apexnui'
end

local function normalizeSpeedUnit(value)
    if value == 'mph' then
        return 'mph'
    end

    return 'kmh'
end

local function getSpeedometerLabel(speedometerType)
    if normalizeSpeedometerType(speedometerType) == 'svg' then
        return 'Tipo 2 - SVG'
    end

    return 'Tipo 1 - ApexNUI'
end

local function getSpeedUnitLabel(speedUnit)
    if normalizeSpeedUnit(speedUnit) == 'mph' then
        return 'MPH'
    end

    return 'KM/H'
end

local function getDefaultEscProfileData()
    return {
        profile = {
            displayName = GetPlayerName(PlayerId()) or 'PILOTO',
            avatarId = 1,
            avatarUrl = nil
        },
        stats = {
            wins = 0,
            winRate = 0,
            totalMultiplayerRaces = 0,
            tracksCreated = 0,
            tracksWithRecords = 0,
            mostUsedCar = nil
        },
        recordTracks = {},
        recentRaces = {}
    }
end

local function normalizeEscProfileData(profileData)
    local fallback = getDefaultEscProfileData()
    local normalized = {
        profile = {
            displayName = fallback.profile.displayName,
            avatarId = fallback.profile.avatarId,
            avatarUrl = fallback.profile.avatarUrl
        },
        stats = {
            wins = 0,
            winRate = 0,
            totalMultiplayerRaces = 0,
            tracksCreated = 0,
            tracksWithRecords = 0,
            mostUsedCar = nil
        },
        recordTracks = {},
        recentRaces = {}
    }

    if type(profileData) ~= 'table' then
        return normalized
    end

    local profile = type(profileData.profile) == 'table' and profileData.profile or {}
    local stats = type(profileData.stats) == 'table' and profileData.stats or {}

    normalized.profile.displayName = tostring(profile.displayName or fallback.profile.displayName)
    normalized.profile.avatarId = math.max(1, math.floor(tonumber(profile.avatarId) or fallback.profile.avatarId))

    if type(profile.avatarUrl) == 'string' and profile.avatarUrl ~= '' then
        normalized.profile.avatarUrl = profile.avatarUrl
    end

    normalized.stats.wins = math.max(0, math.floor(tonumber(stats.wins) or 0))
    normalized.stats.winRate = tonumber(stats.winRate) or 0
    normalized.stats.totalMultiplayerRaces = math.max(0, math.floor(tonumber(stats.totalMultiplayerRaces) or 0))
    normalized.stats.tracksCreated = math.max(0, math.floor(tonumber(stats.tracksCreated) or 0))
    normalized.stats.tracksWithRecords = math.max(0, math.floor(tonumber(stats.tracksWithRecords) or 0))

    if type(stats.mostUsedCar) == 'table' then
        normalized.stats.mostUsedCar = {
            name = tostring(stats.mostUsedCar.name or stats.mostUsedCar.model or 'Sem dados'),
            model = stats.mostUsedCar.model and tostring(stats.mostUsedCar.model) or nil,
            uses = math.max(0, math.floor(tonumber(stats.mostUsedCar.uses) or 0))
        }
    end

    if type(profileData.recordTracks) == 'table' then
        for index = 1, #profileData.recordTracks do
            local record = profileData.recordTracks[index]

            if type(record) == 'table' then
                normalized.recordTracks[#normalized.recordTracks + 1] = {
                    trackId = math.max(0, math.floor(tonumber(record.trackId) or 0)),
                    trackName = tostring(record.trackName or 'PISTA'),
                    bestTimeFormatted = tostring(record.bestTimeFormatted or '--:--.--'),
                    vehicle = tostring(record.vehicle or 'Desconhecido')
                }
            end
        end
    end

    if type(profileData.recentRaces) == 'table' then
        for index = 1, #profileData.recentRaces do
            local race = profileData.recentRaces[index]

            if type(race) == 'table' then
                normalized.recentRaces[#normalized.recentRaces + 1] = {
                    historyId = math.max(0, math.floor(tonumber(race.historyId) or 0)),
                    trackName = tostring(race.trackName or 'PISTA'),
                    trackType = tostring(race.trackType or 'sprint'),
                    position = math.max(0, math.floor(tonumber(race.position) or 0)),
                    playerCount = math.max(0, math.floor(tonumber(race.playerCount) or 0)),
                    vehicle = tostring(race.vehicle or 'Desconhecido'),
                    bestLapFormatted = tostring(race.bestLapFormatted or 'N/A'),
                    finishTimeFormatted = tostring(race.finishTimeFormatted or 'N/A'),
                    didFinish = race.didFinish == true
                }
            end
        end
    end

    return normalized
end

local function buildEscProfilePayload()
    return {
        available = GetResourceState('apexracing') == 'started',
        loading = escProfileState.loading == true,
        data = normalizeEscProfileData(escProfileState.data)
    }
end

local function requestEscProfileData(forceRefresh)
    if GetResourceState('apexracing') ~= 'started' then
        escProfileState.loading = false
        refreshEscMenuContext()
        return false
    end

    local now = GetGameTimer()
    local shouldRequest = forceRefresh == true or escProfileState.data == nil or (now - escProfileState.lastRequestAt) >= 15000

    if not shouldRequest then
        refreshEscMenuContext()
        return true
    end

    escProfileState.loading = true
    escProfileState.lastRequestAt = now
    TriggerServerEvent('racing:requestProfileData')
    refreshEscMenuContext()

    return true
end

local function sanitizeEscMenuItem(itemId)
    local allowedItems = {
        continue = true,
        races = true,
        profile = true,
        map = true,
        leaderboard = true,
        garage = true,
        bennys = true,
        settings = true
    }

    if allowedItems[itemId] then
        return itemId
    end

    return 'continue'
end

local function buildSharedMenuItems()
    return {
        {
            id = 'map',
            label = 'MAPA',
            kicker = 'Los Santos',
            enabled = true
        },
        {
            id = 'races',
            label = 'CORRIDAS',
            kicker = 'Apex Racing',
            enabled = true
        },
        {
            id = 'profile',
            label = 'PERFIL',
            kicker = 'Piloto',
            enabled = true
        },
        {
            id = 'leaderboard',
            label = 'LEADERBOARD',
            kicker = 'Apex Racing',
            enabled = false
        },
        {
            id = 'garage',
            label = 'GARAGEM',
            kicker = 'Apex Garage',
            enabled = true
        },
        {
            id = 'bennys',
            label = 'BENNYS',
            kicker = 'Rush Customs',
            enabled = true
        },
        {
            id = 'settings',
            label = 'CONFIGURACOES',
            kicker = 'Jogo',
            enabled = true
        }
    }
end

local function getActiveRadialMenuConfig()
    if type(ApexRadialMenuConfig) == 'table' and type(ApexRadialMenuConfig.pages) == 'table' then
        return ApexRadialMenuConfig
    end

    return DEFAULT_RADIAL_MENU_CONFIG
end

local function getActiveRadialMenuPages()
    local activeConfig = getActiveRadialMenuConfig()
    return type(activeConfig.pages) == 'table' and activeConfig.pages or DEFAULT_RADIAL_MENU_CONFIG.pages
end

local function getActiveRadialMenuActions()
    if type(ApexRadialMenuActions) == 'table' then
        return ApexRadialMenuActions
    end

    return {}
end

local function getActiveRadialActionHandlers()
    local actions = getActiveRadialMenuActions()

    if type(actions.handlers) == 'table' then
        return actions.handlers
    end

    return {}
end

local function getActiveRadialPageBuilders()
    local actions = getActiveRadialMenuActions()

    if type(actions.pageBuilders) == 'table' then
        return actions.pageBuilders
    end

    return {}
end

local function getConfiguredRadialRootPage()
    local radialMenuConfig = getActiveRadialMenuConfig()
    local radialMenuPages = getActiveRadialMenuPages()
    local configuredRoot = type(radialMenuConfig.rootPage) == 'string' and radialMenuConfig.rootPage or 'root'

    if type(radialMenuPages[configuredRoot]) == 'table' then
        return configuredRoot
    end

    if type(radialMenuPages.root) == 'table' then
        return 'root'
    end

    for pageId, pageConfig in pairs(radialMenuPages) do
        if type(pageConfig) == 'table' then
            return pageId
        end
    end

    return 'root'
end

local function getRadialPageConfig(pageId)
    local radialMenuPages = getActiveRadialMenuPages()
    local rootPage = getConfiguredRadialRootPage()
    local currentPage = type(pageId) == 'string' and pageId or rootPage

    if type(radialMenuPages[currentPage]) ~= 'table' then
        currentPage = rootPage
    end

    return currentPage, radialMenuPages[currentPage] or {}
end

local function copyRadialItem(item)
    local clone = {}

    if type(item) ~= 'table' then
        return clone
    end

    for key, value in pairs(item) do
        clone[key] = value
    end

    return clone
end

local function copyRadialItemList(items)
    local clones = {}

    if type(items) ~= 'table' then
        return clones
    end

    for index = 1, #items do
        clones[index] = copyRadialItem(items[index])
    end

    return clones
end

local function createRadialPayloadItems(items)
    local payloadItems = {}

    if type(items) ~= 'table' then
        return payloadItems
    end

    for index = 1, #items do
        local sourceItem = items[index]
        local targetItem = {}

        if type(sourceItem) == 'table' then
            for key, value in pairs(sourceItem) do
                local valueType = type(value)

                if valueType ~= 'function' and valueType ~= 'table' and valueType ~= 'userdata' and valueType ~= 'thread' then
                    targetItem[key] = value
                end
            end
        end

        payloadItems[#payloadItems + 1] = targetItem
    end

    return payloadItems
end

local function normalizeRadialPageItems(items)
    local normalized = {}
    local nextSlot = 0

    if type(items) ~= 'table' then
        return normalized
    end

    for index = 1, #items do
        local item = copyRadialItem(items[index])
        local requestedSlot = tonumber(item.slot)

        if requestedSlot and requestedSlot >= nextSlot then
            item.slot = math.floor(requestedSlot)
            nextSlot = item.slot + 1
        else
            item.slot = nextSlot
            nextSlot = nextSlot + 1
        end

        item.enabled = item.enabled ~= false
        normalized[#normalized + 1] = item
    end

    return normalized
end

local buildRadialPageItems

local function getRadialDefaultItemId(pageId, items)
    local _, pageConfig = getRadialPageConfig(pageId)
    local desiredDefault = type(pageConfig.defaultItem) == 'string' and pageConfig.defaultItem or nil
    local candidates = items or buildRadialPageItems(pageId)

    if desiredDefault then
        for index = 1, #candidates do
            if candidates[index].id == desiredDefault then
                return desiredDefault
            end
        end
    end

    return candidates[1] and candidates[1].id or nil
end

local function sanitizeRadialMenuItem(itemId, pageId, items)
    local candidates = items or buildRadialPageItems(pageId)

    for index = 1, #candidates do
        if candidates[index].id == itemId then
            return itemId
        end
    end

    return getRadialDefaultItemId(pageId, candidates)
end

local function getRadialParentState(pageId)
    local currentPage, pageConfig = getRadialPageConfig(pageId)
    local parentPage = type(pageConfig.parent) == 'string' and pageConfig.parent or nil

    if not parentPage or parentPage == '' then
        return nil, nil
    end

    local resolvedParent = getRadialPageConfig(parentPage)
    local parentItem = type(pageConfig.parentItem) == 'string' and pageConfig.parentItem or nil

    if resolvedParent == currentPage then
        return nil, nil
    end

    return resolvedParent, parentItem
end

buildRadialPageItems = function(pageId)
    local currentPage, pageConfig = getRadialPageConfig(pageId)
    local items = {}

    if type(pageConfig.builder) == 'function' then
        local ok, builtItems = pcall(pageConfig.builder, {
            pageId = currentPage,
            pageConfig = pageConfig
        })

        if ok and type(builtItems) == 'table' then
            items = builtItems
        elseif not ok then
            print(('[apexnui] Falha ao montar a pagina radial "%s".'):format(currentPage))
        end
    elseif type(pageConfig.builder) == 'string' then
        local radialMenuPageBuilders = getActiveRadialPageBuilders()
        local builder = radialMenuPageBuilders[pageConfig.builder]
        if type(builder) == 'function' then
            local ok, builtItems = pcall(builder, {
                pageId = currentPage,
                pageConfig = pageConfig
            })

            if ok and type(builtItems) == 'table' then
                items = builtItems
            elseif not ok then
                print(('[apexnui] Falha ao montar a pagina radial "%s".'):format(currentPage))
            end
        end
    elseif type(pageConfig.items) == 'table' then
        items = pageConfig.items
    end

    if #items == 0 then
        if currentPage == 'antilag' then
            items = copyRadialItemList(DEFAULT_ANTILAG_MENU_ITEMS)
        elseif currentPage == 'tuning' then
            items = copyRadialItemList(DEFAULT_RADIAL_MENU_CONFIG.pages.tuning.items)
        elseif currentPage == getConfiguredRadialRootPage() then
            items = copyRadialItemList(DEFAULT_RADIAL_MENU_CONFIG.pages.root.items)
        end
    end

    return normalizeRadialPageItems(items)
end

local function saveHudSettings()
    SetResourceKvp(SETTINGS_KVP, json.encode(hudSettings))
end

local function loadHudSettings()
    local savedSettings = GetResourceKvpString(SETTINGS_KVP)
    if not savedSettings then
        hudSettings = cloneDefaultSettings()
        return
    end

    local decoded = json.decode(savedSettings)
    if type(decoded) ~= 'table' then
        hudSettings = cloneDefaultSettings()
        return
    end

    hudSettings.hudEnabled = decoded.hudEnabled ~= false

    -- A versão nova usa o velocímetro SVG como padrão.
    -- Se o KVP antigo ainda estiver salvo como ApexNUI, migra uma única vez.
    if decoded.speedometerType == nil or decoded.speedometerType == 'apexnui' then
        hudSettings.speedometerType = 'svg'
        saveHudSettings()
    else
        hudSettings.speedometerType = normalizeSpeedometerType(decoded.speedometerType)
    end

    hudSettings.speedUnit = normalizeSpeedUnit(decoded.speedUnit)
end

notify = function(description, notificationType)
    lib.notify({
        title = 'Apex HUD',
        description = description,
        type = notificationType or 'inform'
    })
end

local function updateSpeedUnitDisplay()
    SendNUIMessage({
        action = 'updateSpeedUnit',
        unit = getSpeedUnitLabel(hudSettings.speedUnit)
    })
end

local function hideApexSpeedometer(forceUpdate)
    if not forceUpdate and speedState.visible == false then
        return
    end

    speedState.visible = false
    speedState.speed = nil
    speedState.gear = nil
    speedState.unit = nil
    speedState.rpm = nil
    speedState.absActive = nil
    speedState.handbrakeActive = nil

    SendNUIMessage({
        action = 'updateSpeedometer',
        visible = false
    })
end

local function applySquareMapLayout()
    if squareMapLoaded then
        return
    end

    RequestStreamedTextureDict('squaremap', false)

    while not HasStreamedTextureDictLoaded('squaremap') do
        Wait(100)
    end

    AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', 'squaremap', 'radarmasksm')
    AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', 'squaremap', 'radarmasksm')
    SetMinimapClipType(0)
    SetMinimapComponentPosition('minimap', 'L', 'B', 0.0, -0.019, 0.1638, 0.183)
    SetMinimapComponentPosition('minimap_mask', 'L', 'B', 0.0, 0.028, 0.128, 0.20)
    SetMinimapComponentPosition('minimap_blur', 'L', 'B', -0.01, 0.040, 0.262, 0.300)
    SetBlipAlpha(GetNorthRadarBlip(), 0)

    SetRadarBigmapEnabled(true, false)
    Wait(50)
    SetRadarBigmapEnabled(false, false)

    squareMapLoaded = true
end

local function getMinimapScaleform()
    if minimapScaleform ~= 0 and HasScaleformMovieLoaded(minimapScaleform) then
        return minimapScaleform
    end

    minimapScaleform = RequestScaleformMovie('minimap')

    if HasScaleformMovieLoaded(minimapScaleform) then
        return minimapScaleform
    end

    return 0
end

local function hideMinimapHealthArmourBars()
    local minimapHandle = getMinimapScaleform()

    if minimapHandle == 0 then
        return
    end

    BeginScaleformMovieMethod(minimapHandle, 'SETUP_HEALTH_ARMOUR')
    ScaleformMovieMethodAddParamInt(3)
    EndScaleformMovieMethod()
end

local function buildEscMenuPayload()
    local items = buildSharedMenuItems()

    table.insert(items, 1, {
        id = 'continue',
        label = 'CONTINUAR',
        kicker = 'Retorno imediato',
        enabled = true
    })

    return {
        selectedId = sanitizeEscMenuItem(escMenuState.selectedItem),
        items = items,
        profile = buildEscProfilePayload()
    }
end

local function buildRadialMenuPayload()
    local currentPage = getRadialPageConfig(radialMenuState.page)
    local items = buildRadialPageItems(currentPage)
    local selectedId = sanitizeRadialMenuItem(radialMenuState.selectedItem, currentPage, items)
    local parentPage = getRadialParentState(currentPage)

    return {
        page = currentPage,
        canGoBack = parentPage ~= nil,
        selectedId = selectedId,
        items = createRadialPayloadItems(items)
    }
end

refreshEscMenuContext = function()
    if not escMenuState.open then
        return
    end

    SendNUIMessage({
        action = 'setEscMenuState',
        visible = true,
        payload = buildEscMenuPayload()
    })
end

local function refreshRadialMenuContext()
    if not radialMenuState.open then
        return
    end

    SendNUIMessage({
        action = 'setRadialMenuState',
        visible = true,
        payload = buildRadialMenuPayload()
    })
end

setRadialPage = function(pageId, selectedItem, refreshNow)
    local currentPage = getRadialPageConfig(pageId)
    local items = buildRadialPageItems(currentPage)

    radialMenuState.page = currentPage
    radialMenuState.selectedItem = sanitizeRadialMenuItem(selectedItem, currentPage, items)

    if refreshNow then
        refreshRadialMenuContext()
    end
end

local updateHintState
local updateSpeedState
local closeEscMenu
local closeRadialMenu
local backRadialMenu
local openHudSettingsMenu

local function openEscMenu()
    if escMenuState.open or radialMenuState.open or IsNuiFocused() or IsPauseMenuActive() then
        return
    end

    escMenuState.open = true
    escMenuState.selectedItem = 'continue'

    SetPauseMenuActive(false)
    if SetNuiFocusKeepInput then
        SetNuiFocusKeepInput(false)
    end
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'setEscMenuState',
        visible = true,
        payload = buildEscMenuPayload()
    })

    updateHintState(true)
    updateSpeedState(true)
end

local function openRadialMenu()
    if raceState.active or escMenuState.open or radialMenuState.open or IsNuiFocused() or IsPauseMenuActive() then
        return
    end

    radialMenuState.open = true
    setRadialPage(getConfiguredRadialRootPage(), nil, false)

    SetPauseMenuActive(false)
    if SetNuiFocusKeepInput then
        SetNuiFocusKeepInput(true)
    end
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'setRadialMenuState',
        visible = true,
        payload = buildRadialMenuPayload()
    })

    updateHintState(true)
    updateSpeedState(true)
end

local function isHudVisible()
    return hudSettings.hudEnabled and not IsPauseMenuActive() and not escMenuState.open and not radialMenuState.open
end

local function setRaceActive(isActive)
    local nextState = isActive == true

    if raceState.active == nextState then
        return
    end

    if nextState and escMenuState.open then
        closeEscMenu()
    end

    if nextState and radialMenuState.open then
        closeRadialMenu()
    end

    raceState.active = nextState
    updateHintState(true)
    refreshEscMenuContext()
    refreshRadialMenuContext()
end

updateHintState = function(forceUpdate)
    local visible = isHudVisible() and not raceState.active

    if not forceUpdate and hintState.visible == visible then
        return
    end

    hintState.visible = visible

    SendNUIMessage({
        action = 'updateHint',
        visible = visible
    })
end

updateSpeedState = function(forceUpdate)
    local visible = isHudVisible()
    local ped = PlayerPedId()
    local inVehicle = visible and IsPedInAnyVehicle(ped, false)

    if not inVehicle then
        hideApexSpeedometer(forceUpdate)
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    local speedMultiplier = hudSettings.speedUnit == 'mph' and 2.236936 or 3.6
    local speed = math.min(999, math.floor((GetEntitySpeed(vehicle) * speedMultiplier) + 0.5))
    local currentGear = GetVehicleCurrentGear(vehicle)
    local velocityY = GetEntitySpeedVector(vehicle, true).y
    local gear = 'N'
    local unit = getSpeedUnitLabel(hudSettings.speedUnit)
    local rpm = math.max(0.0, math.min(1.0, tonumber(GetVehicleCurrentRpm(vehicle)) or 0.0))
    local absActive = speed > 0 and (IsControlPressed(0, 72) or IsDisabledControlPressed(0, 72))
    local handbrakeActive = IsControlPressed(0, 76) or IsDisabledControlPressed(0, 76)

    if currentGear <= 0 then
        if velocityY < -0.5 then
            gear = 'R'
        end
    else
        gear = tostring(currentGear)
    end

    if not forceUpdate
        and speedState.visible == true
        and speedState.speed == speed
        and speedState.gear == gear
        and speedState.unit == unit
        and speedState.rpm == rpm
        and speedState.absActive == absActive
        and speedState.handbrakeActive == handbrakeActive then
        return
    end

    speedState.visible = true
    speedState.speed = speed
    speedState.gear = gear
    speedState.unit = unit
    speedState.rpm = rpm
    speedState.absActive = absActive
    speedState.handbrakeActive = handbrakeActive

    SendNUIMessage({
        action = 'updateSpeedometer',
        visible = true,
        speedometerType = hudSettings.speedometerType, -- Passa o tipo para a NUI escolher
        speed = speed,
        gear = gear,
        unit = unit,
        rpm = rpm,
        abs = absActive,
        hbk = handbrakeActive
    })
end

closeEscMenu = function()
    if not escMenuState.open then
        return
    end

    escMenuState.open = false

    SetPauseMenuActive(false)
    if SetNuiFocusKeepInput then
        SetNuiFocusKeepInput(false)
    end
    SetNuiFocus(false, false)

    SendNUIMessage({
        action = 'setEscMenuState',
        visible = false
    })

    updateHintState(true)
    updateSpeedState(true)
end

closeRadialMenu = function()
    if not radialMenuState.open then
        return
    end

    radialMenuState.open = false
    setRadialPage(getConfiguredRadialRootPage(), nil, false)

    SetPauseMenuActive(false)
    if SetNuiFocusKeepInput then
        SetNuiFocusKeepInput(false)
    end
    SetNuiFocus(false, false)

    SendNUIMessage({
        action = 'setRadialMenuState',
        visible = false
    })

    updateHintState(true)
    updateSpeedState(true)
end

backRadialMenu = function()
    if not radialMenuState.open then
        return
    end

    local parentPage, parentItem = getRadialParentState(radialMenuState.page)

    if parentPage then
        setRadialPage(parentPage, parentItem, true)
        return
    end

    closeRadialMenu()
end

local function openNativePauseFrontend(component)
    closeEscMenu()
    closeRadialMenu()

    CreateThread(function()
        Wait(120)
        ActivateFrontendMenu(PAUSE_FRONTEND_MENU_HASH, false, component or PAUSE_FRONTEND_COMPONENT_MAP)
    end)
end

local function handleEscMenuAction(itemId)
    local action = sanitizeEscMenuItem(tostring(itemId or 'continue'))
    escMenuState.selectedItem = action

    if action == 'continue' then
        closeEscMenu()
        return
    end

    if action == 'races' then
        closeEscMenu()
        CreateThread(function()
            Wait(0)
            ExecuteCommand('corridas')
        end)
        return
    end

    if action == 'profile' then
        requestEscProfileData(true)
        refreshEscMenuContext()
        return
    end

    if action == 'leaderboard' then
        closeEscMenu()
        CreateThread(function()
            Wait(0)
            ExecuteCommand('corridas')
        end)
        return
    end

    if action == 'map' then
        openNativePauseFrontend(PAUSE_FRONTEND_COMPONENT_MAP)
        return
    end

    if action == 'garage' then
        closeEscMenu()
        CreateThread(function()
            Wait(0)
            ExecuteCommand('car')
        end)
        return
    end

    if action == 'bennys' then
        if GetResourceState('rushBennys') ~= 'started' then
            notify('O recurso rushBennys nao esta iniciado.', 'error')
            refreshEscMenuContext()
            return
        end

        closeEscMenu()
        CreateThread(function()
            Wait(0)
            ExecuteCommand('ls')
        end)
        return
    end

    if action == 'settings' then
        openNativePauseFrontend(PAUSE_FRONTEND_COMPONENT_SETTINGS)
        return
    end
end

local function buildRadialActionContext()
    return {
        notify = notify,
        refresh = function()
            refreshRadialMenuContext()
        end,
        close = function()
            closeRadialMenu()
        end,
        setPage = function(pageId, selectedItem)
            setRadialPage(pageId, selectedItem, true)
        end,
        getPage = function()
            return radialMenuState.page
        end,
        getSelectedItem = function()
            return radialMenuState.selectedItem
        end
    }
end

local function handleRadialMenuAction(itemId)
    local currentPage = getRadialPageConfig(radialMenuState.page)
    local items = buildRadialPageItems(currentPage)
    local action = sanitizeRadialMenuItem(tostring(itemId or ''), currentPage, items)

    if not action then
        return
    end

    radialMenuState.selectedItem = action

    local selectedItem
    for index = 1, #items do
        if items[index].id == action then
            selectedItem = items[index]
            break
        end
    end

    if not selectedItem or selectedItem.enabled == false then
        refreshRadialMenuContext()
        return
    end

    if type(selectedItem.page) == 'string' and selectedItem.page ~= '' then
        setRadialPage(selectedItem.page, selectedItem.selectedItem, true)
        return
    end

    local handler = selectedItem.action
    if type(handler) == 'string' then
        local radialMenuActionHandlers = getActiveRadialActionHandlers()
        handler = radialMenuActionHandlers[handler]
    end

    if type(handler) ~= 'function' then
        return
    end

    local ok, err = pcall(handler, buildRadialActionContext(), selectedItem)
    if not ok then
        print(('[apexnui] Falha ao executar a acao radial "%s": %s'):format(action, tostring(err)))
        notify('Nao foi possivel executar essa opcao do radial.', 'error')
    end
end

openHudSettingsMenu = function()
    local input = lib.inputDialog('Configuracoes da HUD', {
        {
            type = 'select',
            label = 'HUD do Servidor',
            description = 'Ativa ou desativa mapa, F4, velocimetro e HUD nativa.',
            options = {
                { value = true, label = 'Ativada' },
                { value = false, label = 'Desativada' }
            },
            default = hudSettings.hudEnabled
        },
        {
            type = 'select',
            label = 'Velocimetro',
            description = 'Escolha entre o ApexNUI ou o SVG.',
            options = {
                { value = 'apexnui', label = 'Tipo 1 - ApexNUI' },
                { value = 'svg', label = 'Tipo 2 - SVG' }
            },
            default = hudSettings.speedometerType
        },
        {
            type = 'select',
            label = 'Unidade de Velocidade',
            description = 'Escolha se a velocidade sera exibida em KM/H ou MPH.',
            options = {
                { value = 'kmh', label = 'KM/H' },
                { value = 'mph', label = 'MPH' }
            },
            default = hudSettings.speedUnit
        }
    })

    if not input then
        return
    end

    local previousHudEnabled = hudSettings.hudEnabled
    local previousSpeedometerType = hudSettings.speedometerType
    local previousSpeedUnit = hudSettings.speedUnit

    hudSettings.hudEnabled = input[1] ~= false
    hudSettings.speedometerType = normalizeSpeedometerType(input[2])
    hudSettings.speedUnit = normalizeSpeedUnit(input[3])

    saveHudSettings()
    updateSpeedUnitDisplay()
    updateHintState(true)
    updateSpeedState(true)
    refreshEscMenuContext()
    refreshRadialMenuContext()

    if previousHudEnabled ~= hudSettings.hudEnabled then
        notify(hudSettings.hudEnabled and 'HUD do servidor ativada.' or 'HUD do servidor desativada.', hudSettings.hudEnabled and 'success' or 'warning')
    end

    if previousSpeedometerType ~= hudSettings.speedometerType then
        notify('Velocimetro alterado para ' .. getSpeedometerLabel(hudSettings.speedometerType) .. '.', 'success')
    end

    if previousSpeedUnit ~= hudSettings.speedUnit then
        notify('Unidade alterada para ' .. getSpeedUnitLabel(hudSettings.speedUnit) .. '.', 'success')
    end
end

RegisterCommand('hud', function()
    openHudSettingsMenu()
end, false)

RegisterCommand('apexhud', function()
    openHudSettingsMenu()
end, false)


RegisterCommand('+apexnui_holdRadial', function()
    if radialMenuState.open then
        return
    end

    openRadialMenu()
end, false)

RegisterCommand('-apexnui_holdRadial', function()
    closeRadialMenu()
end, false)

RegisterKeyMapping('+apexnui_holdRadial', 'Segurar menu radial Apex', 'keyboard', 'Z')

RegisterCommand('apexnui_openBennys', function()
    if raceState.active or not isHudVisible() then
        return
    end

    if GetResourceState('rushBennys') ~= 'started' then
        notify('O recurso rushBennys nao esta iniciado.', 'error')
        return
    end

    ExecuteCommand('ls')
end, false)

RegisterKeyMapping('apexnui_openBennys', 'Abrir Bennys Apex', 'keyboard', 'F5')


RegisterNUICallback('closeEscMenu', function(_, cb)
    closeEscMenu()
    cb({ ok = true })
end)

RegisterNUICallback('activateEscMenuItem', function(data, cb)
    handleEscMenuAction(data and data.itemId)
    cb({ ok = true })
end)

RegisterNUICallback('refreshEscProfile', function(_, cb)
    requestEscProfileData(true)
    cb({ ok = true })
end)

RegisterNUICallback('openEscProfileEditor', function(_, cb)
    if not escMenuState.open then
        cb({ ok = false })
        return
    end

    if GetResourceState('apexracing') ~= 'started' then
        notify('O recurso apexracing nao esta iniciado.', 'error')
        cb({ ok = false })
        return
    end

    local currentProfile = normalizeEscProfileData(escProfileState.data).profile

    if SetNuiFocusKeepInput then
        SetNuiFocusKeepInput(false)
    end
    SetNuiFocus(false, false)

    local input = lib.inputDialog('Perfil do Piloto', {
        {
            type = 'input',
            label = 'Nome do piloto',
            description = 'Nome exibido no perfil e nos lobbys.',
            default = currentProfile.displayName,
            required = true,
            max = 24
        },
        {
            type = 'number',
            label = 'Avatar',
            description = 'Escolha um avatar entre 1 e 12.',
            default = currentProfile.avatarId,
            min = 1,
            max = 12
        },
        {
            type = 'input',
            label = 'Avatar URL',
            description = 'Opcional. Se vazio, o avatar padrao continua.',
            default = currentProfile.avatarUrl or '',
            required = false
        }
    })

    if escMenuState.open then
        SetNuiFocus(true, true)
    end

    if not input then
        refreshEscMenuContext()
        cb({ ok = true, cancelled = true })
        return
    end

    escProfileState.loading = true
    TriggerServerEvent('racing:updateProfile', {
        displayName = input[1],
        avatarId = input[2],
        avatarUrl = input[3]
    })

    refreshEscMenuContext()
    cb({ ok = true })
end)

RegisterNUICallback('closeRadialMenu', function(_, cb)
    closeRadialMenu()
    cb({ ok = true })
end)

RegisterNUICallback('backRadialMenu', function(_, cb)
    backRadialMenu()
    cb({ ok = true })
end)

RegisterNUICallback('activateRadialMenuItem', function(data, cb)
    handleRadialMenuAction(data and data.itemId)
    cb({ ok = true })
end)

RegisterNetEvent('racing:startTimeTrial')
AddEventHandler('racing:startTimeTrial', function()
    setRaceActive(true)
end)

RegisterNetEvent('racing:receiveProfileData')
AddEventHandler('racing:receiveProfileData', function(profileData)
    escProfileState.loading = false
    escProfileState.data = normalizeEscProfileData(profileData)

    if escMenuState.open then
        refreshEscMenuContext()
    end
end)

AddEventHandler('chat:addMessage', function(message)
    if type(message) ~= 'table' or type(message.args) ~= 'table' then
        return
    end

    local title = tostring(message.args[1] or '')
    local description = tostring(message.args[2] or '')

    if not title:find('%[APEX%]') then
        return
    end

    if description:find('FIM DE CORRIDA!', 1, true)
        or description:find('saiu da corrida', 1, true)
        or description:find('nao pertence a categoria', 1, true) then
        setRaceActive(false)
    end
end)

CreateThread(function()
    loadHudSettings()
    applySquareMapLayout()
    updateSpeedUnitDisplay()
    updateHintState(true)
    updateSpeedState(true)

    while true do
        if not squareMapLoaded then
            applySquareMapLayout()
        end

        updateHintState(false)
        updateSpeedState(false)
        Wait(75)
    end
end)

CreateThread(function()
    while true do
        local customMenuOpen = escMenuState.open or radialMenuState.open
        local anotherNuiFocused = IsNuiFocused() and not customMenuOpen

        if customMenuOpen then
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)

            if radialMenuState.open then
                DisableControlAction(0, 1, true)
                DisableControlAction(0, 2, true)
                DisableControlAction(0, 21, true)
                DisableControlAction(0, 22, true)
                DisableControlAction(0, 23, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
                DisableControlAction(0, 32, true)
                DisableControlAction(0, 33, true)
                DisableControlAction(0, 34, true)
                DisableControlAction(0, 35, true)
                DisableControlAction(0, 36, true)
                DisableControlAction(0, 59, true)
                DisableControlAction(0, 60, true)
                DisableControlAction(0, 61, true)
                DisableControlAction(0, 62, true)
                DisableControlAction(0, 63, true)
                DisableControlAction(0, 64, true)
                DisableControlAction(0, 71, true)
                DisableControlAction(0, 72, true)
                DisableControlAction(0, 75, true)
                DisableControlAction(0, 76, true)
                DisablePlayerFiring(PlayerPedId(), true)
            end

            SetPauseMenuActive(false)
        else
            -- O ESC (200) e o pause/menu (199) sao bloqueados antes do GTA
            -- conseguir abrir o frontend nativo. Isso evita a tela de pausa
            -- antiga aparecer por um frame e impede o GTA de assumir o foco.
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)

            local pressedPause = IsDisabledControlJustPressed(0, 200)
            local pressedFrontend = IsDisabledControlJustPressed(0, 199)

            if pressedPause or pressedFrontend then
                SetPauseMenuActive(false)

                if not anotherNuiFocused then
                    openEscMenu()
                end
            elseif IsPauseMenuActive() then
                -- Se o GTA conseguir ativar o pause por qualquer motivo externo,
                -- fecha imediatamente para manter o menu APEX como frontend.
                SetPauseMenuActive(false)
            end
        end

        Wait(0)
    end
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local shouldShowRadar = hudSettings.hudEnabled and not escMenuState.open and not radialMenuState.open and IsPedInAnyVehicle(ped, false)

        if hudSettings.hudEnabled and not escMenuState.open and not radialMenuState.open then
            DisplayHud(false)
            DisplayRadar(shouldShowRadar)

            if shouldShowRadar then
                SetRadarBigmapEnabled(false, false)
                hideMinimapHealthArmourBars()
            end

            for i = 1, #HIDDEN_NATIVE_HUD_COMPONENTS do
                HideHudComponentThisFrame(HIDDEN_NATIVE_HUD_COMPONENTS[i])
            end
        else
            SetPauseMenuActive(false)
            HideHudAndRadarThisFrame()
        end

        Wait(0)
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'setEscMenuState',
        visible = false
    })
    SendNUIMessage({
        action = 'setRadialMenuState',
        visible = false
    })

    CreateThread(function()
        Wait(500)
        loadHudSettings()
        applySquareMapLayout()
        updateSpeedUnitDisplay()
        updateHintState(true)
        updateSpeedState(true)
    end)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        escMenuState.open = false
        radialMenuState.open = false
        if SetNuiFocusKeepInput then
            SetNuiFocusKeepInput(false)
        end
        SetNuiFocus(false, false)
        SetPauseMenuActive(false)
        return
    end

    if resourceName == 'apexracing' then
        setRaceActive(false)
        escProfileState.loading = false
        escProfileState.data = nil

        if escMenuState.open then
            refreshEscMenuContext()
        end
    end
end)