-- Discord Rich Presence para Apex Racing.
-- Configure no server.cfg e envie o asset correspondente no Discord Developer Portal:
-- setr apexnui_discord_app_id "ID_DA_APLICACAO"
-- setr apexnui_discord_server_asset "apex_logo"
-- setr apexnui_discord_server_name "Apex Racing"

local appId, serverAsset, serverName = '', 'apex_logo', 'Apex Racing'
local activeRace = nil
local lastPresence = nil
local warnedMissingAppId = false
local presenceConfigured = false
local testPresenceUntil = 0

local function cleanText(value, fallback)
    local text = tostring(value or ''):gsub('[\r\n]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then return fallback end
    return text
end

local function configureDiscordPresence()
    local configuredAppId = GetConvar('apexnui_discord_app_id', '')
    local configuredAsset = GetConvar('apexnui_discord_server_asset', 'apex_logo')
    local configuredName = GetConvar('apexnui_discord_server_name', 'Apex Racing')
    if configuredAppId == '' or configuredAppId == 'ID_DA_APLICACAO' then
        presenceConfigured = false
        return false
    end

    if not presenceConfigured or appId ~= configuredAppId then
        appId = configuredAppId
        SetDiscordAppId(appId)
        presenceConfigured = true
        lastPresence = nil
        print('[apexnui] Discord Presence: Application ID recebido pelo cliente.')
    end

    if serverAsset ~= configuredAsset or serverName ~= configuredName then
        serverAsset, serverName = configuredAsset, configuredName
        if serverAsset ~= '' then SetDiscordRichPresenceAsset(serverAsset) end
        SetDiscordRichPresenceAssetText(serverName)
        lastPresence = nil
    end
    warnedMissingAppId = false
    return true
end

local function setPresence(text)
    text = cleanText(text, serverName)
    if text == lastPresence then return end
    lastPresence = text
    SetRichPresence(text:sub(1, 120))
end

local function getVehicleName()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return 'A pé' end

    local modelHash = GetEntityModel(vehicle)
    if GetResourceState('apexgarage_catalog') == 'started' then
        local ok, catalogDisplayName = pcall(function()
            return exports['apexgarage_catalog']:GetDiscordVehicleDisplayName(modelHash)
        end)
        if ok and type(catalogDisplayName) == 'string' and catalogDisplayName ~= '' then
            return catalogDisplayName
        end
    end

    local displayName = GetDisplayNameFromVehicleModel(modelHash)
    if displayName and displayName ~= '' and displayName ~= 'CARNOTFOUND' then
        local label = GetLabelText(displayName)
        if label and label ~= '' and label ~= 'NULL' then return label end
        return displayName
    end

    return 'Veículo'
end

local function getLocationName()
    local coords = GetEntityCoords(PlayerPedId())
    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = streetHash and GetStreetNameFromHashKey(streetHash) or ''
    local zone = GetNameOfZone(coords.x, coords.y, coords.z)
    local zoneLabel = zone and GetLabelText(zone) or ''
    if not zoneLabel or zoneLabel == '' or zoneLabel == 'NULL' then zoneLabel = zone or '' end

    if street and street ~= '' and zoneLabel ~= '' then return street .. ', ' .. zoneLabel end
    if street and street ~= '' then return street end
    if zoneLabel ~= '' then return zoneLabel end
    return 'Los Santos'
end

local function refreshPresence()
    if not configureDiscordPresence() then return end
    if activeRace then
        local raceName = cleanText(activeRace.name, 'Corrida')
        local mode = activeRace.mode
        if mode == 'practice' then
            setPresence(('%s | Treino'):format(raceName))
        elseif mode == 'solo' then
            setPresence(('%s | Contra-tempo'):format(raceName))
        elseif activeRace.trackType == 'circuit' then
            setPresence(('%s | Volta %d/%d | Posição %d/%d'):format(
                raceName,
                tonumber(activeRace.currentLap) or 1,
                tonumber(activeRace.totalLaps) or 1,
                tonumber(activeRace.position) or 1,
                tonumber(activeRace.totalPlayers) or 1
            ))
        else
            setPresence(('%s | Sprint | Posição %d/%d'):format(
                raceName,
                tonumber(activeRace.position) or 1,
                tonumber(activeRace.totalPlayers) or 1
            ))
        end
        return
    end

    setPresence(('%s | %s | Modo livre'):format(getVehicleName(), getLocationName()))
end

configureDiscordPresence()

RegisterNetEvent('apexnui:discordRacePresence', function(data)
    if type(data) ~= 'table' or data.active ~= true then
        activeRace = nil
    else
        activeRace = {
            name = data.name,
            trackType = data.trackType == 'circuit' and 'circuit' or 'sprint',
            mode = data.mode == 'lobby' and 'lobby' or (data.mode == 'practice' and 'practice' or 'solo'),
            currentLap = data.currentLap,
            totalLaps = data.totalLaps,
            position = data.position,
            totalPlayers = data.totalPlayers
        }
    end
    lastPresence = nil
    refreshPresence()
end)

CreateThread(function()
    while true do
        if not configureDiscordPresence() then
            if not warnedMissingAppId then
                print('[apexnui] Discord Presence aguardando apexnui_discord_app_id no server.cfg.')
                warnedMissingAppId = true
            end
            Wait(3000)
        elseif GetGameTimer() < testPresenceUntil then
            Wait(1000)
        else
            refreshPresence()
            Wait(15000)
        end
    end
end)

RegisterCommand('apexpresence', function()
    if not configureDiscordPresence() then
        print('[apexnui] TESTE FALHOU: o cliente não recebeu apexnui_discord_app_id. Confira o setr no server.cfg e reconecte.')
        return
    end

    activeRace = nil
    lastPresence = nil
    SetRichPresence('Apex Racing | Teste de presença')
    lastPresence = 'Apex Racing | Teste de presença'
    testPresenceUntil = GetGameTimer() + 15000
    print('[apexnui] Teste enviado: Apex Racing | Teste de presença. Confira seu perfil no Discord por 15 segundos.')
end, false)
