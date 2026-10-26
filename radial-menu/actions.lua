ApexRadialMenuActions = {
    handlers = {},
    pageBuilders = {}
}

local function getSmpConfigAntilagContext()
    local context = {
        resourceStarted = GetResourceState('smp-config') == 'started',
        inVehicle = false,
        vehicle = 0,
        hasAntilag = false,
        systemEnabled = false
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

    return context
end

local function setSmpConfigAntilagInstalled(context, shouldEnable, radialContext)
    if not context.resourceStarted then
        radialContext.notify('O recurso smp-config nao esta iniciado.', 'error')
        return false
    end

    if not context.inVehicle or context.vehicle == 0 then
        radialContext.notify('Entre em um veiculo para configurar o Antilag.', 'warning')
        return false
    end

    TriggerServerEvent('smp-config:server:SetAntilag', VehToNet(context.vehicle), shouldEnable, nil, nil)
    radialContext.notify(
        shouldEnable and 'Antilag aplicado ao veiculo.' or 'Antilag removido do veiculo.',
        shouldEnable and 'success' or 'warning'
    )

    return true
end

local function toggleSmpConfigAntilagSystem(context, radialContext)
    if not context.resourceStarted then
        radialContext.notify('O recurso smp-config nao esta iniciado.', 'error')
        return false
    end

    local ok = pcall(function()
        exports['smp-config']:ToggleAntilag()
    end)

    if not ok then
        radialContext.notify('Nao foi possivel alternar o Antilag do smp-config.', 'error')
        return false
    end

    local enabled = not context.systemEnabled
    local okStatus, status = pcall(function()
        return exports['smp-config']:StatusAntilag()
    end)

    if okStatus then
        enabled = status == true
    end

    radialContext.notify(
        enabled and 'Antilag local ativado.' or 'Antilag local pausado.',
        enabled and 'success' or 'warning'
    )

    return true
end

ApexRadialMenuActions.pageBuilders.buildSmpAntilagItems = function()
    local context = getSmpConfigAntilagContext()

    return {
        {
            id = 'antilag_install',
            label = context.hasAntilag and 'Reaplicar' or 'Aplicar',
            kicker = 'Veiculo',
            icon = 'fa-plus',
            action = 'antilag_install',
            enabled = context.resourceStarted and context.inVehicle
        },
        {
            id = 'antilag_toggle',
            label = context.systemEnabled and 'Pausar' or 'Ativar',
            kicker = 'Sistema',
            icon = 'fa-power-off',
            action = 'antilag_toggle',
            enabled = context.resourceStarted
        },
        {
            id = 'antilag_remove',
            label = 'Remover',
            kicker = 'Veiculo',
            icon = 'fa-minus',
            action = 'antilag_remove',
            enabled = context.resourceStarted and context.inVehicle and context.hasAntilag
        }
    }
end

ApexRadialMenuActions.handlers.nitro_placeholder = function(radialContext)
    radialContext.notify('Opcao de Nitro em configuracao.', 'inform')
end

ApexRadialMenuActions.handlers.antilag_install = function(radialContext)
    local context = getSmpConfigAntilagContext()

    if setSmpConfigAntilagInstalled(context, true, radialContext) then
        radialContext.refresh()
    end
end

ApexRadialMenuActions.handlers.antilag_toggle = function(radialContext)
    local context = getSmpConfigAntilagContext()

    if toggleSmpConfigAntilagSystem(context, radialContext) then
        radialContext.refresh()
    end
end

ApexRadialMenuActions.handlers.antilag_remove = function(radialContext)
    local context = getSmpConfigAntilagContext()

    if setSmpConfigAntilagInstalled(context, false, radialContext) then
        radialContext.refresh()
    end
end

-- Exemplo de nova acao:
-- ApexRadialMenuActions.handlers.minha_acao = function(ctx, item)
--     ctx.notify('Minha acao rodou.', 'success')
-- end
