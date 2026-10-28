/* ============================================================
   Apex Input Glyphs  -  icones globais de teclado / PlayStation / Xbox
   Pacote de icones: Kenney Input Prompts (CC0) em html/input-icons/{kb,ps,xbox}

   Como usar em QUALQUER tela (index.html, esc-menu.html, futuras):
     <script src="input-glyphs.js"></script>  +  <link rel="stylesheet" href="input-glyphs.css">

     <span data-input="menu"></span>                       acao pronta (veja ACTIONS)
     <span data-key="z" data-pad="dpad-left"></span>       tecla + botao do controle
     <span data-key="1" data-pad="dpad-left">1</span>      o texto interno e o fallback

   O modo (teclado | gamepad) e o estilo do controle (playstation | xbox) chegam do
   client.lua via { action: 'setInputMode', mode, padStyle }. Elementos criados depois
   (renderizados por JS) sao atualizados automaticamente.
   Documentacao completa: INPUT_GLYPHS.md na raiz do resource.
   ============================================================ */
(function () {
    'use strict'

    const ICON_ROOT = 'input-icons'

    // Botao generico do controle -> arquivo em cada pacote (sem .svg)
    const PAD = {
        'face-bottom': { playstation: 'playstation_button_color_cross', xbox: 'xbox_button_color_a' },
        'face-right': { playstation: 'playstation_button_color_circle', xbox: 'xbox_button_color_b' },
        'face-left': { playstation: 'playstation_button_color_square', xbox: 'xbox_button_color_x' },
        'face-top': { playstation: 'playstation_button_color_triangle', xbox: 'xbox_button_color_y' },
        options: { playstation: 'playstation4_button_options', xbox: 'xbox_button_menu' },
        share: { playstation: 'playstation4_button_share', xbox: 'xbox_button_view' },
        l1: { playstation: 'playstation_trigger_l1', xbox: 'xbox_lb' },
        r1: { playstation: 'playstation_trigger_r1', xbox: 'xbox_rb' },
        l2: { playstation: 'playstation_trigger_l2', xbox: 'xbox_lt' },
        r2: { playstation: 'playstation_trigger_r2', xbox: 'xbox_rt' },
        l3: { playstation: 'playstation_button_l3', xbox: 'xbox_stick_l_press' },
        r3: { playstation: 'playstation_button_r3', xbox: 'xbox_stick_r_press' },
        'stick-l': { playstation: 'playstation_stick_l', xbox: 'xbox_stick_l' },
        'stick-r': { playstation: 'playstation_stick_r', xbox: 'xbox_stick_r' },
        dpad: { playstation: 'playstation_dpad', xbox: 'xbox_dpad' },
        'dpad-up': { playstation: 'playstation_dpad_up', xbox: 'xbox_dpad_up' },
        'dpad-down': { playstation: 'playstation_dpad_down', xbox: 'xbox_dpad_down' },
        'dpad-left': { playstation: 'playstation_dpad_left', xbox: 'xbox_dpad_left' },
        'dpad-right': { playstation: 'playstation_dpad_right', xbox: 'xbox_dpad_right' },
        'dpad-horizontal': { playstation: 'playstation_dpad_horizontal', xbox: 'xbox_dpad_horizontal' },
        'dpad-vertical': { playstation: 'playstation_dpad_vertical', xbox: 'xbox_dpad_vertical' }
    }

    // Acoes prontas: {key: tecla do teclado, pad: botao generico do controle}
    const ACTIONS = {
        menu: { key: 'escape', pad: 'options' },
        shortcuts: { key: 'z', pad: 'dpad-left' },
        confirm: { key: 'enter', pad: 'face-bottom' },
        back: { key: 'escape', pad: 'face-right' },
        close: { key: 'escape', pad: 'face-right' },
        'nav-up': { key: 'arrow_up', pad: 'dpad-up' },
        'nav-down': { key: 'arrow_down', pad: 'dpad-down' },
        'nav-left': { key: 'arrow_left', pad: 'dpad-left' },
        'nav-right': { key: 'arrow_right', pad: 'dpad-right' },
        'nav-horizontal': { key: 'arrows_horizontal', pad: 'dpad-horizontal' },
        'nav-vertical': { key: 'arrows_vertical', pad: 'dpad-vertical' },
        'tab-prev': { key: 'q', pad: 'l1' },
        'tab-next': { key: 'e', pad: 'r1' }
    }

    const KEY_ALIASES = {
        esc: 'escape', return: 'enter', del: 'delete', ' ': 'space', spacebar: 'space',
        left: 'arrow_left', right: 'arrow_right', up: 'arrow_up', down: 'arrow_down',
        '←': 'arrow_left', '→': 'arrow_right', '↑': 'arrow_up', '↓': 'arrow_down',
        control: 'ctrl', pgup: 'page_up', pgdn: 'page_down'
    }

    const state = { mode: 'keyboard', padStyle: 'playstation' }

    function normKey(key) {
        const raw = String(key == null ? '' : key).trim().toLowerCase()
        if (KEY_ALIASES[raw]) return KEY_ALIASES[raw]
        return raw.replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '')
    }

    function describe(el) {
        const preset = ACTIONS[el.dataset.input] || {}
        return { key: el.dataset.key || preset.key || '', pad: el.dataset.pad || preset.pad || '' }
    }

    // Caminho do icone para o estado atual (ou null se nao existir mapeamento)
    function iconSrc(key, pad) {
        if (state.mode === 'gamepad') {
            const entry = PAD[pad]
            const family = state.padStyle === 'xbox' ? 'xbox' : 'playstation'
            if (!entry) return null
            return `${ICON_ROOT}/${family === 'xbox' ? 'xbox' : 'ps'}/${entry[family]}.svg`
        }
        const name = normKey(key)
        return name ? `${ICON_ROOT}/kb/keyboard_${name}.svg` : null
    }

    function stateKey() {
        return `${state.mode}:${state.padStyle}`
    }

    function renderOne(el) {
        if (el.dataset.glyphText === undefined) el.dataset.glyphText = el.textContent.trim()
        el.classList.add('input-glyph')
        const { key, pad } = describe(el)
        const src = iconSrc(key, pad)
        el.dataset.glyphState = stateKey()

        if (!src) {
            el.classList.remove('has-icon')
            el.textContent = state.mode === 'gamepad' ? '' : (el.dataset.glyphText || key.toUpperCase())
            return
        }

        const img = document.createElement('img')
        img.className = 'input-icon'
        img.alt = el.dataset.glyphText || key || pad
        img.draggable = false
        img.addEventListener('error', () => {
            el.classList.remove('has-icon')
            el.textContent = el.dataset.glyphText || key.toUpperCase()
        }, { once: true })
        img.src = src
        el.classList.add('has-icon')
        el.replaceChildren(img)
    }

    function render(root) {
        const scope = root || document
        const current = stateKey()
        scope.querySelectorAll('[data-input], [data-key], [data-pad]').forEach((el) => {
            if (el.dataset.glyphState !== current) renderOne(el)
        })
    }

    function syncFrames() {
        document.querySelectorAll('iframe').forEach((frame) => {
            try {
                frame.contentWindow && frame.contentWindow.postMessage({ action: 'setInputMode', mode: state.mode, padStyle: state.padStyle }, '*')
            } catch (e) { /* ignora */ }
        })
    }

    function setMode(mode, padStyle) {
        const nextMode = mode === 'gamepad' ? 'gamepad' : 'keyboard'
        const nextStyle = padStyle === 'xbox' ? 'xbox' : (padStyle === 'playstation' ? 'playstation' : state.padStyle)
        if (nextMode === state.mode && nextStyle === state.padStyle) return
        state.mode = nextMode
        state.padStyle = nextStyle
        document.body && document.body.classList.toggle('input-pad', nextMode === 'gamepad')
        render()
        syncFrames()
        window.dispatchEvent(new CustomEvent('apex-input-change', { detail: { mode: state.mode, padStyle: state.padStyle } }))
    }

    window.addEventListener('message', (event) => {
        const data = event.data
        if (!data) return
        if (data.action === 'setInputMode') {
            setMode(data.mode, data.padStyle)
        } else if (data.action === 'apexInputRequest' && event.source) {
            try {
                event.source.postMessage({ action: 'setInputMode', mode: state.mode, padStyle: state.padStyle }, '*')
            } catch (e) { /* ignora */ }
        }
    })

    function init() {
        document.body.classList.toggle('input-pad', state.mode === 'gamepad')
        render()

        // Conteudo criado depois (listas, modais, etc.) tambem recebe os icones.
        let queued = false
        new MutationObserver(() => {
            if (queued) return
            queued = true
            requestAnimationFrame(() => { queued = false; render() })
        }).observe(document.body, { childList: true, subtree: true })

        // Dentro de um iframe: pede ao documento pai o modo atual.
        if (window.parent && window.parent !== window) {
            try { window.parent.postMessage({ action: 'apexInputRequest' }, '*') } catch (e) { /* ignora */ }
        }
        syncFrames()
    }

    window.ApexInput = {
        get mode() { return state.mode },
        get padStyle() { return state.padStyle },
        setMode,
        render,
        actions: ACTIONS,
        padButtons: Object.keys(PAD),
        // HTML de um icone para usar em templates JS: ApexInput.html('confirm')
        html(action, extra) {
            const preset = typeof action === 'string' ? (ACTIONS[action] || { key: action, pad: action }) : (action || {})
            const attrs = `data-key="${(extra && extra.key) || preset.key || ''}" data-pad="${(extra && extra.pad) || preset.pad || ''}"`
            return `<span class="input-glyph" ${attrs}></span>`
        }
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init)
    else init()
})()
