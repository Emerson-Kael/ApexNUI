ApexRadialMenuActions = {
    handlers = {},
    pageBuilders = {}
}

local radialRootItems = {}
local radialMenus = {}

local antilagSoundEffects = {
    sultan2 = true,
    default = true,
    superv8 = true,
    vacca = true,
    eurosz = true,
    toysupmk4 = true,
    murcisp = true,
    subej22 = true,
    default2 = true,
    default3 = true,
    antilagold = true
}

local antilagColors = {
    blue = true,
    pink = true,
    purple = true,
    red = true,
    natural = true,
    aqua = true
}

local function getRadialNotify(ctx)
    if type(ctx) == 'table' and type(ctx.notify) == 'function' then
        return ctx.notify
    end

    return function()
    end
end

local function getSmpConfigAntilagContext()
    local context = {
        resourceStarted = GetResourceState('smp-config') == 'started',
        inVehicle = false,
        vehicle = 0,
        hasAntilag = false,
        systemEnabled = false,
        sound = 'default',
        color = nil
    }

    if not context.resourceStarted then
        return context
    end

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        return context
    end

    context.vehicle = GetVehiclePedIsIn(ped, false)
    context.inVehicle = context.vehicle ~= 0

    local okHasAntilag, hasAntilag = pcall(function()
        return exports['smp-config']:HasAntilag()
    end)

    if okHasAntilag then
        context.hasAntilag = hasAntilag == true
    end

    local okStatus, status = pcall(function()
        return exports['smp-config']:StatusAntilag()
    end)

    if okStatus then
        context.systemEnabled = status == true
    end

    if context.inVehicle and context.vehicle ~= 0 then
        local state = Entity(context.vehicle).state.Antilag
        if type(state) == 'table' then
            if type(state.sound) == 'string' and antilagSoundEffects[state.sound] then
                context.sound = state.sound
            end

            if type(state.color) == 'string' and antilagColors[state.color] then
                context.color = state.color
            end
        end
    end

    return context
end

local function setSmpConfigAntilagInstalled(shouldEnable, ctx, soundType, color)
    local context = getSmpConfigAntilagContext()
    local notify = getRadialNotify(ctx)

    if not context.resourceStarted then
        notify('O recurso smp-config nao esta iniciado.', 'error')
        return false
    end

    if not context.inVehicle or context.vehicle == 0 then
        notify('Entre em um veiculo para configurar o Antilag.', 'warning')
        return false
    end

    local nextSound = (type(soundType) == 'string' and antilagSoundEffects[soundType]) and soundType or context.sound or 'default'
    local nextColor = (type(color) == 'string' and antilagColors[color]) and color or context.color

    TriggerServerEvent('smp-config:server:SetAntilag', VehToNet(context.vehicle), shouldEnable, nextSound, nextColor)

    return true
end

local function toggleSmpConfigAntilagSystem(ctx)
    local context = getSmpConfigAntilagContext()
    local notify = getRadialNotify(ctx)

    if not context.resourceStarted then
        notify('O recurso smp-config nao esta iniciado.', 'error')
        return false
    end

    local ok = pcall(function()
        exports['smp-config']:ToggleAntilag()
    end)

    if not ok then
        notify('Nao foi possivel alternar o Antilag do smp-config.', 'error')
        return false
    end

    local enabled = not context.systemEnabled
    local okStatus, status = pcall(function()
        return exports['smp-config']:StatusAntilag()
    end)

    if okStatus then
        enabled = status == true
    end

    return true, enabled
end

local defaultNitroFuelAmount = 2000

local function getSmpConfigNitroContext()
    local context = {
        resourceStarted = GetResourceState('smp-config') == 'started',
        inVehicle = false,
        vehicle = 0,
        hasNitro = false,
        fuel = 0,
        color = nil
    }

    if not context.resourceStarted then
        return context
    end

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        return context
    end

    context.vehicle = GetVehiclePedIsIn(ped, false)
    context.inVehicle = context.vehicle ~= 0

    if context.inVehicle and context.vehicle ~= 0 then
        local fuel = tonumber(Entity(context.vehicle).state.Nitro) or 0
        local color = Entity(context.vehicle).state.NitroColor

        context.fuel = math.max(0, math.floor(fuel))
        context.hasNitro = context.fuel >= 1

        if type(color) == 'string' and antilagColors[color] then
            context.color = color
        end
    end

    return context
end

local function setSmpConfigNitroInstalled(shouldEnable, ctx, fuelAmount, color)
    local context = getSmpConfigNitroContext()
    local notify = getRadialNotify(ctx)

    if not context.resourceStarted then
        notify('O recurso smp-config nao esta iniciado.', 'error')
        return false
    end

    if not context.inVehicle or context.vehicle == 0 then
        notify('Entre em um veiculo para configurar o Nitro.', 'warning')
        return false
    end

    local nextFuel = tonumber(fuelAmount)
    if nextFuel then
        nextFuel = math.max(1, math.floor(nextFuel))
    else
        nextFuel = context.hasNitro and context.fuel or defaultNitroFuelAmount
    end

    local nextColor = (type(color) == 'string' and antilagColors[color]) and color or context.color

    TriggerServerEvent('smp-config:server:SetNitro', VehToNet(context.vehicle), shouldEnable, nextFuel, nextColor)

    return true
end

local function toggleSmpConfigNitroInstalled(ctx)
    local context = getSmpConfigNitroContext()
    local notify = getRadialNotify(ctx)

    if not context.resourceStarted then
        notify('O recurso smp-config nao esta iniciado.', 'error')
        return false
    end

    if not context.inVehicle or context.vehicle == 0 then
        notify('Entre em um veiculo para configurar o Nitro.', 'warning')
        return false
    end

    local enabled = not context.hasNitro
    local nextFuel = enabled and (context.hasNitro and context.fuel or defaultNitroFuelAmount) or defaultNitroFuelAmount
    local nextColor = enabled and context.color or nil

    TriggerServerEvent('smp-config:server:SetNitro', VehToNet(context.vehicle), enabled, nextFuel, nextColor)

    return true, enabled
end

local function cloneRadialEntry(entry)
    local clone = {}

    if type(entry) ~= 'table' then
        return clone
    end

    for key, value in pairs(entry) do
        clone[key] = value
    end

    return clone
end

local function appendRadialEntry(target, entry)
    if type(entry) ~= 'table' then
        return
    end

    target[#target + 1] = cloneRadialEntry(entry)
end

function addRadialItem(items)
    if type(items) ~= 'table' then
        return
    end

    if items[1] ~= nil then
        for index = 1, #items do
            appendRadialEntry(radialRootItems, items[index])
        end

        return
    end

    appendRadialEntry(radialRootItems, items)
end

function registerRadial(definition)
    if type(definition) ~= 'table' or type(definition.id) ~= 'string' then
        return
    end

    local items = {}
    local sourceItems = type(definition.items) == 'table' and definition.items or {}

    for index = 1, #sourceItems do
        appendRadialEntry(items, sourceItems[index])
    end

    radialMenus[definition.id] = {
        id = definition.id,
        label = definition.label,
        defaultItem = definition.defaultItem,
        items = items
    }
end

local function buildRadialConfigItem(sourceItem, defaultKicker)
    local itemId = type(sourceItem.id) == 'string' and sourceItem.id or ('item_' .. tostring(math.random(1000, 9999)))
    local targetItem = {
        id = itemId,
        label = type(sourceItem.label) == 'string' and sourceItem.label or itemId,
        kicker = type(sourceItem.kicker) == 'string' and sourceItem.kicker or defaultKicker or 'Apex',
        icon = type(sourceItem.icon) == 'string' and sourceItem.icon or nil,
        enabled = sourceItem.enabled ~= false and sourceItem.disabled ~= true
    }

    local targetPage = sourceItem.menu
    if type(targetPage) ~= 'string' or targetPage == '' then
        targetPage = sourceItem.page
    end

    if type(targetPage) == 'string' and targetPage ~= '' then
        targetItem.page = targetPage
    end

    if sourceItem.onSelect ~= nil then
        targetItem.action = sourceItem.onSelect
    elseif sourceItem.action ~= nil then
        targetItem.action = sourceItem.action
    end

    local slot = tonumber(sourceItem.slot)
    if slot then
        targetItem.slot = math.floor(slot)
    end

    return targetItem
end

local function resolveDefaultItem(items, configuredDefault)
    if type(configuredDefault) == 'string' then
        for index = 1, #items do
            if items[index].id == configuredDefault then
                return configuredDefault
            end
        end
    end

    return items[1] and items[1].id or nil
end

local function buildRegisteredPage(menuId, parentPage, parentItemId, pages, visited)
    if visited[menuId] then
        return
    end

    local menuDefinition = radialMenus[menuId]
    if type(menuDefinition) ~= 'table' then
        return
    end

    visited[menuId] = true

    local defaultKicker = type(menuDefinition.label) == 'string' and menuDefinition.label or 'Menu'
    local pageItems = {}

    for index = 1, #menuDefinition.items do
        pageItems[#pageItems + 1] = buildRadialConfigItem(menuDefinition.items[index], defaultKicker)
    end

    pages[menuId] = {
        parent = parentPage,
        parentItem = parentItemId,
        defaultItem = resolveDefaultItem(pageItems, menuDefinition.defaultItem),
        items = pageItems
    }

    for index = 1, #pageItems do
        local item = pageItems[index]
        if type(item.page) == 'string' and radialMenus[item.page] then
            buildRegisteredPage(item.page, menuId, item.id, pages, visited)
        end
    end
end

local function buildRootPage()
    local pages = {}
    local visited = {}
    local rootItems = {}

    for index = 1, #radialRootItems do
        rootItems[#rootItems + 1] = buildRadialConfigItem(radialRootItems[index], 'Apex')
    end

    pages.root = {
        defaultItem = resolveDefaultItem(rootItems, nil),
        items = rootItems
    }

    for index = 1, #rootItems do
        local item = rootItems[index]
        if type(item.page) == 'string' and radialMenus[item.page] then
            buildRegisteredPage(item.page, 'root', item.id, pages, visited)
        end
    end

    return {
        rootPage = 'root',
        pages = pages
    }
end

-- =====================================
-- CONFIGURE TUDO DO RADIAL SO NESTE PARTE
-- =====================================

addRadialItem({
    {
        id = 'tuning',
        label = 'Tunagem',
        icon = 'screwdriver-wrench',
        menu = 'tuning_menu',
        kicker = 'Apex'
    },
    {
        id = 'settings',
        label = 'settings',
        icon = 'gears',
        menu = 'settings_menu',
        kicker = 'configuraÃƒÂ§ÃƒÂµes'
    },
    {
        id = 'salvarmods',
        label = 'salvar tunagem',
        icon = 'folder',
        kicker = 'Salvar',
        onSelect = function(ctx)
            ExecuteCommand('salvarmods')
        end
    },
})

registerRadial({
    id = 'tuning_menu',
    label = 'Tunagem',
    items = {
        {
            id = 'antilag',
            label = 'Antilag',
            icon = 'fire',
            menu = 'antilag_menu',
            kicker = 'Tunagem'
        },
        {
            id = 'nitro',
            label = 'Nitro',
            icon = 'bolt',
            menu = 'nitro_menu',
            kicker = 'Tunagem'
        }
    }
})

registerRadial({
    id = 'antilag_menu',
    label = 'Antilag',
    items = {
        {
            id = 'toggle',
            label = 'Ativar/Desligar',
            icon = 'power-off',
            kicker = 'Sistema',
            onSelect = function(ctx)
                local ok, enabled = toggleSmpConfigAntilagSystem(ctx)

                if ok then
                    ctx.notify(
                        enabled and 'Antilag ativado' or 'Antilag desligado',
                        enabled and 'success' or 'warning'
                    )
                    ctx.refresh()
                end
            end
        },
        {
            id = 'sound',
            label = 'Som',
            icon = 'volume-high',
            menu = 'antilag_sound_menu',
            kicker = 'Antilag'
        },
        {
            id = 'colors',
            label = 'Cores',
            icon = 'palette',
            menu = 'antilag_color_menu',
            kicker = 'Antilag'
        },
    }
})

registerRadial({
    id = 'antilag_sound_menu',
    label = 'Som',
    items = {
        {
            id = 'sultan2',
            label = 'sultan2',
            icon = 'volume-high',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, 'sultan2', nil) then
                    ctx.notify('Som do antilag selecionado: sultan2', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'default',
            label = 'Default',
            icon = 'volume-high',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, 'default', nil) then
                    ctx.notify('Som do antilag selecionado: default', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'superv8',
            label = 'superv8',
            icon = 'volume-high',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, 'superv8', nil) then
                    ctx.notify('Som do antilag selecionado: superv8', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'vacca',
            label = 'vacca',
            icon = 'volume-high',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, 'vacca', nil) then
                    ctx.notify('Som do antilag selecionado: vacca', 'sucess')
                        ctx.refresh()
                    end
                end
        },
        {
            id = 'eurosz',
            label = 'eurosz',
            icon = 'volume-high',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, 'eurosz', nil) then
                    ctx.notify('Som do antilag selecionado: eurosz', 'sucess')
                        ctx.refresh()
                    end
                end
        },
        {
            id = 'toysupmk4',
            label = 'toysupmk4',
            icon = 'volume-high',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, 'toysupmk4', nil) then
                    ctx.notify('Som do antilag selecionado: toysupmk4', 'sucess')
                        ctx.refresh()
                    end
                end
        },
        {
            id = 'murcisp',
            label = 'murcisp',
            icon = 'volume-high',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, 'murcisp', nil) then
                    ctx.notify('Som do antilag selecionado: murcisp', 'sucess')
                        ctx.refresh()
                    end
                end
        },
        {
            id = 'subej22',
            label = 'subej22',
            icon = 'volume-high',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, 'subej22', nil) then
                    ctx.notify('Som do antilag selecionado: subej22', 'sucess')
                        ctx.refresh()
                    end
                end
        },
        {
            id = 'default2',
            label = 'default2',
            icon = 'volume-high',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, 'default2', nil) then
                    ctx.notify('Som do antilag selecionado: default2', 'sucess')
                        ctx.refresh()
                    end
                end
        },
        {
            id = 'default3',
            label = 'default3',
            icon = 'volume-high',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, 'default3', nil) then
                    ctx.notify('Som do antilag selecionado: default3', 'sucess')
                        ctx.refresh()
                    end
                end
        },
        {
            id = 'antilagold',
            label = 'antilagold',
            icon = 'volume-high',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, 'antilagold', nil) then
                    ctx.notify('Som do antilag selecionado: antilagold', 'sucess')
                        ctx.refresh()
                    end
                end
        }
    }
})

registerRadial({
    id = 'antilag_color_menu',
    label = 'Cores',
    items = {
        {
            id = 'blue',
            label = 'Blue',
            icon = 'droplet',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, nil, 'blue') then
                    ctx.notify('Cor do antilag: blue', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'Pink',
            label = 'Pink',
            icon = 'droplet',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, nil, 'pink') then
                    ctx.notify('Cor do antilag: Pink', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'Purple',
            label = 'Purple',
            icon = 'droplet',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, nil, 'purple') then
                    ctx.notify('Cor do antilag: Purple', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'Red',
            label = 'Red',
            icon = 'droplet',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, nil, 'red') then
                    ctx.notify('Cor do antilag: Red', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'Natural',
            label = 'Natural',
            icon = 'droplet',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, nil, 'natural') then
                    ctx.notify('Cor do antilag: Natural', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'Aqua',
            label = 'Aqua',
            icon = 'droplet',
            onSelect = function(ctx)
                if setSmpConfigAntilagInstalled(true, ctx, nil, 'aqua') then
                    ctx.notify('Cor do antilag: Aqua', 'success')
                    ctx.refresh()
                end
            end
        }
    }
})

registerRadial({
    id = 'nitro_menu',
    label = 'Nitro',
    items = {
        {
            id = 'toggle',
            label = 'Ativar/Desligar',
            icon = 'power-off',
            kicker = 'Sistema',
            onSelect = function(ctx)
                local ok, enabled = toggleSmpConfigNitroInstalled(ctx)

                if ok then
                    ctx.notify(
                        enabled and 'Nitro ativado' or 'Nitro desligado',
                        enabled and 'success' or 'warning'
                    )
                    ctx.refresh()
                end
            end
        },
        {
            id = 'colors',
            label = 'Cores',
            icon = 'palette',
            menu = 'nitro_color_menu',
            kicker = 'Nitro'
        }
    }
})

registerRadial({
    id = 'nitro_color_menu',
    label = 'Cores',
    items = {
        {
            id = 'blue',
            label = 'Blue',
            icon = 'droplet',
            onSelect = function(ctx)
                if setSmpConfigNitroInstalled(true, ctx, nil, 'blue') then
                    ctx.notify('Cor do nitro: blue', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'pink',
            label = 'Pink',
            icon = 'droplet',
            onSelect = function(ctx)
                if setSmpConfigNitroInstalled(true, ctx, nil, 'pink') then
                    ctx.notify('Cor do nitro: pink', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'purple',
            label = 'Purple',
            icon = 'droplet',
            onSelect = function(ctx)
                if setSmpConfigNitroInstalled(true, ctx, nil, 'purple') then
                    ctx.notify('Cor do nitro: purple', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'red',
            label = 'Red',
            icon = 'droplet',
            onSelect = function(ctx)
                if setSmpConfigNitroInstalled(true, ctx, nil, 'red') then
                    ctx.notify('Cor do nitro: red', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'natural',
            label = 'Natural',
            icon = 'droplet',
            onSelect = function(ctx)
                if setSmpConfigNitroInstalled(true, ctx, nil, 'natural') then
                    ctx.notify('Cor do nitro: natural', 'success')
                    ctx.refresh()
                end
            end
        },
        {
            id = 'aqua',
            label = 'Aqua',
            icon = 'droplet',
            onSelect = function(ctx)
                if setSmpConfigNitroInstalled(true, ctx, nil, 'aqua') then
                    ctx.notify('Cor do nitro: aqua', 'success')
                    ctx.refresh()
                end
            end
        }
    }
})

-- ==============================
-- MENU DE SETTINGS (CONFIGURAÃƒâ€¡Ãƒâ€¢ES)
-- ==============================

registerRadial({
    id = 'settings_menu',
    label = 'settings',
    items = {
        {
            id = 'hud',
            label = 'Hud',
            icon = 'gear',
            kicker = 'HUD',
            onSelect = function(ctx)
                ExecuteCommand('hud')
            end
        },
        {
            id = 'Editor',                  
            label = 'Rockstar editor',               
            icon = 'video',      
            menu = 'rockstar_menu'
        },
        {
            id = 'time',
            label = 'Hora',
            icon = 'clock',
            menu = 'time_menu',
            kicker = 'Time'
        },
        {
            id = 'clima',
            label = 'Clima',
            icon = 'cloud-sun',
            menu = 'clima_menu',
            kicker = 'Clima'
        }
    }
})

-- Menu do Rockstar Editor
registerRadial({
    id = 'rockstar_menu',
    label = 'Rockstar Editor',
    items = {
        {
            id = 'Editor',
            label = 'Editor',
            icon = 'camera',
            kicker = 'Editor',
            onSelect = function(ctx)
                ActivateRockstarEditor()
            end
        },
        {
            id = 'Clip',
            label = 'Clip Start',
            icon = 'scissors',
            kicker = 'Editor',
            onSelect = function(ctx)
                StartRecording(1)
            end
        },
        {
            id = 'ClipStop',
            label = 'Clip Stop',
            icon = 'stop',
            kicker = 'Editor',
            onSelect = function(ctx)
                StopRecordingAndSaveClip()
            end
        },
        {
            id = 'ClipDiscard',
            label = 'Clip Discard',
            icon = 'trash-can',
            kicker = 'Editor',
            onSelect = function(ctx)
                StopRecordingAndDiscardClip()
            end
        },
    }
})

-- Submenu de tempo (dia, noite, amanhecer, entardecer)
registerRadial({
    id = 'time_menu',
    label = 'Hora',
    items = {
       {
            id = 'dia',                  
            label = 'Dia',               
            icon = 'sun',      
            onSelect = function()
                ExecuteCommand('dia')
            end
        },
        {
            id = 'noite',                  
            label = 'Noite',               
            icon = 'moon',      
            onSelect = function()
                ExecuteCommand('noite')
            end
        },
        {
            id = 'sunrise',                  
            label = 'Manha',               
            icon = 'cloud-sun',      
            onSelect = function()
                ExecuteCommand('manha')
            end
        },
        {
            id = 'sunset',                  
            label = 'Tarde',               
            icon = 'cloud-sun',      
            onSelect = function()
                ExecuteCommand('tarde')
            end
        }
    }
})

-- Submenu de clima (ensolarado, chuvoso, nublado, etc.)
registerRadial({
    id = 'clima_menu',
    label = 'Clima',
    items = {
        {
            id = 'ensolarado',                  
            label = 'ensolarado',               
            icon = 'sun',      
            onSelect = function()
                ExecuteCommand('clima 1')
            end
        },
        {
            id = 'chuvoso',                  
            label = 'chuvoso',               
            icon = 'cloud-rain',      
            onSelect = function()
                ExecuteCommand('clima 10')
            end
        },
        {
            id = 'nublado',                  
            label = 'nublado',               
            icon = 'cloud',      
            onSelect = function()
                ExecuteCommand('clima 6')
            end
        },
        {
            id = 'tempestade',                  
            label = 'tempestade',               
            icon = 'cloud-bolt',      
            onSelect = function()
                ExecuteCommand('clima 9')
            end
        }
    }
})


local function openWeaponsMenuFromRadial(ctx)
    if GetResourceState('weaponsui') ~= 'started' then
        ctx.notify('O sistema de armas nao esta iniciado.', 'error')
        return false
    end

    ctx.close()

    CreateThread(function()
        Wait(100)
        ExecuteCommand('armasmenu')
    end)

    return true
end

local function registerWeaponsRadialShortcut()
    addRadialItem({
        {
            id = 'weapons_root',
            label = 'Armas',
            icon = 'gun',
            kicker = 'Arsenal',
            onSelect = function(ctx)
                openWeaponsMenuFromRadial(ctx)
            end
        }
    })
end

registerWeaponsRadialShortcut()
ApexRadialMenuConfig = buildRootPage()
