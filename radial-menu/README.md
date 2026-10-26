# Radial Menu - Arquivo Unico

Agora voce configura tudo em um arquivo so:

- `radial-menu/config.lua`

Voce nao precisa mais editar `actions.lua` para montar abas, submenu ou funcoes.

## Estrutura basica

### Aba na raiz

```lua
addRadialItem({
    {
        id = 'garage',
        label = 'Garagem',
        icon = 'warehouse',
        menu = 'garage_menu',
        kicker = 'Apex'
    }
})
```

### Submenu

```lua
registerRadial({
    id = 'garage_menu',
    label = 'Garagem',
    items = {
        {
            id = 'garage_open',
            label = 'Abrir',
            icon = 'car',
            kicker = 'Garagem',
            onSelect = function()
                ExecuteCommand('car')
            end
        }
    }
})
```

## Regras simples

- `addRadialItem(...)` adiciona abas na raiz do radial
- `registerRadial(...)` cria um submenu
- `menu = 'nome_do_menu'` abre outro submenu
- `onSelect = function(ctx) ... end` executa a funcao ao clicar
- `enabled = false` deixa o item bloqueado
- `icon = 'car'` usa icone curto no estilo do ox_lib

## Exemplo completo

```lua
addRadialItem({
    {
        id = 'vehicle',
        label = 'Vehicle',
        icon = 'car',
        menu = 'vehicle_menu'
    },
    {
        id = 'settings',
        label = 'Settings',
        icon = 'gear',
        menu = 'settings_menu'
    }
})

registerRadial({
    id = 'vehicle_menu',
    label = 'Vehicle',
    items = {
        {
            id = 'fix',
            label = 'Fix',
            icon = 'wrench',
            onSelect = function(ctx)
                ExecuteCommand('fix')
                ctx.notify('Veiculo reparado.', 'success')
            end
        },
        {
            id = 'performance',
            label = 'Performance',
            icon = 'gauge-high',
            menu = 'performance_menu'
        }
    }
})

registerRadial({
    id = 'performance_menu',
    label = 'Performance',
    items = {
        {
            id = 'maxmods',
            label = 'MaxMods',
            icon = 'gauge',
            onSelect = function(ctx)
                ExecuteCommand('maxmods')
                ctx.notify('MaxMods aplicado.', 'success')
            end
        },
        {
            id = 'ls',
            label = 'LS Customs',
            icon = 'spray-can',
            onSelect = function()
                ExecuteCommand('ls')
            end
        }
    }
})
```

## O que o `ctx` pode usar

Dentro do `onSelect`, voce pode usar:

- `ctx.notify('Texto', 'success')`
- `ctx.refresh()`
- `ctx.close()`
- `ctx.setPage('nome_do_menu', 'item_id')`

## Exemplo de submenu dentro de submenu

```lua
registerRadial({
    id = 'tuning_menu',
    label = 'Tunagem',
    items = {
        {
            id = 'antilag',
            label = 'Antilag',
            icon = 'fire',
            menu = 'antilag_menu'
        }
    }
})

registerRadial({
    id = 'antilag_menu',
    label = 'Antilag',
    items = {
        {
            id = 'antilag_install',
            label = 'Aplicar',
            icon = 'plus',
            onSelect = function(ctx)
                ctx.notify('Antilag aplicado.', 'success')
            end
        }
    }
})
```