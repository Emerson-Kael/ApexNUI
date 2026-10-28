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
local garageCatalogOpen = false
local garageCatalogReturnToMultiplayer = false
local multiplayerCatalogRequested = false
local multiplayerVehicleImages = {}
local multiplayerVehicleDetails = {}
local garagePurchaseConfirmOpen = false
local garagePropertySiteOpen = false
local worldInteractions = {}
local worldInteractionDotVisible = false
local lastWorldInteractionDotX, lastWorldInteractionDotY
local lastWorldInteractionDotNear
local worldInteractionPromptVisible = false
local lastWorldInteractionPromptX, lastWorldInteractionPromptY, lastWorldInteractionPromptText

local function interactionCoords(value)
    if value == nil then return nil end
    local ok, x, y, z = pcall(function() return tonumber(value.x), tonumber(value.y), tonumber(value.z) end)
    if not ok then return nil end
    if not x or not y or not z then return nil end
    return vector3(x, y, z)
end

local function registerWorldInteraction(definition)
    if type(definition) ~= 'table' or not definition.id then return false end
    local coords = interactionCoords(definition.coords)
    if not coords then return false end
    worldInteractions[tostring(definition.id)] = {
        coords = coords,
        label = tostring(definition.label or 'INTERAGIR'),
        distance = math.max(0.5, tonumber(definition.distance) or 1.6),
        markerDistance = math.max(2.0, tonumber(definition.markerDistance) or 20.0),
        control = tonumber(definition.control) or 38,
        key = tostring(definition.key or 'E'),
        event = tostring(definition.event or ''),
        serverEvent = definition.serverEvent == true,
        args = type(definition.args) == 'table' and definition.args or {},
        onFoot = definition.onFoot == true
    }
    return true
end

local function removeWorldInteraction(id)
    if id == nil then return end
    worldInteractions[tostring(id)] = nil
end

exports('RegisterWorldInteraction', registerWorldInteraction)
exports('RemoveWorldInteraction', removeWorldInteraction)
AddEventHandler('apexnui:registerWorldInteraction', registerWorldInteraction)
AddEventHandler('apexnui:removeWorldInteraction', removeWorldInteraction)

-- Compensa o atraso da interface (NUI): estima a velocidade do ponto na tela e envia a posição
-- um instante à frente, para ele não "arrastar" atrás do mundo quando a câmera gira.
local WORLD_INTERACTION_LEAD = 0.035   -- segundos de antecipação (0 desliga)
local WORLD_INTERACTION_MAX_LEAD = 0.03 -- limite do deslocamento antecipado (fração da tela)
local promptPrediction, dotPrediction = {}, {}

local function predictScreen(state, x, y)
    local now = GetGameTimer()
    local dt = GetFrameTime()
    local vx, vy = 0.0, 0.0
    if state.x and state.time and now - state.time < 120 and dt > 0.0005 then
        local rvx, rvy = (x - state.x) / dt, (y - state.y) / dt
        vx = (state.vx or 0.0) * 0.5 + rvx * 0.5
        vy = (state.vy or 0.0) * 0.5 + rvy * 0.5
    end
    state.x, state.y, state.vx, state.vy, state.time = x, y, vx, vy, now
    if WORLD_INTERACTION_LEAD <= 0.0 then return x, y end
    local ox = math.max(-WORLD_INTERACTION_MAX_LEAD, math.min(WORLD_INTERACTION_MAX_LEAD, vx * WORLD_INTERACTION_LEAD))
    local oy = math.max(-WORLD_INTERACTION_MAX_LEAD, math.min(WORLD_INTERACTION_MAX_LEAD, vy * WORLD_INTERACTION_LEAD))
    return x + ox, y + oy
end

local function drawWorldInteractionPrompt(coords, key, label)
    local visible, screenX, screenY = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not visible or IsNuiFocused() then
        if worldInteractionPromptVisible then
            SendNUIMessage({ action = 'worldInteractionPrompt', visible = false })
            worldInteractionPromptVisible = false
            lastWorldInteractionPromptX, lastWorldInteractionPromptY, lastWorldInteractionPromptText = nil, nil, nil
        end
        return
    end
    screenX, screenY = predictScreen(promptPrediction, screenX, screenY)
    local promptText = tostring(key) .. '|' .. tostring(label)
    if not worldInteractionPromptVisible or math.abs(screenX - (lastWorldInteractionPromptX or 0)) > 0.00008
        or math.abs(screenY - (lastWorldInteractionPromptY or 0)) > 0.00008 or promptText ~= lastWorldInteractionPromptText then
        worldInteractionPromptVisible = true
        lastWorldInteractionPromptX, lastWorldInteractionPromptY, lastWorldInteractionPromptText = screenX, screenY, promptText
        SendNUIMessage({ action = 'worldInteractionPrompt', visible = true, x = screenX, y = screenY, key = key, label = label })
    end
end

local function hideWorldInteractionPrompt()
    if not worldInteractionPromptVisible then return end
    SendNUIMessage({ action = 'worldInteractionPrompt', visible = false })
    worldInteractionPromptVisible = false
    lastWorldInteractionPromptX, lastWorldInteractionPromptY, lastWorldInteractionPromptText = nil, nil, nil
end

local function updateWorldInteractionDot(coords, near)
    local visible, centerX, centerY = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not visible or IsNuiFocused() then
        if worldInteractionDotVisible then
            SendNUIMessage({ action = 'worldInteractionDot', visible = false, near = false })
            worldInteractionDotVisible = false
            lastWorldInteractionDotX, lastWorldInteractionDotY = nil, nil
            lastWorldInteractionDotNear = nil
        end
        return
    end
    near = near == true
    centerX, centerY = predictScreen(dotPrediction, centerX, centerY)
    if not worldInteractionDotVisible or math.abs(centerX - (lastWorldInteractionDotX or 0)) > 0.00008
        or math.abs(centerY - (lastWorldInteractionDotY or 0)) > 0.00008
        or near ~= lastWorldInteractionDotNear then
        worldInteractionDotVisible = true
        lastWorldInteractionDotX, lastWorldInteractionDotY = centerX, centerY
        lastWorldInteractionDotNear = near
        SendNUIMessage({ action = 'worldInteractionDot', visible = true, near = near, x = centerX, y = centerY })
    end
end

local function hideWorldInteractionDot()
    if not worldInteractionDotVisible then return end
    SendNUIMessage({ action = 'worldInteractionDot', visible = false, near = false })
    worldInteractionDotVisible = false
    lastWorldInteractionDotX, lastWorldInteractionDotY = nil, nil
    lastWorldInteractionDotNear = nil
end

CreateThread(function()
    while true do
        local wait = 400
        if next(worldInteractions) then
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            local inVehicle = IsPedInAnyVehicle(ped, false)
            -- Só UMA interação é exibida por vez (a "near" tem prioridade; depois a mais próxima).
            -- Antes, cada interação ao alcance mostrava/escondia o mesmo ponto/prompt no mesmo
            -- quadro, e isso causava o tremor/piscar quando havia mais de uma perto.
            local best, bestDistance, bestNear
            for _, interaction in pairs(worldInteractions) do
                local distance = #(playerCoords - interaction.coords)
                if distance <= interaction.markerDistance then
                    wait = 0
                    local near = distance <= interaction.distance and (not interaction.onFoot or not inVehicle)
                    if not best or (near and not bestNear) or (near == bestNear and distance < bestDistance) then
                        best, bestDistance, bestNear = interaction, distance, near
                    end
                end
            end
            if best then
                if bestNear then
                    hideWorldInteractionDot()
                    drawWorldInteractionPrompt(best.coords + vector3(0.0, 0.0, 0.08), best.key, best.label)
                    DisableControlAction(0, best.control, true)
                    if IsDisabledControlJustReleased(0, best.control) then
                        if best.event ~= '' then
                            if best.serverEvent then
                                TriggerServerEvent(best.event, table.unpack(best.args))
                            else
                                TriggerEvent(best.event, table.unpack(best.args))
                            end
                        end
                    end
                else
                    hideWorldInteractionPrompt()
                    updateWorldInteractionDot(best.coords, false)
                end
            end
        end
        if wait ~= 0 then
            hideWorldInteractionDot()
            hideWorldInteractionPrompt()
        end
        Wait(wait)
    end
end)

local function getMultiplayerVehiclePreview()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local preview = { available = false }

    if vehicle ~= 0 and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped then
        local modelHash = GetEntityModel(vehicle)
        local displayKey = GetDisplayNameFromVehicleModel(modelHash)
        local archetype = GetEntityArchetypeName and GetEntityArchetypeName(vehicle) or nil
        local model = string.lower(tostring(archetype and archetype ~= '' and archetype ~= 'NULL' and archetype or displayKey or ''))
        local label = displayKey and GetLabelText(displayKey) or nil
        local make = GetMakeNameFromVehicleModel(modelHash)
        local makeLabel = make and GetLabelText(make) or nil
        local catalog = multiplayerVehicleDetails[model] or {}
        preview = {
            available = true,
            model = model,
            displayName = catalog.displayName or (label and label ~= 'NULL' and label or model),
            brand = catalog.brand or (makeLabel and makeLabel ~= 'NULL' and makeLabel or 'SEU VEÍCULO'),
            image = catalog.image or multiplayerVehicleImages[model]
        }
    end

    return preview
end

local escProfileState = {
    loading = false,
    data = nil,
    lastRequestAt = 0
}
local apexEconomyState = { balance = 0, level = 1, levelProgress = 0, xpForNextLevel = 1000 }

local radialMenuState = {
    open = false,
    page = 'root',
    selectedItem = nil
}

local vehicleQuickMenuState = {
    open = false,
    vehicle = 0
}

local raceState = {
    active = false
}

local garageInteriorActive = false

-- Pistas do apexracing, usadas pela aba "Corridas" do esc-menu (Treino,
-- Tomada de tempo e Pistas verificadas). O apexracing continua sendo o
-- dono da logica/dados; aqui so guardamos um cache para exibir na NUI.
local raceTracksState = {
    loading = false,
    tracks = {},
    lastRequestAt = 0
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
local nativeMapOnlyOpen = false
local apexMapOpen = false
local nativeSettingsOnlyOpen = false

-- Ambiente controlado pelo menu APEX (cliente).
local environmentState = {
    time = GetClockHours(),
    minute = GetClockMinutes(),
    weather = 'CLEAR',
    locked = false
}

local ENVIRONMENT_WEATHER = {
    clear = 'CLEAR',
    cloudy = 'CLOUDS',
    rain = 'RAIN',
    storm = 'THUNDER',
    fog = 'FOGGY',
    snow = 'XMAS'
}

local function applyEnvironmentTime(hour, minute)
    hour = math.max(0, math.min(23, math.floor(tonumber(hour) or environmentState.time or 18)))
    minute = math.max(0, math.min(59, math.floor(tonumber(minute) or 0)))
    environmentState.time = hour
    environmentState.minute = minute
    NetworkOverrideClockTime(hour, minute, 0)
end

local function applyEnvironmentWeather(weatherId)
    local weather = ENVIRONMENT_WEATHER[tostring(weatherId or '')] or 'CLEAR'
    environmentState.weather = weather

    -- Remove qualquer override anterior antes de aplicar o novo clima.
    ClearOverrideWeather()
    SetWeatherTypePersist(weather)
    SetWeatherTypeNowPersist(weather)
    SetWeatherTypeNow(weather)
end

local WEATHER_HASH_TO_ID = {
    [GetHashKey('EXTRASUNNY')] = 'EXTRASUNNY',
    [GetHashKey('CLEAR')] = 'CLEAR',
    [GetHashKey('CLOUDS')] = 'CLOUDS',
    [GetHashKey('OVERCAST')] = 'OVERCAST',
    [GetHashKey('RAIN')] = 'RAIN',
    [GetHashKey('THUNDER')] = 'THUNDER',
    [GetHashKey('FOGGY')] = 'FOGGY',
    [GetHashKey('XMAS')] = 'XMAS'
}

local function getCurrentWeatherType()
    local hash = GetPrevWeatherTypeHashName()
    return WEATHER_HASH_TO_ID[hash] or environmentState.weather or 'CLEAR'
end

local function getEnvironmentPayload()
    local weatherIds = {
        EXTRASUNNY = 'clear',
        CLEAR = 'clear',
        CLOUDS = 'cloudy',
        OVERCAST = 'cloudy',
        RAIN = 'rain',
        THUNDER = 'storm',
        FOGGY = 'fog',
        XMAS = 'snow'
    }

    if not environmentState.locked then
        environmentState.time = GetClockHours()
        environmentState.minute = GetClockMinutes()
        environmentState.weather = getCurrentWeatherType()
    end

    return {
        time = environmentState.time,
        minute = environmentState.minute,
        weather = environmentState.weather,
        weatherId = weatherIds[environmentState.weather] or 'clear',
        locked = environmentState.locked == true
    }
end

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

local function normalizeRaceTrackEntry(track)
    if type(track) ~= 'table' then return nil end

    local checkpoints = type(track.checkpoints) == 'table' and #track.checkpoints or tonumber(track.checkpointCount) or 0
    local trackType = (track.type == 'sprint') and 'sprint' or 'circuit'

    return {
        id = tonumber(track.id),
        name = tostring(track.name or 'PISTA'),
        type = trackType,
        checkpoints = checkpoints,
        distance = tonumber(track.distance) or 0.0,
        creatorName = tostring(track.creator_name or track.creatorName or 'Equipe Apex')
    }
end

local function sendRaceTracksToNui()
    local list = {}
    for i = 1, #raceTracksState.tracks do
        list[#list + 1] = raceTracksState.tracks[i]
    end

    SendNUIMessage({
        action = 'loadApexRaceTracks',
        loading = raceTracksState.loading == true,
        available = GetResourceState('apexracing') == 'started',
        tracks = list
    })
end

local function requestRaceTracks(forceRefresh)
    if GetResourceState('apexracing') ~= 'started' then
        raceTracksState.loading = false
        sendRaceTracksToNui()
        return false
    end

    local now = GetGameTimer()
    local shouldRequest = forceRefresh == true or (#raceTracksState.tracks == 0) or (now - raceTracksState.lastRequestAt) >= 15000

    if not shouldRequest then
        sendRaceTracksToNui()
        return true
    end

    raceTracksState.loading = true
    raceTracksState.lastRequestAt = now
    TriggerServerEvent('racing:requestTracksList')
    sendRaceTracksToNui()

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
    if decoded.speedometerType == nil then
        hudSettings.speedometerType = 'svg'
    else
        hudSettings.speedometerType = normalizeSpeedometerType(decoded.speedometerType)
    end

    hudSettings.speedUnit = normalizeSpeedUnit(decoded.speedUnit)
end

notify = function(description, notificationType)
    TriggerEvent('apexnui:notify', {
        title = 'APEX HUD',
        description = description,
        type = notificationType or 'inform'
    })
end

RegisterNetEvent('apexnui:notify', function(payload)
    payload = type(payload) == 'table' and payload or { description = tostring(payload or '') }
    local description = tostring(payload.description or payload.message or '')
    local title = tostring(payload.title or 'APEX')
    local kind = tostring(payload.type or payload.kind or 'inform')

    if GetResourceState('apexplayergarage') == 'started' then
        TriggerEvent('apexplayergarage:showNotification', description, kind, title)
        return
    end

    lib.notify({ title = title, description = description, type = kind })
end)

RegisterCommand('testarnotificacao', function()
    if GetResourceState('apexplayergarage') == 'started' then
        TriggerEvent('apexplayergarage:showReward', 3000, 'Corrida casual concluída')
        return
    end

    TriggerEvent('apexnui:notify', {
        title = 'DINHEIRO',
        description = '+$3.000 • Corrida casual concluída',
        type = 'success'
    })
end, false)

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
        profile = buildEscProfilePayload(),
        economy = apexEconomyState,
        environment = getEnvironmentPayload(),
        settings = {
            speedUnit = hudSettings.speedUnit,
            speedometerType = hudSettings.speedometerType
        }
    }
end

RegisterNetEvent('apexnui:economyUpdate', function(account)
    if type(account) ~= 'table' then return end
    apexEconomyState = {
        balance = math.max(0, math.floor(tonumber(account.balance) or 0)),
        level = math.max(1, math.floor(tonumber(account.level) or 1)),
        levelProgress = math.max(0, math.floor(tonumber(account.levelProgress) or 0)),
        xpForNextLevel = math.max(1, math.floor(tonumber(account.xpForNextLevel) or 1000))
    }
    SendNUIMessage({ action = 'apexEconomyUpdate', economy = apexEconomyState })
    refreshEscMenuContext()
end)

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
local closeVehicleQuickMenu
local backRadialMenu
local openHudSettingsMenu
local trackCreatorCanCreate = false

local function requestTrackCreatorPermission()
    if GetResourceState('apexracing') == 'started' then
        TriggerServerEvent('racing:checkPermission')
    else
        SendNUIMessage({ action = 'setTrackCreatorPermission', canCreate = false })
    end
end

RegisterNetEvent('racing:returnPermission', function(permissionData)
    trackCreatorCanCreate = type(permissionData) == 'table' and permissionData.canCreate == true
    SendNUIMessage({ action = 'setTrackCreatorPermission', canCreate = trackCreatorCanCreate })
end)

local function isTrackCreatorActive()
    return LocalPlayer and LocalPlayer.state and LocalPlayer.state.apexCreatorHudMode == true or false
end

local function openEscMenu()
    if isTrackCreatorActive() or escMenuState.open or radialMenuState.open or vehicleQuickMenuState.open or IsNuiFocused() or IsPauseMenuActive() then
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

    SendNUIMessage({ action = 'setMultiplayerShowcaseVehicle', vehicle = getMultiplayerVehiclePreview() })
    if not garageCatalogOpen and not multiplayerCatalogRequested and GetResourceState('apexgarage_catalog') == 'started' then
        multiplayerCatalogRequested = true
        TriggerServerEvent('apexgarage_catalog:requestOpenData')
    end

    updateHintState(true)
    updateSpeedState(true)
end

RegisterNetEvent('apexnui:setVehicleSwapHudHidden', function(hidden)
    SendNUIMessage({
        action = 'setVehicleSwapHudHidden',
        hidden = hidden == true
    })
end)


RegisterNetEvent('apexnui:openEscMenu')
AddEventHandler('apexnui:openEscMenu', function()
    openEscMenu()
end)

local function openRadialMenu()
    if raceState.active or escMenuState.open or radialMenuState.open or vehicleQuickMenuState.open or IsNuiFocused() or IsPauseMenuActive() then
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

local function getVehicleQuickMenuName(vehicle)
    local model = GetEntityModel(vehicle)
    local displayKey = GetDisplayNameFromVehicleModel(model)
    local displayName = GetLabelText(displayKey)
    if not displayName or displayName == '' or displayName == 'NULL' then
        displayName = displayKey
    end

    local makeKey = GetMakeNameFromVehicleModel(model)
    local makeName = GetLabelText(makeKey)
    if makeName and makeName ~= '' and makeName ~= 'NULL' and displayName and displayName ~= '' then
        return (makeName .. ' ' .. displayName):upper()
    end

    return tostring(displayName or 'VEICULO'):upper()
end

local function getVehicleQuickMenuPayload(vehicle)
    local indicatorState = GetVehicleIndicatorLights(vehicle)
    return {
        vehicleName = getVehicleQuickMenuName(vehicle),
        engineOn = GetIsVehicleEngineRunning(vehicle),
        hazardsOn = indicatorState == 3,
        moving = GetEntitySpeed(vehicle) > 0.5
    }
end

local function refreshVehicleQuickMenu()
    if not vehicleQuickMenuState.open then
        return
    end

    local vehicle = vehicleQuickMenuState.vehicle
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        closeVehicleQuickMenu()
        return
    end

    SendNUIMessage({
        action = 'setVehicleQuickMenuState',
        visible = true,
        payload = getVehicleQuickMenuPayload(vehicle)
    })
end

local function openVehicleQuickMenu()
    if vehicleQuickMenuState.open then
        closeVehicleQuickMenu()
        return
    end

    if escMenuState.open or radialMenuState.open or IsNuiFocused() or IsPauseMenuActive() then
        return
    end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        return
    end

    vehicleQuickMenuState.open = true
    vehicleQuickMenuState.vehicle = vehicle

    SetPauseMenuActive(false)
    if SetNuiFocusKeepInput then
        SetNuiFocusKeepInput(true)
    end
    SetNuiFocus(true, false)

    SendNUIMessage({
        action = 'setVehicleQuickMenuState',
        visible = true,
        payload = getVehicleQuickMenuPayload(vehicle)
    })

    updateHintState(true)
    updateSpeedState(true)
end

local function isHudVisible()
    local garageInterior = garageInteriorActive
        or (LocalPlayer and LocalPlayer.state and LocalPlayer.state.apexPlayerGarageInterior == true)
    return hudSettings.hudEnabled and not garageInterior and not IsPauseMenuActive()
        and not escMenuState.open and not radialMenuState.open
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

    if nextState and vehicleQuickMenuState.open then
        closeVehicleQuickMenu()
    end

    raceState.active = nextState
    updateHintState(true)
    refreshEscMenuContext()
    refreshRadialMenuContext()
end

updateHintState = function(forceUpdate)
    local visible = isHudVisible() and not vehicleQuickMenuState.open and not raceState.active

    if not forceUpdate and hintState.visible == visible then
        return
    end

    hintState.visible = visible

    SendNUIMessage({
        action = 'updateHint',
        visible = visible
    })
end

CreateThread(function()
    local previousMode = nil
    while true do
        local active = LocalPlayer and LocalPlayer.state and LocalPlayer.state.apexCreatorHudMode == true or false
        if active ~= previousMode then
            previousMode = active
            SendNUIMessage({ action = 'setCreatorHudMode', active = active })
        end
        Wait(250)
    end
end)

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
    -- ABS = freio (72) acionado em movimento; HBK = freio de mao (76).
    -- Usa o valor analogico (gatilho L2 do controle) alem da tecla e segura o
    -- estado aceso por 200 ms para um toque rapido nao passar despercebido.
    local now = GetGameTimer()
    local function inputActive(control)
        return IsControlPressed(0, control) or IsDisabledControlPressed(0, control)
            or GetControlNormal(0, control) > 0.15 or GetDisabledControlNormal(0, control) > 0.15
    end
    if speed > 2 and inputActive(72) then
        speedState.absUntil = now + 200
    end
    if inputActive(76) then
        speedState.handbrakeUntil = now + 200
    end
    local absActive = now < (speedState.absUntil or 0)
    local handbrakeActive = now < (speedState.handbrakeUntil or 0)

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

AddEventHandler('apexnui:setGarageInterior', function(active)
    garageInteriorActive = active == true
    updateHintState(true)
    updateSpeedState(true)
end)

closeEscMenu = function()
    if not escMenuState.open then
        return
    end

    escMenuState.open = false
    garageCatalogOpen = false
    garageCatalogReturnToMultiplayer = false
    TriggerEvent('apexnui:stopGaragePreview', false)
    TriggerEvent('apexgarage:clearPickerContext', 'closed')

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

closeVehicleQuickMenu = function()
    if not vehicleQuickMenuState.open then
        return
    end

    vehicleQuickMenuState.open = false
    vehicleQuickMenuState.vehicle = 0

    SetPauseMenuActive(false)
    if SetNuiFocusKeepInput then
        SetNuiFocusKeepInput(false)
    end
    SetNuiFocus(false, false)

    SendNUIMessage({
        action = 'setVehicleQuickMenuState',
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

local function configureNativeMapHeader()
    -- O mapa continua sendo o mapa nativo do GTA, mas deixamos as outras
    -- abas do frontend bloqueadas para o jogador permanecer no MAPA.
    if not IsPauseMenuActive() then
        return
    end

    -- Índices conhecidos do cabeçalho multiplayer: 0 = Mapa.
    -- Os demais ficam bloqueados, mas o mapa continua totalmente interativo.
    for index = 1, 5 do
        if BeginScaleformMovieMethodOnFrontendHeader('LOCK_MENU_ITEM') then
            ScaleformMovieMethodAddParamInt(index)
            ScaleformMovieMethodAddParamBool(true)
            EndScaleformMovieMethod()
        end
    end

    if BeginScaleformMovieMethodOnFrontendHeader('HIGHLIGHT_MENU') then
        ScaleformMovieMethodAddParamInt(0)
        EndScaleformMovieMethod()
    end
end

local function configureNativeSettingsHeader()
    if not IsPauseMenuActive() then
        return
    end

    -- No cabeçalho multiplayer, Configurações ocupa o índice 5.
    -- Trava as outras páginas para manter o jogador somente nas opções nativas.
    for index = 0, 10 do
        if BeginScaleformMovieMethodOnFrontendHeader('LOCK_MENU_ITEM') then
            ScaleformMovieMethodAddParamInt(index)
            ScaleformMovieMethodAddParamBool(index ~= 5)
            EndScaleformMovieMethod()
        end
    end

    if BeginScaleformMovieMethodOnFrontendHeader('HIGHLIGHT_MENU') then
        ScaleformMovieMethodAddParamInt(5)
        EndScaleformMovieMethod()
    end
end

local function openNativePauseFrontend(component)
    closeEscMenu()
    closeRadialMenu()
    closeVehicleQuickMenu()

    nativeSettingsOnlyOpen = true
    apexMapOpen = false
    nativeMapOnlyOpen = false
    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then
        SetNuiFocusKeepInput(false)
    end

    CreateThread(function()
        ActivateFrontendMenu(PAUSE_FRONTEND_MENU_HASH, 0, component or PAUSE_FRONTEND_COMPONENT_SETTINGS)
        Wait(120)
        if nativeSettingsOnlyOpen then
            configureNativeSettingsHeader()
        end
    end)
end

local function closeNativeSettingsAndReturn()
    if not nativeSettingsOnlyOpen then
        return
    end

    nativeSettingsOnlyOpen = false
    SetFrontendActive(false)
    SetPauseMenuActive(false)
    CreateThread(function()
        Wait(100)
        if not escMenuState.open and not radialMenuState.open then
            openEscMenu()
        end
    end)
end

local function maintainNativeSettingsOnly()
    if not nativeSettingsOnlyOpen then
        return
    end

    if not IsPauseMenuActive() then
        closeNativeSettingsAndReturn()
        return
    end

    -- Bloqueia apenas os atalhos de abas; esquerda/direita continuam ajustando
    -- as opções dentro da página nativa de Configurações.
    local blockedControls = { 189, 190, 199 }
    for i = 1, #blockedControls do
        DisableControlAction(0, blockedControls[i], true)
    end

    if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 202) then
        closeNativeSettingsAndReturn()
        return
    end

    configureNativeSettingsHeader()
end

local function openApexBigMap()
    closeEscMenu()
    closeRadialMenu()

    apexMapOpen = true
    nativeMapOnlyOpen = true

    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then
        SetNuiFocusKeepInput(false)
    end

    CreateThread(function()
        -- O mapa em tela cheia precisa do frontend nativo. Diferente do
        -- BigMap do radar, esta versão permite zoom, arrastar e marcar
        -- waypoint normalmente.
        ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_MP_PAUSE'), 0, -1)
        Wait(120)

        if not apexMapOpen then
            return
        end

        PauseMenuceptionGoDeeper(0)
        Wait(80)
        configureNativeMapHeader()
    end)
end

local function closeApexBigMap()
    if not apexMapOpen and not nativeMapOnlyOpen then
        return
    end

    apexMapOpen = false
    nativeMapOnlyOpen = false

    SetFrontendActive(false)
    SetPauseMenuActive(false)
    SetRadarBigmapEnabled(false, false)
    DisplayRadar(false)
end

local function maintainNativeMapOnly()
    if not nativeMapOnlyOpen then
        return
    end

    if not IsPauseMenuActive() then
        apexMapOpen = false
        nativeMapOnlyOpen = false
        return
    end

    -- Bloqueia a troca de páginas do frontend, mas NÃO bloqueia mouse,
    -- zoom, arrasto ou seleção de waypoint do mapa.
    local blockedControls = {
        189, 190, -- LB / RB
        205, 206, -- esquerda / direita frontend
        199       -- pause alternativo
    }

    for i = 1, #blockedControls do
        DisableControlAction(0, blockedControls[i], true)
    end

    -- ESC fecha o mapa sem voltar para o menu APEX ou para outra aba.
    if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 202) then
        closeApexBigMap()
        return
    end

    configureNativeMapHeader()
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
        openApexBigMap()
        return
    end

    if action == 'garage' then
        if GetResourceState('apexgarage_catalog') ~= 'started' then
            refreshEscMenuContext()
            return
        end

        garageCatalogOpen = true
        SendNUIMessage({ action = 'openApexGarageCatalog' })
        TriggerServerEvent('apexgarage_catalog:requestOpenData')
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
    if not radialMenuState.open then
        openRadialMenu()
    end
end, false)

RegisterCommand('-apexnui_holdRadial', function()
    closeRadialMenu()
end, false)

RegisterKeyMapping('+apexnui_holdRadial', 'Segurar menu radial Apex', 'keyboard', 'F1')

CreateThread(function()
    while true do
        if vehicleQuickMenuState.open then
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) or GetVehiclePedIsIn(ped, false) ~= vehicleQuickMenuState.vehicle then
                closeVehicleQuickMenu()
            else
                refreshVehicleQuickMenu()
            end
            Wait(250)
        else
            Wait(500)
        end
    end
end)

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

RegisterNetEvent('apexnui:openGaragePurchaseConfirm', function(data)
    if type(data) ~= 'table' then return end
    if escMenuState.open or radialMenuState.open or vehicleQuickMenuState.open or IsNuiFocused() then return end

    garagePurchaseConfirmOpen = true
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'showApexGaragePurchaseConfirm',
        kind = 'purchase',
        locationId = tonumber(data.locationId),
        locationName = tostring(data.locationName or 'Garagem APEX'),
        price = tostring(data.price or '$25.000'),
        capacity = tonumber(data.capacity) or 2,
        tier = tonumber(data.tier) or 1
    })
end)

-- Fecha o site de garagens e a confirmação de compra (usado pelo apexplayergarage na troca para Tier 2).
AddEventHandler('apexnui:closeGaragePropertySite', function()
    garagePropertySiteOpen = false
    garagePurchaseConfirmOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideApexGarageSite' })
    SendNUIMessage({ action = 'hideApexGaragePurchaseConfirm' })
end)

RegisterNetEvent('apexnui:openGarageUpgradeConfirm', function(data)
    if type(data) ~= 'table' then return end
    if escMenuState.open or radialMenuState.open or vehicleQuickMenuState.open or IsNuiFocused() then return end
    local capacity = tonumber(data.capacity)
    if not capacity or capacity < 1 then return end

    garagePurchaseConfirmOpen = true
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'showApexGaragePurchaseConfirm',
        kind = 'upgrade',
        capacity = capacity,
        price = tostring(data.price or '$0')
    })
end)

RegisterNUICallback('confirmApexGaragePurchase', function(data, cb)
    local kind = tostring(data and data.kind or 'purchase')
    local locationId = tonumber(data and data.locationId)
    local capacity = tonumber(data and data.capacity)
    local started = GetResourceState('apexplayergarage') == 'started'
    garagePurchaseConfirmOpen = false
    SetNuiFocus(false, false)
    if kind == 'upgrade' and capacity and capacity > 0 and started then
        TriggerServerEvent('apexplayergarage:upgradeGarage', capacity)
    elseif kind == 'purchase' and locationId and locationId > 0 and started then
        TriggerServerEvent('apexplayergarage:buyGarage', locationId)
    end
    cb({ ok = started and ((kind == 'upgrade' and capacity ~= nil) or (kind == 'purchase' and locationId ~= nil)) })
end)

RegisterNUICallback('closeApexGaragePurchaseConfirm', function(_, cb)
    garagePurchaseConfirmOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideApexGaragePurchaseConfirm' })
    cb({ ok = true })
end)

RegisterNetEvent('apexnui:openGaragePropertySite', function(data)
    if type(data) ~= 'table' then return end
    if escMenuState.open or radialMenuState.open or vehicleQuickMenuState.open or IsNuiFocused() then return end
    garagePropertySiteOpen = true
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'showApexGarageSite', locations = data.locations or {}, owned = data.owned == true,
        ownedGarages = data.ownedGarages or {}, vehicles = data.vehicles or {},
        currentLocationId = tonumber(data.currentLocationId), currentLocationLabel = tostring(data.currentLocationLabel or ''),
        selectedLocationId = tonumber(data.selectedLocationId), priceText = tostring(data.priceText or '$25.000'),
        capacity = tonumber(data.capacity) or 2, nextCapacity = tonumber(data.nextCapacity),
        upgradePriceText = tostring(data.upgradePriceText or '') })
end)

RegisterNUICallback('closeApexGarageSite', function(_, cb)
    garagePropertySiteOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideApexGarageSite' })
    cb({ ok = true })
end)

RegisterNUICallback('submitApexGarageSite', function(data, cb)
    local locationId = tonumber(data and data.locationId)
    local started = GetResourceState('apexplayergarage') == 'started'
    garagePropertySiteOpen = false
    SetNuiFocus(false, false)
    if started and locationId and locationId > 0 then
        garagePurchaseConfirmOpen = true
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'showApexGaragePurchaseConfirm',
            kind = 'purchase',
            locationId = locationId,
            locationName = tostring(data.locationName or 'Garagem APEX'),
            price = tostring(data.price or '$25.000'),
            capacity = tonumber(data.capacity) or 2,
            tier = tonumber(data.tier) or 1
        })
    end
    cb({ ok = started and locationId ~= nil })
end)

RegisterNUICallback('openGarageSiteUpgrade', function(data, cb)
    local capacity = tonumber(data and data.capacity)
    local price = tostring(data and data.price or '$0')
    garagePropertySiteOpen = false
    SetNuiFocus(false, false)
    if capacity and capacity > 0 then
        TriggerEvent('apexnui:openGarageUpgradeConfirm', { capacity = capacity, price = price })
    end
    cb({ ok = capacity ~= nil })
end)

RegisterNetEvent('apexnui:openGarageCatalog', function()
    if GetResourceState('apexgarage_catalog') ~= 'started' then
        return
    end

    if not escMenuState.open then
        openEscMenu()
    end

    garageCatalogOpen = true
    garageCatalogReturnToMultiplayer = false
    SendNUIMessage({ action = 'openApexGarageCatalog' })
    TriggerServerEvent('apexgarage_catalog:requestOpenData')
end)

RegisterNetEvent('apexgarage_catalog:receiveOpenData', function(payload)
    if not garageCatalogOpen and not multiplayerCatalogRequested then
        return
    end
    multiplayerCatalogRequested = false

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local currentVehicle = nil

    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        local displayName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
        local label = displayName and GetLabelText(displayName) or nil
        currentVehicle = {
            model = string.lower(displayName or ''),
            displayName = label and label ~= 'NULL' and label or displayName,
            brand = 'VEÍCULO ATUAL'
        }
    end

    payload = payload or {}
    multiplayerVehicleImages = {}
    multiplayerVehicleDetails = {}
    for _, entry in ipairs(payload.vehicles or {}) do
        local model = string.lower(tostring(entry.model or ''))
        if model ~= '' then
            multiplayerVehicleDetails[model] = {
                displayName = entry.displayName,
                brand = entry.brand,
                image = type(entry.image) == 'string' and entry.image ~= '' and entry.image or nil
            }
            if multiplayerVehicleDetails[model].image then
                multiplayerVehicleImages[model] = multiplayerVehicleDetails[model].image
            end
        end
    end
    if not garageCatalogOpen then
        SendNUIMessage({ action = 'setMultiplayerShowcaseVehicle', vehicle = getMultiplayerVehiclePreview() })
        return
    end

    SendNUIMessage({
        action = 'loadApexGarageCatalog',
        payload = {
            vehicles = payload.vehicles or {},
            currentVehicle = currentVehicle
        }
    })
end)

RegisterNetEvent('apexnui:receiveGarageCatalogData', function(payload)
    SendNUIMessage({ action = 'loadApexGarageCatalog', payload = payload or {} })
end)

RegisterNUICallback('openApexGarageCatalog', function(_, cb)
    if GetResourceState('apexgarage_catalog') ~= 'started' then
        cb({ ok = false })
        return
    end

    garageCatalogOpen = true
    garageCatalogReturnToMultiplayer = false
    SendNUIMessage({ action = 'openApexGarageCatalog' })
    TriggerServerEvent('apexgarage_catalog:requestOpenData')
    cb({ ok = true })
end)

RegisterNUICallback('openMultiplayerVehiclePicker', function(_, cb)
    if GetResourceState('apexgarage_catalog') ~= 'started' then
        cb({ ok = false })
        return
    end

    garageCatalogOpen = true
    garageCatalogReturnToMultiplayer = true
    SendNUIMessage({ action = 'openApexGarageCatalog' })
    TriggerServerEvent('apexgarage_catalog:requestOpenData')
    cb({ ok = true })
end)

RegisterNUICallback('previewApexGarageVehicle', function(data, cb)
    local model = type(data) == 'table' and tostring(data.model or '') or ''
    if not garageCatalogOpen or not model:match('^[%w_%-]+$') then
        cb({ ok = false })
        return
    end

    TriggerEvent('apexnui:previewGarageVehicle', model)
    cb({ ok = true })
end)

RegisterNUICallback('stopApexGaragePreview', function(_, cb)
    TriggerEvent('apexnui:stopGaragePreview', false)
    cb({ ok = true })
end)

RegisterNUICallback('spawnApexGarageVehicle', function(data, cb)
    if GetResourceState('apexgarage_catalog') ~= 'started' or type(data) ~= 'table' then
        cb({ ok = false })
        return
    end

    local returnToMultiplayer = garageCatalogReturnToMultiplayer
    TriggerEvent('apexnui:stopGaragePreview', true)
    TriggerEvent('apexgarage_catalog:spawnFromCatalog', data)
    if returnToMultiplayer then
        garageCatalogOpen = false
        garageCatalogReturnToMultiplayer = false
        SendNUIMessage({ action = 'returnToMultiplayer' })
        CreateThread(function()
            local deadline = GetGameTimer() + 10000
            repeat
                Wait(250)
                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle ~= 0 and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped then
                    break
                end
            until GetGameTimer() >= deadline
            Wait(500)
            SendNUIMessage({ action = 'setMultiplayerShowcaseVehicle', vehicle = getMultiplayerVehiclePreview() })
        end)
    else
        closeEscMenu()
    end
    cb({ ok = true })
end)

RegisterNUICallback('setHudOption', function(data, cb)
    local option = data and data.option
    local value = data and data.value

    if option == 'speedUnit' and (value == 'kmh' or value == 'mph') then
        hudSettings.speedUnit = value
    elseif option == 'speedometerType' and (value == 'apexnui' or value == 'svg') then
        hudSettings.speedometerType = value
    else
        cb({ ok = false })
        return
    end

    saveHudSettings()
    updateSpeedUnitDisplay()
    updateHintState(true)
    updateSpeedState(true)
    cb({ ok = true })
end)

RegisterNUICallback('setEnvironmentTime', function(data, cb)
    local hour = data and data.hour or 18
    local minute = data and data.minute or 0
    environmentState.locked = true
    applyEnvironmentTime(hour, minute)
    refreshEscMenuContext()
    cb({ ok = true, time = environmentState.time, minute = environmentState.minute })
end)

RegisterNUICallback('setEnvironmentWeather', function(data, cb)
    local weatherId = data and data.weather or 'clear'
    environmentState.locked = true
    applyEnvironmentWeather(weatherId)
    refreshEscMenuContext()
    cb({ ok = true, weather = environmentState.weather })
end)

RegisterNUICallback('resetEnvironment', function(_, cb)
    environmentState.locked = false
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    NetworkClearClockTimeOverride()
    environmentState.time = GetClockHours()
    environmentState.minute = GetClockMinutes()
    environmentState.weather = getCurrentWeatherType()
    refreshEscMenuContext()
    cb({ ok = true })
end)

RegisterNUICallback('setEnvironmentLock', function(data, cb)
    local enabled = data and data.enabled == true
    environmentState.locked = enabled

    if enabled then
        environmentState.time = GetClockHours()
        environmentState.minute = GetClockMinutes()
        environmentState.weather = getCurrentWeatherType()
        applyEnvironmentTime(environmentState.time, environmentState.minute)
        applyEnvironmentWeather(environmentState.weather)
    end

    refreshEscMenuContext()
    cb({ ok = true, enabled = environmentState.locked })
end)

-- Compatibilidade com a versão anterior do menu.
RegisterNUICallback('setEnvironmentServerSync', function(data, cb)
    local enabled = data and data.enabled == true
    environmentState.locked = enabled
    refreshEscMenuContext()
    cb({ ok = true, enabled = environmentState.locked })
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

-- ================= Corridas (aba do esc-menu) =================
-- Ligacao real com o apexracing: Pistas verificadas / Treino /
-- Tomada de tempo listam as mesmas pistas cadastradas no apexracing;
-- Criar corrida abre o editor de pistas do apexracing.

RegisterNUICallback('getApexRaceTracks', function(data, cb)
    requestRaceTracks(data and data.forceRefresh == true)
    cb({ ok = true })
end)

RegisterNUICallback('getMyApexTracks', function(_, cb)
    if GetResourceState('apexracing') ~= 'started' then
        cb({ ok = false })
        return
    end
    TriggerServerEvent('racing:requestMyTracksList')
    cb({ ok = true })
end)

RegisterNetEvent('racing:receiveMyTracksList', function(tracks)
    SendNUIMessage({ action = 'loadApexMyTracks', tracks = type(tracks) == 'table' and tracks or {} })
end)

RegisterNetEvent('apexnui:openTrackCreatorPage', function()
    openEscMenu()
    SendNUIMessage({ action = 'openApexCreatorPage' })
end)

RegisterNUICallback('startApexNewTrack', function(_, cb)
    if not trackCreatorCanCreate then
        notify('Apenas Master ou Dev podem criar pistas.', 'error')
        cb({ ok = false, denied = true })
        return
    end
    if GetResourceState('apexracing') ~= 'started' then
        notify('O recurso apexracing nao esta iniciado.', 'error')
        cb({ ok = false })
        return
    end
    closeEscMenu()
    TriggerEvent('racing:beginTrackCreationFreecam')
    cb({ ok = true })
end)

-- Recordes reais de uma pista (tabela apex_records). O apexracing ja expoe
-- esse fluxo via evento global (usado antes pelo nui/app.js proprio dele);
-- aqui so repassamos para a NUI unificada.
RegisterNUICallback('getApexTrackRecords', function(data, cb)
    local trackId = tonumber(data and data.trackId)
    if not trackId then
        cb({ ok = false })
        return
    end

    TriggerServerEvent('racing:requestTrackRecords', trackId)
    cb({ ok = true })
end)

RegisterNetEvent('racing:receiveTrackRecords', function(trackId, records)
    SendNUIMessage({ action = 'loadApexTrackRecords', trackId = trackId, records = records })
end)

-- Abrir o editor de uma pista ja existente (usado pelo botao "Editar pista"
-- em Pistas verificadas). Mesma ideia de racing:beginTrackCreation: um
-- evento de cliente global, sem NUI callback proprio, com a permissao
-- sempre confirmada no servidor antes de abrir o editor.
RegisterNUICallback('startApexTrackEdit', function(data, cb)
    if not trackCreatorCanCreate then
        notify('Apenas Master ou Dev podem editar pistas.', 'error')
        cb({ ok = false, denied = true })
        return
    end
    if GetResourceState('apexracing') ~= 'started' then
        notify('O recurso apexracing nao esta iniciado.', 'error')
        cb({ ok = false })
        return
    end

    local trackId = tonumber(data and data.trackId)
    if not trackId then
        cb({ ok = false })
        return
    end

    closeEscMenu()
    TriggerEvent('racing:beginTrackEdit', trackId)

    cb({ ok = true })
end)

local function getCurrentVehicleForRace()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
        return true
    end
    return false
end

local function startApexSoloRace(trackId, mode, laps)
    if GetResourceState('apexracing') ~= 'started' then
        notify('O recurso apexracing nao esta iniciado.', 'error')
        return
    end

    trackId = tonumber(trackId)
    if not trackId then return end

    if not getCurrentVehicleForRace() then
        notify('Entre em um veiculo como motorista para comecar.', 'error')
        return
    end

    local raceContext = {
        mode = (mode == 'practice') and 'practice' or 'solo',
        showRacingLine = true,
        showGhost = true
    }

    closeEscMenu()
    TriggerServerEvent('racing:requestTrackData', trackId, nil, math.max(1, math.min(50, tonumber(laps) or 3)), true, raceContext)
end

RegisterNUICallback('startApexPractice', function(data, cb)
    startApexSoloRace(data and data.trackId, 'practice', data and data.laps)
    cb({ ok = true })
end)

RegisterNUICallback('startApexTimeTrial', function(data, cb)
    startApexSoloRace(data and data.trackId, 'solo', data and data.laps)
    cb({ ok = true })
end)

RegisterNUICallback('startApexTrackCreation', function(_, cb)
    if not trackCreatorCanCreate then
        notify('Apenas Master ou Dev podem criar pistas.', 'error')
        cb({ ok = false, denied = true })
        return
    end
    if GetResourceState('apexracing') ~= 'started' then
        notify('O recurso apexracing nao esta iniciado.', 'error')
        cb({ ok = false })
        return
    end

    -- Esta entrada abre a nova página de pistas do jogador; a freecam só
    -- começa quando ele seleciona "Nova corrida" nessa página.
    closeEscMenu()
    TriggerEvent('racing:beginTrackCreation')

    cb({ ok = true })
end)

RegisterNUICallback('closeRadialMenu', function(_, cb)
    closeRadialMenu()
    cb({ ok = true })
end)

RegisterNUICallback('closeVehicleQuickMenu', function(_, cb)
    closeVehicleQuickMenu()
    cb({ ok = true })
end)

vehicleQuickMenuState.runAction = function(data, cb)
    if not vehicleQuickMenuState.open then
        cb({ ok = false })
        return
    end

    local vehicle = vehicleQuickMenuState.vehicle
    local ped = PlayerPedId()
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetVehiclePedIsIn(ped, false) ~= vehicle then
        closeVehicleQuickMenu()
        cb({ ok = false })
        return
    end

    local actionId = data and tostring(data.actionId or '') or ''
    if actionId == 'engine' then
        SetVehicleEngineOn(vehicle, not GetIsVehicleEngineRunning(vehicle), true, true)
    elseif actionId == 'hazards' then
        local hazardsOn = GetVehicleIndicatorLights(vehicle) == 3
        SetVehicleIndicatorLights(vehicle, 0, not hazardsOn)
        SetVehicleIndicatorLights(vehicle, 1, not hazardsOn)
    elseif actionId == 'doors' then
        if GetEntitySpeed(vehicle) > 0.5 then
            closeVehicleQuickMenu()
            cb({ ok = false, reason = 'moving' })
            return
        end

        local doorCount = GetNumberOfVehicleDoors(vehicle)
        for doorIndex = 0, doorCount - 1 do
            SetVehicleDoorOpen(vehicle, doorIndex, false, false)
        end
    elseif actionId == 'repair' then
        if GetEntitySpeed(vehicle) > 0.5 then
            closeVehicleQuickMenu()
            cb({ ok = false, reason = 'moving' })
            return
        end

        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehicleUndriveable(vehicle, false)
    else
        cb({ ok = false })
        return
    end

    closeVehicleQuickMenu()
    cb({ ok = true })
end

RegisterNUICallback('vehicleQuickMenuAction', vehicleQuickMenuState.runAction)

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

RegisterNetEvent('racing:receiveTracksList')
AddEventHandler('racing:receiveTracksList', function(tracks)
    raceTracksState.loading = false
    raceTracksState.tracks = {}

    if type(tracks) == 'table' then
        for i = 1, #tracks do
            local normalized = normalizeRaceTrackEntry(tracks[i])
            if normalized then
                raceTracksState.tracks[#raceTracksState.tracks + 1] = normalized
            end
        end
    end

    sendRaceTracksToNui()
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
    environmentState.time = GetClockHours()
    environmentState.minute = GetClockMinutes()

    while true do
        if environmentState.locked then
            -- Travado: reforca o horario/clima escolhido a cada segundo.
            NetworkOverrideClockTime(environmentState.time, environmentState.minute or 0, 0)
            SetWeatherTypePersist(environmentState.weather)
            SetWeatherTypeNowPersist(environmentState.weather)
        elseif escMenuState.open then
            -- Destravado: o relogio nativo do jogo corre sozinho (minuto a
            -- minuto). So atualizamos o menu pra ele mostrar a hora certa.
            refreshEscMenuContext()
        end
        Wait(1000)
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
        -- O velocímetro continua ativo na corrida, com atualização suficiente
        -- para leitura e menos consultas enquanto o HUD da prova está em uso.
        Wait(raceState.active and 100 or 75)
    end
end)

CreateThread(function()
    while true do
        -- Teclado: Z (abre/fecha). Controle: seta para a esquerda abre; Bolinha fecha.
        local usingKeyboard = hintState.inputOverride == 'keyboard'
            or (hintState.inputOverride == nil and IsInputDisabled(2))
        local fixedZPressed
        if usingKeyboard then
            fixedZPressed = IsControlJustPressed(0, 20) or IsDisabledControlJustPressed(0, 20)
        else
            fixedZPressed = not vehicleQuickMenuState.open
                and (IsControlJustPressed(0, 174) or IsDisabledControlJustPressed(0, 174))
        end
        if fixedZPressed then
            if vehicleQuickMenuState.open then
                closeVehicleQuickMenu()
            elseif not escMenuState.open and not radialMenuState.open and not IsNuiFocused() and not IsPauseMenuActive() then
                openVehicleQuickMenu()
            end
        end

        local customMenuOpen = escMenuState.open or radialMenuState.open or vehicleQuickMenuState.open
        local anotherNuiFocused = IsNuiFocused() and not customMenuOpen

        if isTrackCreatorActive() then
            -- O ESC/Pause não deve interromper o editor de pista nem abrir o menu global.
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
            SetPauseMenuActive(false)
        elseif nativeSettingsOnlyOpen then
            maintainNativeSettingsOnly()
        elseif apexMapOpen or nativeMapOnlyOpen then
            maintainNativeMapOnly()
        elseif customMenuOpen then
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
        elseif not anotherNuiFocused and not IsPauseMenuActive() then
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)

            if IsDisabledControlJustPressed(0, 199) or IsDisabledControlJustPressed(0, 200) then
                SetPauseMenuActive(false)
                openEscMenu()
            end
        end

        Wait(0)
    end
end)

CreateThread(function()
    while true do
        maintainNativeMapOnly()
        -- O controle do frontend só precisa rodar por frame enquanto o mapa
        -- nativo está aberto; em jogo normal não há trabalho nesse loop.
        Wait(nativeMapOnlyOpen and 0 or 250)
    end
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local shouldShowRadar = hudSettings.hudEnabled and not escMenuState.open and not radialMenuState.open and IsPedInAnyVehicle(ped, false)

        if nativeSettingsOnlyOpen or apexMapOpen or nativeMapOnlyOpen then
            -- O frontend nativo cuida do mapa em tela cheia. Não force o
            -- radar/bigmap aqui, pois isso cria o mapa pequeno no mundo.
            DisplayHud(false)
            DisplayRadar(false)
        elseif hudSettings.hudEnabled and not escMenuState.open and not radialMenuState.open then
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
    if resourceName == 'apexracing' then
        SetTimeout(800, requestTrackCreatorPermission)
        return
    end
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    SetTimeout(1200, requestTrackCreatorPermission)

    nativeMapOnlyOpen = false
    apexMapOpen = false
    nativeSettingsOnlyOpen = false
    SetRadarBigmapEnabled(false, false)
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'setEscMenuState',
        visible = false
    })
    SendNUIMessage({
        action = 'setRadialMenuState',
        visible = false
    })
    SendNUIMessage({
        action = 'setVehicleQuickMenuState',
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
        vehicleQuickMenuState.open = false
        vehicleQuickMenuState.vehicle = 0
        nativeMapOnlyOpen = false
        apexMapOpen = false
        nativeSettingsOnlyOpen = false
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

-- ================= Online / Matchmaking (aba do esc-menu) =================
-- Sala automatica do apexracing (auto-hoster). Aqui so repassamos os
-- mesmos eventos de rede que ja existem no apexracing para a NUI nova.

RegisterNUICallback('getApexAutoHostState', function(_, cb)
    TriggerServerEvent('racing:requestAutoHostState')
    cb({ ok = true })
end)

RegisterNUICallback('joinApexAutoHost', function(data, cb)
    local lobbyId = data and tonumber(data.lobbyId)
    if not lobbyId then
        cb({ ok = false })
        return
    end

    TriggerServerEvent('racing:joinLobby', lobbyId)
    cb({ ok = true })
end)

RegisterNUICallback('leaveApexAutoHost', function(_, cb)
    TriggerServerEvent('racing:leaveLobby')
    cb({ ok = true })
end)

RegisterNUICallback('sendApexLobbyChat', function(data, cb)
    local message = data and tostring(data.message or ''):sub(1, 140) or ''
    if message == '' then
        cb({ ok = false })
        return
    end

    TriggerServerEvent('racing:sendLobbyChat', message)
    cb({ ok = true })
end)

RegisterNUICallback('voteApexAutoHost', function(data, cb)
    local choice = data and data.choice
    if not choice then
        cb({ ok = false })
        return
    end

    TriggerServerEvent('racing:autoHostVote', choice)
    cb({ ok = true })
end)

RegisterNetEvent('racing:autoHostState', function(state)
    SendNUIMessage({ action = 'loadApexAutoHostState', state = state })
end)

RegisterNetEvent('racing:openLobbyRoom', function(room)
    SendNUIMessage({ action = 'loadApexLobbyRoom', room = room })
end)

RegisterNetEvent('racing:closeLobbyRoom', function()
    SendNUIMessage({ action = 'closeApexLobbyRoom' })
end)

-- ============================================================
-- Entrada: teclado x controle (PlayStation)
-- A NUI troca os glifos (ESC/Z/1-4 -> Options/D-pad/X O [] /\) conforme o modo.
-- Para forcar manualmente: /apexnui_inputmode auto | teclado | controle
-- Estilo dos icones do controle (salvo): /apexnui_padstyle playstation | xbox
-- (hintState e usado como tabela de estado para nao criar novos locals)
-- ============================================================
hintState.inputOverride = nil
hintState.inputMode = 'keyboard'
hintState.padStyle = GetResourceKvpString('apexnui:padStyle') == 'xbox' and 'xbox' or 'playstation'

CreateThread(function()
    local lastSent, lastSentAt = nil, 0
    while true do
        local mode = hintState.inputOverride
        if not mode then
            -- IsInputDisabled(2) = true enquanto o jogador usa teclado/mouse
            mode = IsInputDisabled(2) and 'keyboard' or 'gamepad'
        end
        hintState.inputMode = mode

        local now = GetGameTimer()
        local signature = mode .. ':' .. hintState.padStyle
        if signature ~= lastSent or now - lastSentAt > 5000 then
            lastSent, lastSentAt = signature, now
            SendNUIMessage({ action = 'setInputMode', mode = mode, padStyle = hintState.padStyle })
        end
        Wait(250)
    end
end)

RegisterCommand('apexnui_inputmode', function(_, args)
    local value = tostring(args[1] or 'auto'):lower()
    if value == 'teclado' or value == 'keyboard' then
        hintState.inputOverride = 'keyboard'
    elseif value == 'controle' or value == 'gamepad' or value == 'pad' then
        hintState.inputOverride = 'gamepad'
    else
        hintState.inputOverride = nil
    end
    print(('[apexnui] modo de entrada: %s'):format(hintState.inputOverride or 'auto'))
end, false)

RegisterCommand('apexnui_padstyle', function(_, args)
    local value = tostring(args[1] or ''):lower()
    if value == 'xbox' then
        hintState.padStyle = 'xbox'
    elseif value == 'playstation' or value == 'ps' or value == 'ps5' or value == 'ps4' then
        hintState.padStyle = 'playstation'
    else
        print('[apexnui] uso: /apexnui_padstyle playstation | xbox')
        return
    end
    SetResourceKvp('apexnui:padStyle', hintState.padStyle)
    print(('[apexnui] icones do controle: %s'):format(hintState.padStyle))
end, false)

-- Atalhos do veiculo no controle (menu aberto com a seta da esquerda):
-- esquerda = ligar/desligar, baixo = pisca alerta, direita = portas, cima = reparar.
-- Bolinha (ou Options) fecha.
CreateThread(function()
    local function pressed(control)
        return IsControlJustPressed(0, control) or IsDisabledControlJustPressed(0, control)
    end

    local wasOpen = false
    while true do
        if vehicleQuickMenuState.open and hintState.inputMode == 'gamepad' then
            if not wasOpen then
                -- o mesmo toque que abriu o menu nao pode acionar uma opcao
                wasOpen = true
            elseif pressed(174) then -- seta esquerda
                vehicleQuickMenuState.runAction({ actionId = 'engine' }, function() end)
            elseif pressed(173) then -- seta baixo
                vehicleQuickMenuState.runAction({ actionId = 'hazards' }, function() end)
            elseif pressed(175) then -- seta direita
                vehicleQuickMenuState.runAction({ actionId = 'doors' }, function() end)
            elseif pressed(172) then -- seta cima
                vehicleQuickMenuState.runAction({ actionId = 'repair' }, function() end)
            elseif pressed(202) or pressed(199) or pressed(200) then -- Bolinha / Options
                closeVehicleQuickMenu()
            end
            Wait(0)
        else
            wasOpen = false
            Wait(150)
        end
    end
end)

-- Diagnostico do ABS/HBK: /apexnui_debugpedals (liga/desliga) mostra no F8 os valores dos controles
RegisterCommand('apexnui_debugpedals', function()
    hintState.debugPedals = not hintState.debugPedals
    print(('[apexnui] debug pedais: %s'):format(hintState.debugPedals and 'ligado' or 'desligado'))
    if not hintState.debugPedals then return end
    CreateThread(function()
        while hintState.debugPedals do
            print(('freio(72) normal=%.2f pressed=%s | freio de mao(76) normal=%.2f pressed=%s | acelerar(71) normal=%.2f | modo=%s'):format(
                GetControlNormal(0, 72), tostring(IsControlPressed(0, 72)),
                GetControlNormal(0, 76), tostring(IsControlPressed(0, 76)),
                GetControlNormal(0, 71), tostring(hintState.inputMode)))
            Wait(500)
        end
    end)
end, false)
