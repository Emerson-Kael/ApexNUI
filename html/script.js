const speedometer = document.getElementById('speedometer')
const speedDigits = Array.from(document.querySelectorAll('[data-speed-digit]'))
const rpmSegments = Array.from(document.querySelectorAll('[data-rpm-segment]'))
const speedometerGearValue = document.getElementById('speedometer-gear-value')
const speedometerUnit = document.getElementById('speedometer-unit')
const speedometerAbs = document.getElementById('speedometer-abs')
const speedometerHbk = document.getElementById('speedometer-hbk')

// Novos elementos SVG
const svgSpeedometer = document.getElementById('svg-speedometer')
const svgSpeedValue = document.getElementById('svg-speed-value')
const svgSpeedUnit = document.querySelector('.svg-speed-unit')
const svgRpmDotsTrack = document.getElementById('svg-rpm-dots')

// Paleta usada nos pontinhos de RPM, do neutro (giro baixo) ao vermelho (redline)
const SVG_RPM_DOT_COUNT = 12
const SVG_RPM_PALETTE = ['#D9D9D9', '#FEEAE2', '#FFEBE3', '#FFDDD0', '#FFD4C4', '#FF9E8A', '#FF7E70', '#FF7469', '#FF5547', '#FA4739', '#FA3829', '#FF1200']
const svgRpmDots = (() => {
    if (!svgRpmDotsTrack) return []
    const frag = document.createDocumentFragment()
    const dots = []
    for (let i = 0; i < SVG_RPM_DOT_COUNT; i++) {
        const dot = document.createElement('span')
        dot.className = 'svg-rpm-dot'
        frag.appendChild(dot)
        dots.push(dot)
    }
    svgRpmDotsTrack.appendChild(frag)
    return dots
})()

// --- Conta-giros SVG progressivo -------------------------------------------------
// O arco (rosa 0-6 + vermelho 6-10) comeca apagado e vai acendendo conforme o RPM.
// Os numeros tambem ganham forca (opacidade + leve escala) ao se aproximar do giro atual.
const GAUGE_CENTER_X = 200
const GAUGE_CENTER_Y = 195
const GAUGE_CLIP_RADIUS = 220 // maior que o raio externo (176) para cobrir a faixa inteira
const GAUGE_START_ANGLE = -145 // graus a partir do topo, sentido horario (numero 0)
const GAUGE_SWEEP = 290 // do 0 ao 10 (29 graus por numero)
const GAUGE_NUM_MIN_OPACITY = 0.38
const GAUGE_NUM_MIN_SCALE = 1
const GAUGE_NUM_MAX_SCALE = 1.2

const gaugeClipPath = document.getElementById('gauge-rpm-clip-path')
const gaugeNumbers = Array.from(document.querySelectorAll('.gauge-numbers .gauge-num'))

let gaugeTarget = 0 // RPM alvo (0..1) vindo do jogo
let gaugeCurrent = 0 // RPM exibido (suavizado)
let gaugeRaf = null

function gaugePoint(angleDeg, radius) {
    const rad = (angleDeg * Math.PI) / 180
    return [GAUGE_CENTER_X + radius * Math.sin(rad), GAUGE_CENTER_Y - radius * Math.cos(rad)]
}

function paintGauge(rpm) {
    const value = rpm * 10 // 0..10, mesma escala dos numeros

    if (gaugeClipPath) {
        const sweep = rpm * GAUGE_SWEEP
        if (sweep < 0.05) {
            gaugeClipPath.setAttribute('d', '')
        } else {
            const [sx, sy] = gaugePoint(GAUGE_START_ANGLE, GAUGE_CLIP_RADIUS)
            const [ex, ey] = gaugePoint(GAUGE_START_ANGLE + sweep, GAUGE_CLIP_RADIUS)
            const largeArc = sweep > 180 ? 1 : 0
            gaugeClipPath.setAttribute(
                'd',
                `M ${GAUGE_CENTER_X} ${GAUGE_CENTER_Y} L ${sx.toFixed(2)} ${sy.toFixed(2)} ` +
                `A ${GAUGE_CLIP_RADIUS} ${GAUGE_CLIP_RADIUS} 0 ${largeArc} 1 ${ex.toFixed(2)} ${ey.toFixed(2)} Z`
            )
        }
    }

    gaugeNumbers.forEach((node, index) => {
        // O numero comeca a acender 1 unidade antes de ser alcancado e fica pleno ao chegar nele.
        const t = index === 0
            ? Math.max(0, Math.min(1, value * 2))
            : Math.max(0, Math.min(1, value - (index - 1)))
        node.style.opacity = (GAUGE_NUM_MIN_OPACITY + (1 - GAUGE_NUM_MIN_OPACITY) * t).toFixed(3)
        node.classList.toggle('is-lit', t >= 0.99)
        node.style.transform = `scale(${(GAUGE_NUM_MIN_SCALE + (GAUGE_NUM_MAX_SCALE - GAUGE_NUM_MIN_SCALE) * t).toFixed(3)})`
    })
}

function gaugeLoop() {
    // Suavizacao: sobe/desce em direcao ao alvo sem "pular" entre as mensagens do client.
    const diff = gaugeTarget - gaugeCurrent
    if (Math.abs(diff) < 0.001) {
        gaugeCurrent = gaugeTarget
        paintGauge(gaugeCurrent)
        gaugeRaf = null
        return
    }
    gaugeCurrent += diff * 0.35
    paintGauge(gaugeCurrent)
    gaugeRaf = requestAnimationFrame(gaugeLoop)
}

function renderSvgRpm(rpm) {
    const clamped = Math.max(0, Math.min(1, Number(rpm) || 0))

    // Pontinhos centrais
    const lit = Math.round(clamped * SVG_RPM_DOT_COUNT)
    svgRpmDots.forEach((dot, i) => {
        dot.style.background = i < lit ? SVG_RPM_PALETTE[i] : 'rgba(255,255,255,.24)'
    })

    // Arco + numeros
    gaugeTarget = clamped
    if (!gaugeRaf) {
        gaugeRaf = requestAnimationFrame(gaugeLoop)
    }
}

// Estado inicial: tudo apagado
paintGauge(0)

const escMenu = document.getElementById('esc-menu')
const apexNewEsc = document.getElementById('apex-new-esc')
const apexNewEscFrame = document.getElementById('apex-new-esc-frame')
let lastApexGarageCatalogPayload = null
let apexGarageCatalogDelivery = 0
let apexTrackCreationAllowed = false
function forwardApexGarageCatalog(payload, delivery) {
    if (delivery !== apexGarageCatalogDelivery || !apexNewEscFrame || !apexNewEscFrame.contentWindow) return
    apexNewEscFrame.contentWindow.postMessage({ type: 'apex-garage-data', payload }, '*')
}
function forwardApexTrackCreationPermission() {
    if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
        apexNewEscFrame.contentWindow.postMessage({ type: 'apex-track-creator-permission', canCreate: apexTrackCreationAllowed }, '*')
    }
}
if (apexNewEscFrame) {
    apexNewEscFrame.addEventListener('load', () => {
        if (lastApexGarageCatalogPayload) {
            const delivery = ++apexGarageCatalogDelivery
            forwardApexGarageCatalog(lastApexGarageCatalogPayload, delivery)
        }
        forwardApexTrackCreationPermission()
    })
}
const escMenuNav = document.getElementById('esc-menu-nav')
const escProfilePanel = document.getElementById('esc-profile-panel')
const escProfileRefreshButton = document.getElementById('esc-profile-refresh-button')
const escProfileEditButton = document.getElementById('esc-profile-edit-button')
const escProfileAvatarImage = document.getElementById('esc-profile-avatar-image')
const escProfileAvatarFallback = document.getElementById('esc-profile-avatar-fallback')
const escProfileDisplayName = document.getElementById('esc-profile-display-name')
const escProfileSubline = document.getElementById('esc-profile-subline')
const escProfileRankValue = document.getElementById('esc-profile-rank-value')
const escProfileRankSubtext = document.getElementById('esc-profile-rank-subtext')
const escProfileRankMax = document.getElementById('esc-profile-rank-max')
const escProfileLinkChip = document.getElementById('esc-profile-link-chip')
const escProfileStatRecords = document.getElementById('esc-profile-stat-records')
const escProfileStatWinrate = document.getElementById('esc-profile-stat-winrate')
const escProfileStatWins = document.getElementById('esc-profile-stat-wins')
const escProfileStatRaces = document.getElementById('esc-profile-stat-races')
const escProfileStatRacesMeta = document.getElementById('esc-profile-stat-races-meta')
const escProfileFavoriteCarName = document.getElementById('esc-profile-favorite-car-name')
const escProfileFavoriteCarMeta = document.getElementById('esc-profile-favorite-car-meta')
const escProfileBestTime = document.getElementById('esc-profile-best-time')
const escProfileBestTimeMeta = document.getElementById('esc-profile-best-time-meta')
const escProfileBestTrack = document.getElementById('esc-profile-best-track')
const escProfileBestTrackMeta = document.getElementById('esc-profile-best-track-meta')
const escProfileLastRace = document.getElementById('esc-profile-last-race')
const escProfileLastRaceMeta = document.getElementById('esc-profile-last-race-meta')
const escProfileStatCreated = document.getElementById('esc-profile-stat-created')
const escProfileStatCreatedMeta = document.getElementById('esc-profile-stat-created-meta')
const escProfileLevelMax = document.getElementById('esc-profile-level-max')
const escProfileLevelMaxMeta = document.getElementById('esc-profile-level-max-meta')
const escProfileLastVehicle = document.getElementById('esc-profile-last-vehicle')
const escProfileLastVehicleMeta = document.getElementById('esc-profile-last-vehicle-meta')
const escProfileBestLap = document.getElementById('esc-profile-best-lap')
const escProfileBestLapMeta = document.getElementById('esc-profile-best-lap-meta')
const escProfileEmptyState = document.getElementById('esc-profile-empty-state')
const escProfileEmptyKicker = document.getElementById('esc-profile-empty-kicker')
const escProfileEmptyTitle = document.getElementById('esc-profile-empty-title')
const escProfileEmptyText = document.getElementById('esc-profile-empty-text')

const radialMenu = document.getElementById('radial-menu')
const radialMenuItemsContainer = document.getElementById('radial-menu-items')
const radialMenuCore = document.getElementById('radial-menu-core')
const radialMenuKicker = document.getElementById('radial-menu-kicker')
const radialMenuTitle = document.getElementById('radial-menu-title')
const radialMenuSubtitle = document.getElementById('radial-menu-subtitle')
const vehicleQuickMenu = document.getElementById('vehicle-quick-menu')
const vehicleQuickMenuName = document.getElementById('vehicle-quick-menu-name')
const vehicleQuickActionButtons = Array.from(document.querySelectorAll('[data-vehicle-action]'))
const vehicleQuickCloseButton = document.getElementById('vehicle-quick-menu-close')

const radialIconMap = {
    map: 'fa-map-location-dot',
    races: 'fa-flag-checkered',
    profile: 'fa-id-card',
    leaderboard: 'fa-trophy',
    garage: 'fa-warehouse',
    bennys: 'fa-screwdriver-wrench',
    settings: 'fa-sliders',
    tuning: 'fa-screwdriver-wrench',
    antilag: 'fa-fire',
    nitro: 'fa-bolt',
    antilag_install: 'fa-plus',
    antilag_toggle: 'fa-power-off',
    antilag_remove: 'fa-minus'
}

let escMenuItems = []
let escActiveIndex = 0
let escMenuOpen = false
let escProfileOpen = false
let radialMenuItems = []
let radialActiveIndex = 0
let radialMenuOpen = false
let radialCanGoBack = false
let vehicleQuickMenuOpen = false
let apexGaragePurchaseOpen = false
let apexGaragePurchaseLocationId = null
let apexGaragePurchaseKind = 'purchase'
let apexGaragePurchaseCapacity = null
let apexGarageSiteOpen = false
let apexGarageSiteData = null
let apexGarageSiteSelectedId = null

// Estado inicial: o menu ESC comeca SEMPRE fechado.
if (apexNewEsc) {
    apexNewEsc.classList.remove('is-open')
    apexNewEsc.setAttribute('aria-hidden', 'true')
}
if (escMenu) {
    escMenu.classList.remove('is-open')
    escMenu.setAttribute('aria-hidden', 'true')
}

function postNui(eventName, payload = {}) {
    return fetch(`https://${GetParentResourceName()}/${eventName}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8'
        },
        body: JSON.stringify(payload)
    }).catch(() => {})
}

const apexGaragePurchaseModal = document.getElementById('apex-garage-purchase')
const apexGaragePurchaseCancel = document.getElementById('apex-garage-purchase-cancel')
const apexGaragePurchaseConfirm = document.getElementById('apex-garage-purchase-confirm')
const apexGarageSite = document.getElementById('apex-garage-site')
const apexGarageSiteAction = document.getElementById('apex-site-action')
const apexGarageSitePrimaryTab = document.getElementById('apex-site-tab-primary')
const apexGarageSiteListingsTab = document.getElementById('apex-site-tab-listings')
const apexGarageSiteWorkspace = document.querySelector('.apex-garage-site-workspace')
const apexGarageSiteListings = document.getElementById('apex-garage-listings')
const apexGarageOwnedVehicles = document.getElementById('apex-garage-owned-vehicles')
let apexGarageSitePage = 'primary'

function setApexGarageSitePage(page) {
    apexGarageSitePage = page
    const showListings = page === 'listings'
    const showOwnedVehicles = page === 'primary' && apexGarageSiteData?.owned === true
    const showDetails = !showListings && !showOwnedVehicles
    apexGarageSiteWorkspace.hidden = !showDetails
    apexGarageSiteListings.hidden = !showListings
    apexGarageOwnedVehicles.hidden = !showOwnedVehicles
    apexGarageSitePrimaryTab?.classList.toggle('is-active', page === 'primary')
    apexGarageSiteListingsTab?.classList.toggle('is-active', showListings || page === 'details')
    const available = (apexGarageSiteData?.locations || []).filter((item) => item.occupied !== true && item.owned !== true)
    const count = document.getElementById('apex-garage-site-count')
    const countLabel = document.querySelector('.apex-site-count span')
    if (showListings) {
        document.getElementById('apex-site-heading').textContent = 'Garagens à venda.'
        document.getElementById('apex-site-subheading').textContent = 'Veja as fotos, o local. a capacidade e o valor do novo local'
        if (count) count.textContent = String(available.length).padStart(2, '0')
        if (countLabel) countLabel.innerHTML = 'LOCAIS<br>DISPONÍVEIS'
        document.getElementById('apex-site-footer-help').textContent = 'VISUALIZAR GARAGENS'
    } else if (showOwnedVehicles) {
        document.getElementById('apex-site-heading').textContent = 'Seus veículos.'
        document.getElementById('apex-site-subheading').textContent = 'Todos seus veículos em sua garagem.'
        if (count) count.textContent = String(apexGarageSiteData?.vehicles?.length || 0).padStart(2, '0')
        if (countLabel) countLabel.innerHTML = 'VEÍCULOS<br>REGISTRADOS'
        document.getElementById('apex-site-footer-help').textContent = 'SEUS VEÍCULOS'
    } else {
        document.getElementById('apex-site-heading').textContent = 'Conheça esta garagem.'
        document.getElementById('apex-site-subheading').textContent = 'Veja as fotos e os detalhes antes de comprar.'
        const selected = getApexGarageLocation(apexGarageSiteSelectedId)
        if (count) count.textContent = String(Number(selected?.capacity) || 6).padStart(2, '0')
        if (countLabel) countLabel.innerHTML = 'VAGAS<br>DO LOCAL'
        document.getElementById('apex-site-footer-help').textContent = 'VER DETALHES DA GARAGEM'
    }
}

function getApexGarageLocation(id) {
    return apexGarageSiteData?.locations.find((item) => Number(item.id) === Number(id)) || null
}

function setApexGaragePhoto(location, view = 'exterior') {
    const image = document.querySelector('.apex-garage-photo-image')
    const exterior = location?.exteriorPhoto || 'https://cfx-nui-apexplayergarage/ui/img/garage-property-exterior.jpg'
    const interior = location?.interiorPhoto || 'https://cfx-nui-apexplayergarage/ui/img/garage-property-preview.jpg'
    const scene = document.querySelector('.apex-garage-photo-scene')
    const showingExterior = view !== 'interior'
    if (image) {
        image.hidden = false
        if (scene) scene.style.display = 'none'
        image.src = showingExterior ? exterior : interior
        image.alt = showingExterior ? 'Fachada externa da garagem' : 'Interior da garagem'
        image.onerror = () => {
            image.onerror = null
            image.hidden = true
            if (scene) scene.style.display = 'block'
        }
    }
    document.querySelectorAll('[data-garage-photo]').forEach((button) => {
        button.classList.toggle('is-active', button.dataset.garagePhoto === (showingExterior ? 'exterior' : 'interior'))
    })
}

function showApexGarageLocation(location) {
    if (!location) return
    apexGarageSiteSelectedId = Number(location.id)
    const name = String(location.label || 'Garagem particular')
    const address = name.toUpperCase()
    const preview = document.getElementById('apex-site-property-name')
    const copy = document.getElementById('apex-site-property-copy')
    const action = document.getElementById('apex-site-action')
    const available = location.occupied !== true && location.owned !== true
    const capacity = Number(location.tier) >= 2 ? 6 : 2
    const priceText = `$${Number(location.price || 25000).toLocaleString('pt-BR')}`
    setApexGarageSitePage('details')
    document.getElementById('apex-garage-site-count').textContent = String(capacity).padStart(2, '0')
    document.querySelector('.apex-site-count span').innerHTML = 'VAGAS<br>DO LOCAL'
    document.getElementById('apex-site-heading').textContent = 'Conheça esta garagem.'
    document.getElementById('apex-site-subheading').textContent = 'Confira a fachada e o interior antes de confirmar a compra.'
    document.getElementById('apex-site-photo-title').textContent = name.toUpperCase()
    document.getElementById('apex-site-photo-address').textContent = address
    document.getElementById('apex-site-photo-capacity').textContent = `${String(capacity).padStart(2, '0')} VAGAS`
    document.getElementById('apex-site-current-capacity').textContent = 'NOVA GARAGEM'
    document.getElementById('apex-site-next-capacity').textContent = `${String(capacity).padStart(2, '0')} VAGAS`
    document.getElementById('apex-site-plan-price').textContent = priceText
    document.getElementById('apex-site-property-tag').textContent = 'GARAGEM APEX'
    document.getElementById('apex-site-property-number').textContent = `LOCAL ${String(location.id).padStart(2, '0')}`
    document.getElementById('apex-site-property-area').textContent = 'ENDEREÇO DA GARAGEM'
    if (preview) preview.textContent = name
    if (copy) copy.textContent = `Garagem Tier ${Number(location.tier) || 1} com capacidade para ${capacity} veículos. Veja as fotos do local antes de comprar.`
    document.getElementById('apex-site-capacity-label').textContent = 'CAPACIDADE INICIAL'
    document.getElementById('apex-site-capacity').textContent = `${String(capacity).padStart(2, '0')} VAGAS`
    document.getElementById('apex-site-price-label').textContent = 'VALOR DA GARAGEM'
    document.getElementById('apex-site-price').textContent = priceText
    const currentAddress = document.getElementById('apex-site-current-address')
    currentAddress.hidden = false
    currentAddress.textContent = `ENDEREÇO · ${name}`
    action.hidden = !available
    action.disabled = !available
    action.querySelector('span').textContent = 'CONTINUAR PARA COMPRA'
    setApexGaragePhoto(location, 'exterior')
    apexGarageSitePrimaryTab.textContent = apexGarageSiteData?.owned === true ? 'MINHA GARAGEM' : 'DETALHES'
}

function submitApexGarageSitePurchase(location) {
    if (!location || location.occupied === true || location.owned === true) return
    const price = `$${Number(location.price || 25000).toLocaleString('pt-BR')}`
    closeApexGarageSite(false)
    postNui('submitApexGarageSite', { mode: 'purchase', locationId: Number(location.id), locationName: location.label || 'Garagem APEX', price, capacity: Number(location.tier) >= 2 ? 6 : 2, tier: Number(location.tier) || 1 })
}

function renderApexGarageListings() {
    const grid = document.getElementById('apex-garage-listings-grid')
    if (!grid || !apexGarageSiteData) return
    const owned = apexGarageSiteData.owned === true
    const available = apexGarageSiteData.locations.filter((item) => item.occupied !== true && item.owned !== true)
    grid.replaceChildren()
    document.getElementById('apex-garage-listings-title').textContent = owned ? 'Garagens de 6 vagas disponíveis' : 'Escolha sua garagem'
    document.getElementById('apex-garage-listings-copy').textContent = owned
        ? 'Escolha uma nova garagem de 6 vagas para comprar.'
        : 'Compare os locais disponíveis. Cada endereço possui saída própria.'
    document.getElementById('apex-garage-listings-count').textContent = `${String(available.length).padStart(2, '0')} ${available.length === 1 ? 'LOCAL' : 'LOCAIS'}`
    if (!available.length) {
        const empty = document.createElement('div')
        empty.className = 'apex-garage-listings-empty'
        empty.textContent = 'Não há garagens disponíveis para visualização agora.'
        grid.appendChild(empty)
        return
    }
    available.forEach((location, index) => {
        const card = document.createElement('article')
        card.className = 'apex-garage-listing-card is-clickable'
        card.tabIndex = 0
        const image = document.createElement('img')
        image.src = location.exteriorPhoto || 'https://cfx-nui-apexplayergarage/ui/img/garage-property-exterior.jpg'
        image.alt = `Foto da garagem ${location.label || index + 1}`
        image.style.objectPosition = `${48 + (index % 3) * 5}% ${42 + (index % 2) * 8}%`
        const photo = document.createElement('div')
        photo.className = 'apex-garage-listing-photo'
        image.onerror = () => { image.remove(); photo.classList.add('is-placeholder') }
        photo.append(image)
        const photoTag = document.createElement('span')
        photoTag.className = 'apex-garage-listing-tag'
        photoTag.textContent = `APEX GARAGE · LOCAL ${String(location.id).padStart(2, '0')}`
        photo.append(photoTag)
        const info = document.createElement('div')
        info.className = 'apex-garage-listing-info'
        const area = document.createElement('small')
        area.textContent = 'ENDEREÇO DISPONÍVEL'
        const name = document.createElement('h4')
        name.textContent = String(location.label || `Garagem ${index + 1}`)
        const facts = document.createElement('div')
        facts.className = 'apex-garage-listing-facts'
        const locationCapacity = Number(location.tier) >= 2 ? 6 : 2
        facts.innerHTML = `<span><i class="fa-solid fa-warehouse"></i> TIER ${Number(location.tier) || 1} · ${String(locationCapacity).padStart(2, '0')} VAGAS</span>`
        const price = document.createElement('b')
        price.textContent = `$${Number(location.price || 25000).toLocaleString('pt-BR')}`
        facts.append(price)
        const action = document.createElement('button')
        action.type = 'button'
        action.disabled = false
        action.className = 'apex-garage-listing-action'
        action.textContent = 'Detalhes da Garagem'
        action.addEventListener('click', (event) => { event.stopPropagation(); showApexGarageLocation(location) })
        info.append(area, name, facts, action)
        card.append(photo, info)
        card.addEventListener('click', () => showApexGarageLocation(location))
        card.addEventListener('keydown', (event) => {
            if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); showApexGarageLocation(location) }
        })
        grid.appendChild(card)
    })
}

function renderApexOwnedGarageVehicles() {
    const grid = document.getElementById('apex-garage-owned-grid')
    if (!grid || !apexGarageSiteData) return
    const vehicles = Array.isArray(apexGarageSiteData.vehicles) ? apexGarageSiteData.vehicles : []
    grid.replaceChildren()
    document.getElementById('apex-garage-owned-count').textContent = `${String(vehicles.length).padStart(2, '0')} ${vehicles.length === 1 ? 'VEÍCULO' : 'VEÍCULOS'}`
    if (!vehicles.length) {
        const empty = document.createElement('div')
        empty.className = 'apex-garage-listings-empty'
        empty.textContent = 'Nenhum veículo registrado nas suas garagens.'
        grid.appendChild(empty)
        return
    }
    for (const vehicle of vehicles) {
        const card = document.createElement('article')
        card.className = 'apex-garage-owned-card'
        const icon = document.createElement('i')
        icon.className = 'fa-solid fa-car-side'
        const details = document.createElement('div')
        const name = document.createElement('b')
        name.textContent = String(vehicle.displayName || vehicle.model || 'Veículo')
        const plate = document.createElement('small')
        plate.textContent = `PLACA ${String(vehicle.plate || '---')} · ${String(vehicle.garageName || 'Garagem pessoal')}`
        details.append(name, plate)
        const state = document.createElement('span')
        state.textContent = vehicle.stored ? 'GUARDADO' : 'EM USO'
        card.append(icon, details, state)
        grid.appendChild(card)
    }
}

apexGarageSitePrimaryTab?.addEventListener('click', () => {
    if (apexGarageSiteData?.owned === true) openApexGarageSite(apexGarageSiteData)
    else if (getApexGarageLocation(apexGarageSiteSelectedId)) showApexGarageLocation(getApexGarageLocation(apexGarageSiteSelectedId))
    else setApexGarageSitePage('primary')
})
apexGarageSiteListingsTab?.addEventListener('click', () => setApexGarageSitePage('listings'))
document.querySelectorAll('[data-garage-photo]').forEach((button) => {
    button.addEventListener('click', () => {
        const selected = getApexGarageLocation(apexGarageSiteSelectedId)
        setApexGaragePhoto(selected, button.dataset.garagePhoto)
    })
})

function closeApexGarageSite(sendCallback = true) {
    apexGarageSiteOpen = false
    apexGarageSite?.classList.remove('is-open')
    apexGarageSite?.setAttribute('aria-hidden', 'true')
    if (sendCallback) postNui('closeApexGarageSite')
}

function openApexGarageSite(data) {
    if (!apexGarageSite || !data || typeof data !== 'object') return
    apexGarageSiteData = { ...data, locations: Array.isArray(data.locations) ? data.locations.filter((item) => item && Number(item.id)) : [] }
    apexGarageSiteOpen = true
    const locations = apexGarageSiteData.locations
    const selected = locations.find((item) => Number(item.id) === Number(data.selectedLocationId))
        || locations.find((item) => item.occupied !== true)
    apexGarageSiteSelectedId = Number((data.owned === true
        ? locations.find((item) => item.owned === true || Number(item.id) === Number(data.currentLocationId))
        : selected)?.id) || null
    const currentCapacity = Number(data.capacity) || 2
    const address = selected?.label || data.currentLocationLabel
    const setText = (id, value) => { const el = document.getElementById(id); if (el) el.textContent = value }
    setText('apex-garage-site-count', String(currentCapacity).padStart(2, '0'))
    setText('apex-site-heading', data.owned ? 'Seus veículos.' : 'Seu novo espaço começa aqui.')
    setText('apex-site-subheading', data.owned ? 'Consulte os veículos registrados nas suas garagens.' : 'Uma garagem particular para guardar seus veículos com segurança.')
    setText('apex-site-photo-title', data.owned ? 'SUA GARAGEM' : 'GARAGEM APEX')
    setText('apex-site-photo-address', address ? String(address).toUpperCase() : 'ENDEREÇO VINCULADO AO SEU PERFIL')
    setText('apex-site-photo-capacity', `${String(data.owned ? currentCapacity : 2).padStart(2, '0')} VAGAS`)
    setText('apex-site-current-capacity', data.owned ? `${String(currentCapacity).padStart(2, '0')} VAGAS` : 'NOVA GARAGEM')
    setText('apex-site-next-capacity', `${String(Number(selected?.capacity) || 6).padStart(2, '0')} VAGAS`)
    setText('apex-site-plan-price', selected ? `$${Number(selected.price || 25000).toLocaleString('pt-BR')}` : '—')
    setText('apex-site-property-number', selected ? `LOCAL ${String(selected.id).padStart(2, '0')}` : 'MINHA COLEÇÃO')
    setText('apex-site-property-tag', data.owned ? 'APEX GARAGE' : 'GARAGEM APEX')
    setText('apex-site-property-area', data.owned ? 'VEÍCULOS REGISTRADOS' : 'ENDEREÇO DA GARAGEM')
    setText('apex-site-property-name', data.owned ? 'Seus veículos' : String(selected?.label || 'Garagem particular'))
    setText('apex-site-property-copy', data.owned ? 'Veja aqui os carros vinculados às suas garagens.' : 'Garagem independente com saída vinculada a este endereço.')
    setText('apex-site-capacity-label', 'CAPACIDADE DO LOCAL')
    setText('apex-site-capacity', `${String(Number(selected?.capacity) || 6).padStart(2, '0')} VAGAS`)
    setText('apex-site-price-label', 'VALOR DA GARAGEM')
    setText('apex-site-price', selected ? `$${Number(selected.price || 25000).toLocaleString('pt-BR')}` : '—')
    const currentAddress = document.getElementById('apex-site-current-address')
    if (currentAddress) {
        currentAddress.hidden = !address || data.owned === true
        currentAddress.textContent = address ? `ENDEREÇO · ${address}` : ''
    }
    const capacity = document.getElementById('apex-site-capacity')
    if (capacity) capacity.textContent = `${String(Number(selected?.capacity) || 6).padStart(2, '0')} VAGAS`
    apexGarageSiteAction.disabled = !apexGarageSiteSelectedId
    apexGarageSiteAction.hidden = true
    apexGarageSitePrimaryTab.textContent = data.owned === true ? 'MINHA GARAGEM' : 'DETALHES'
    renderApexGarageListings()
    const currentLocation = getApexGarageLocation(data.currentLocationId) || selected
    setApexGaragePhoto(currentLocation, 'exterior')
    renderApexOwnedGarageVehicles()
    setApexGarageSitePage(data.owned === true ? 'primary' : 'listings')
    apexGarageSite.classList.add('is-open')
    apexGarageSite.setAttribute('aria-hidden', 'false')
    document.getElementById('apex-garage-site-close')?.focus()
}

document.getElementById('apex-garage-site-close')?.addEventListener('click', () => closeApexGarageSite())
apexGarageSiteAction?.addEventListener('click', () => {
    if (!apexGarageSiteOpen || !apexGarageSiteSelectedId || apexGarageSiteAction.disabled) return
    const location = apexGarageSiteData?.locations.find((item) => Number(item.id) === apexGarageSiteSelectedId)
    submitApexGarageSitePurchase(location)
})
document.addEventListener('keydown', (event) => {
    if (!apexGarageSiteOpen) return
    if (event.key === 'Escape' || event.key === 'Backspace') {
        event.preventDefault(); event.stopImmediatePropagation(); closeApexGarageSite()
    } else if (event.key === 'Enter') {
        if (event.target instanceof HTMLElement && event.target.closest('button')) return
        if (apexGarageSitePage === 'listings') return
        event.preventDefault(); event.stopImmediatePropagation()
        apexGarageSiteAction?.click()
    } else if (event.key === 'Tab') {
        return
    } else {
        event.preventDefault(); event.stopImmediatePropagation()
    }
}, true)

function closeApexGaragePurchase(sendCallback = true) {
    apexGaragePurchaseOpen = false
    apexGaragePurchaseLocationId = null
    apexGaragePurchaseCapacity = null
    apexGaragePurchaseModal?.classList.remove('is-open')
    apexGaragePurchaseModal?.setAttribute('aria-hidden', 'true')
    if (sendCallback) postNui('closeApexGaragePurchaseConfirm')
}
function confirmApexGaragePurchase() {
    if (!apexGaragePurchaseOpen || (apexGaragePurchaseKind === 'purchase' && !apexGaragePurchaseLocationId)) return
    if (apexGaragePurchaseKind === 'upgrade' && !apexGaragePurchaseCapacity) return
    const locationId = apexGaragePurchaseLocationId
    const kind = apexGaragePurchaseKind
    const capacity = apexGaragePurchaseCapacity
    closeApexGaragePurchase(false)
    postNui('confirmApexGaragePurchase', { kind, locationId, capacity })
}
apexGaragePurchaseCancel?.addEventListener('click', (event) => {
    event.preventDefault()
    if (!apexGaragePurchaseOpen) return
    closeApexGaragePurchase()
})
apexGaragePurchaseConfirm?.addEventListener('click', (event) => {
    event.preventDefault()
    if (!apexGaragePurchaseOpen) return
    confirmApexGaragePurchase()
})
document.addEventListener('keydown', (event) => {
    if (!apexGaragePurchaseOpen) return
    if (event.key === 'Escape' || event.key === 'Backspace') {
        event.preventDefault()
        event.stopImmediatePropagation()
        closeApexGaragePurchase()
    } else if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
        event.preventDefault()
        event.stopImmediatePropagation()
        const target = event.key === 'ArrowLeft' ? apexGaragePurchaseCancel : apexGaragePurchaseConfirm
        target?.focus()
    } else if (event.key === 'Enter') {
        event.preventDefault()
        event.stopImmediatePropagation()
        if (document.activeElement === apexGaragePurchaseConfirm) confirmApexGaragePurchase()
        else closeApexGaragePurchase()
    } else {
        event.preventDefault()
        event.stopImmediatePropagation()
    }
}, true)

function setVehicleQuickMenuState(isOpen, payload = {}) {
    vehicleQuickMenuOpen = isOpen === true
    vehicleQuickMenu?.classList.toggle('is-open', vehicleQuickMenuOpen)
    vehicleQuickMenu?.setAttribute('aria-hidden', String(!vehicleQuickMenuOpen))
    document.body.classList.toggle('vehicle-quick-menu-open', vehicleQuickMenuOpen)

    if (!vehicleQuickMenuOpen) return

    if (vehicleQuickMenuName) {
        vehicleQuickMenuName.textContent = String(payload.vehicleName || 'VEÍCULO').toUpperCase()
    }

    const moving = payload.moving === true
    vehicleQuickActionButtons.forEach((button) => {
        const action = button.dataset.vehicleAction
        const status = button.querySelector(`[data-vehicle-status="${action}"]`)
        const label = button.querySelector('.vehicle-quick-label')
        const disabledForMotion = moving && (action === 'doors' || action === 'repair')

        button.disabled = disabledForMotion
        if (status) status.textContent = disabledForMotion ? 'EM MOVIMENTO.' : ''

        if (action === 'engine' && label) {
            label.textContent = payload.engineOn === true ? 'DESLIGAR VEÍCULO' : 'LIGAR VEÍCULO'
        }
        if (action === 'hazards' && status && !disabledForMotion && payload.hazardsOn === true) {
            status.textContent = 'ATIVO'
        }
    })
}

vehicleQuickActionButtons.forEach((button) => {
    button.addEventListener('click', () => {
        if (button.disabled) return
        postNui('vehicleQuickMenuAction', { actionId: button.dataset.vehicleAction })
    })
})

vehicleQuickCloseButton?.addEventListener('click', () => postNui('closeVehicleQuickMenu'))

function renderSpeed(speed) {
    const clamped = Math.max(0, Math.min(999, Number(speed) || 0))
    const padded = String(clamped).padStart(3, '0')
    const firstActiveIndex = clamped === 0 ? padded.length : padded.search(/[1-9]/)

    speedDigits.forEach((digitNode, index) => {
        digitNode.textContent = padded[index]
        digitNode.classList.toggle('is-muted', clamped === 0 || index < firstActiveIndex)
    })
}

function renderGear(gear) {
    const normalized = String(gear || 'N').trim().toUpperCase()
    speedometerGearValue.textContent = normalized.slice(0, 1) || 'N'
}

function renderUnit(unit) {
    const normalized = String(unit || 'KM/H').trim().toUpperCase()
    speedometerUnit.textContent = normalized || 'KM/H'
}

function renderRpm(rpm) {
    const normalized = Math.max(0, Math.min(1, Number(rpm) || 0))
    const activeSegments = Math.max(0, Math.ceil(normalized * rpmSegments.length))

    rpmSegments.forEach((segment, index) => {
        segment.classList.toggle('is-active', index < activeSegments)
    })
}

function renderAssist(absActive, handbrakeActive) {
    speedometerAbs.classList.toggle('is-active', absActive === true)
    speedometerHbk.classList.toggle('is-active', handbrakeActive === true)
}

function setEscMenuOpenState(isOpen) {
    escMenuOpen = isOpen === true

    // O menu novo e o menu antigo nunca ficam visiveis ao mesmo tempo.
    // A nova versao e o iframe #apex-new-esc.
    escMenu.classList.remove('is-open')
    escMenu.setAttribute('aria-hidden', 'true')

    if (apexNewEsc) {
        apexNewEsc.classList.toggle('is-open', escMenuOpen)
        apexNewEsc.setAttribute('aria-hidden', String(!escMenuOpen))
    }

    if (!escMenuOpen && apexNewEscFrame && apexNewEscFrame.contentWindow) {
        apexNewEscFrame.contentWindow.postMessage({ type: 'apex-esc-closed' }, '*')
    }

    document.body.classList.toggle('esc-menu-open', escMenuOpen)

    if (escMenuOpen && apexNewEscFrame) {
        // Garante que o iframe receba teclado imediatamente apos abrir.
        setTimeout(() => {
            try {
                apexNewEscFrame.focus()
                apexNewEscFrame.contentWindow?.focus()
            } catch (_) {}
        }, 50)
    }
}

function syncRadialCoreState() {
    radialMenuCore.classList.toggle('is-backable', radialMenuOpen && radialCanGoBack)
}

function setRadialMenuOpenState(isOpen) {
    radialMenuOpen = isOpen === true
    if (!radialMenuOpen) {
        radialCanGoBack = false
    }
    radialMenu.classList.toggle('is-open', radialMenuOpen)
    radialMenu.setAttribute('aria-hidden', String(!radialMenuOpen))
    document.body.classList.toggle('radial-menu-open', radialMenuOpen)
    syncRadialCoreState()
}

function createEscMenuButton(item, index) {
    const button = document.createElement('button')
    button.type = 'button'
    button.className = 'esc-nav-item'
    button.dataset.index = String(index)
    button.dataset.itemId = item.id || ''

    if (item.enabled === false) {
        button.classList.add('is-disabled')
    }

    const copy = document.createElement('span')
    copy.className = 'esc-nav-copy'
    copy.textContent = String(item.kicker || 'MENU').toUpperCase()

    const label = document.createElement('strong')
    label.className = 'esc-nav-label'
    label.textContent = String(item.label || 'ITEM').toUpperCase()

    button.append(copy, label)

    if (item.enabled === false) {
        const lock = document.createElement('i')
        lock.className = 'fa-solid fa-lock esc-nav-lock'
        button.appendChild(lock)
    }

    button.addEventListener('mouseenter', () => {
        setActiveEscItem(index)
    })

    button.addEventListener('focus', () => {
        setActiveEscItem(index)
    })

    button.addEventListener('click', () => {
        activateEscItem(index)
    })

    return button
}

function buildEscMenuButtons() {
    escMenuNav.innerHTML = ''

    escMenuItems.forEach((item, index) => {
        escMenuNav.appendChild(createEscMenuButton(item, index))
    })
}

function setActiveEscItem(index) {
    if (!escMenuItems.length) {
        escActiveIndex = 0
        return
    }

    const clampedIndex = Math.max(0, Math.min(escMenuItems.length - 1, Number(index) || 0))
    escActiveIndex = clampedIndex

    Array.from(escMenuNav.children).forEach((button, buttonIndex) => {
        button.classList.toggle('is-active', buttonIndex === escActiveIndex)
    })
}

function moveEscSelection(step) {
    if (!escMenuItems.length) {
        return
    }

    const length = escMenuItems.length
    const nextIndex = (escActiveIndex + step + length) % length
    setActiveEscItem(nextIndex)
}

function activateEscItem(index = escActiveIndex) {
    const item = escMenuItems[index]
    if (!item || item.enabled === false) {
        return
    }

    postNui('activateEscMenuItem', { itemId: item.id })
}

function getInitials(name) {
    const clean = String(name || 'APEX').trim()
    if (!clean) {
        return 'AP'
    }

    const parts = clean.split(/\s+/).slice(0, 2)
    return parts.map((part) => part[0] || '').join('').toUpperCase() || clean.slice(0, 2).toUpperCase()
}

function formatCount(value, fallback = '---') {
    const normalized = Number(value)
    if (!Number.isFinite(normalized)) {
        return fallback
    }

    return Math.max(0, Math.floor(normalized)).toLocaleString('pt-BR')
}

function formatPercent(value, fallback = '---%') {
    const normalized = Number(value)
    if (!Number.isFinite(normalized)) {
        return fallback
    }

    return `${normalized.toFixed(1).replace('.', ',')}%`
}

function formatSlug(value) {
    const normalized = String(value || 'piloto')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '')

    return normalized || 'piloto'
}

function setProfileAvatar(avatarUrl, displayName) {
    const safeUrl = typeof avatarUrl === 'string' ? avatarUrl.trim() : ''
    const fallback = getInitials(displayName)

    escProfileAvatarFallback.textContent = fallback

    if (safeUrl) {
        escProfileAvatarImage.src = safeUrl
        escProfileAvatarImage.classList.add('is-visible')
        escProfileAvatarFallback.classList.remove('is-visible')
        return
    }

    escProfileAvatarImage.removeAttribute('src')
    escProfileAvatarImage.classList.remove('is-visible')
    escProfileAvatarFallback.classList.add('is-visible')
}

function setTextContent(node, value, fallback = '---') {
    if (!node) {
        return
    }

    const normalized = value === undefined || value === null || value === '' ? fallback : value
    node.textContent = String(normalized)
}

function setProfileOverlay(visible, kicker, title, text) {
    escProfileEmptyState.classList.toggle('is-visible', visible)
    setTextContent(escProfileEmptyKicker, kicker, 'Perfil')
    setTextContent(escProfileEmptyTitle, title, 'CARREGANDO')
    setTextContent(escProfileEmptyText, text, 'Buscando estatisticas do piloto.')
}

function renderEscProfile(payload = {}, isVisible = false) {
    escProfileOpen = isVisible
    escProfilePanel.classList.toggle('is-visible', isVisible)
    escProfilePanel.setAttribute('aria-hidden', String(!isVisible))
    escMenu.classList.toggle('is-profile-mode', escMenuOpen && escProfileOpen)

    if (!isVisible) {
        setProfileOverlay(false)
        return
    }

    const available = payload.available !== false
    const loading = payload.loading === true
    const data = payload.data || {}
    const profile = data.profile || {}
    const stats = data.stats || {}
    const recordTracks = Array.isArray(data.recordTracks) ? data.recordTracks : []
    const recentRaces = Array.isArray(data.recentRaces) ? data.recentRaces : []
    const bestRecord = recordTracks[0] || null
    const recentRace = recentRaces[0] || null
    const favoriteCar = stats.mostUsedCar || null

    const displayName = String(profile.displayName || 'PILOTO')
    const avatarId = Number(profile.avatarId) || 1

    setProfileAvatar(profile.avatarUrl, displayName)
    setTextContent(escProfileDisplayName, displayName, 'PILOTO')
    setTextContent(escProfileSubline, `Avatar #${avatarId} • Perfil Apex Racing`, 'Perfil Apex Racing')
    setTextContent(escProfileRankValue, 'EM BREVE')
    setTextContent(escProfileRankSubtext, 'Sistema de niveis ainda nao integrado.')
    setTextContent(escProfileRankMax, '--- MMR')
    setTextContent(escProfileLinkChip, `@${formatSlug(displayName)}`, '@piloto')

    setTextContent(escProfileStatRecords, formatCount(stats.tracksWithRecords))
    setTextContent(escProfileStatWinrate, formatPercent(stats.winRate))
    setTextContent(escProfileStatWins, formatCount(stats.wins))
    setTextContent(escProfileStatRaces, formatCount(stats.totalMultiplayerRaces))
    setTextContent(escProfileStatRacesMeta, stats.totalMultiplayerRaces > 0 ? 'Participacoes registradas em lobbys.' : 'Sem corridas multiplayer registradas.')
    setTextContent(escProfileStatCreated, formatCount(stats.tracksCreated))
    setTextContent(escProfileStatCreatedMeta, stats.tracksCreated > 0 ? 'Conteudo publicado pelo piloto.' : 'Nenhuma pista criada ainda.')
    setTextContent(escProfileLevelMax, '---')
    setTextContent(escProfileLevelMaxMeta, 'Progressao ainda nao sincronizada.')

    if (favoriteCar) {
        setTextContent(escProfileFavoriteCarName, favoriteCar.name, 'Sem dados')
        setTextContent(
            escProfileFavoriteCarMeta,
            `${formatCount(favoriteCar.uses, '0')} usos${favoriteCar.model ? ` • ${favoriteCar.model}` : ''}`,
            'Sem historico suficiente ainda.'
        )
    } else {
        setTextContent(escProfileFavoriteCarName, 'SEM DADOS')
        setTextContent(escProfileFavoriteCarMeta, 'Sem historico suficiente ainda.')
    }

    if (bestRecord) {
        setTextContent(escProfileBestTime, bestRecord.bestTimeFormatted, '--:--.--')
        setTextContent(escProfileBestTimeMeta, bestRecord.vehicle ? `Com ${bestRecord.vehicle}` : 'Recorde pessoal do piloto.')
        setTextContent(escProfileBestTrack, bestRecord.trackName, '---')
        setTextContent(escProfileBestTrackMeta, 'Pista em que o piloto entregou seu melhor tempo.')
    } else {
        setTextContent(escProfileBestTime, '--:--.--')
        setTextContent(escProfileBestTimeMeta, 'Sem recorde registrado.')
        setTextContent(escProfileBestTrack, '---')
        setTextContent(escProfileBestTrackMeta, 'Melhor pista do piloto.')
    }

    if (recentRace) {
        const resultLabel = recentRace.position > 0 && recentRace.playerCount > 0
            ? `${recentRace.position}º de ${recentRace.playerCount}`
            : recentRace.didFinish === false
                ? 'Nao concluiu'
                : 'Sem colocacao'

        setTextContent(escProfileLastRace, recentRace.trackName, '---')
        setTextContent(escProfileLastRaceMeta, resultLabel)
        setTextContent(escProfileLastVehicle, recentRace.vehicle, '---')
        setTextContent(escProfileLastVehicleMeta, `Tipo ${String(recentRace.trackType || 'sprint').toUpperCase()}`)
        setTextContent(escProfileBestLap, recentRace.bestLapFormatted, '---')
        setTextContent(escProfileBestLapMeta, recentRace.finishTimeFormatted ? `Tempo final ${recentRace.finishTimeFormatted}` : 'Referencia da ultima corrida.')
    } else {
        setTextContent(escProfileLastRace, '---')
        setTextContent(escProfileLastRaceMeta, 'Sem corrida recente.')
        setTextContent(escProfileLastVehicle, '---')
        setTextContent(escProfileLastVehicleMeta, 'Ultimo carro usado em corrida.')
        setTextContent(escProfileBestLap, '---')
        setTextContent(escProfileBestLapMeta, 'Referencia da ultima corrida.')
    }

    escProfileEditButton.disabled = !available
    escProfileRefreshButton.disabled = !available

    if (!available) {
        setProfileOverlay(true, 'Perfil', 'INDISPONIVEL', 'Inicie o recurso apexracing para carregar as estatisticas do piloto.')
        return
    }

    if (loading) {
        setProfileOverlay(true, 'Sincronizando', 'CARREGANDO', 'Atualizando estatisticas do piloto e o resumo do perfil.')
        return
    }

    setProfileOverlay(false)
}

function renderEscMenuContext(payload = {}) {
    escMenuItems = Array.isArray(payload.items) ? payload.items : []
    buildEscMenuButtons()

    let selectedIndex = escMenuItems.findIndex((item) => item.id === payload.selectedId)
    if (selectedIndex === -1) {
        selectedIndex = 0
    }

    renderEscProfile(payload.profile || {}, payload.selectedId === 'profile')
    setActiveEscItem(selectedIndex)

    if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
        apexNewEscFrame.contentWindow.postMessage({
            type: 'apex-esc-profile-summary',
            displayName: payload.profile && payload.profile.data && payload.profile.data.profile
                ? payload.profile.data.profile.displayName
                : 'PILOTO'
        }, '*')
        apexNewEscFrame.contentWindow.postMessage({ type: 'apex-economy-summary', economy: payload.economy || {} }, '*')
        apexNewEscFrame.contentWindow.postMessage({
            type: 'apex-environment-state',
            environment: payload.environment || null
        }, '*')
        apexNewEscFrame.contentWindow.postMessage({
            type: 'apex-hud-settings',
            settings: payload.settings || {}
        }, '*')
    }
}

function getRadialItemIcon(item) {
    const rawIcon = item && typeof item.icon === 'string' ? item.icon.trim() : ''
    if (rawIcon.length > 0) {
        return rawIcon.startsWith('fa-') ? rawIcon : `fa-${rawIcon}`
    }

    const itemId = item && typeof item.id === 'string' ? item.id : ''
    return radialIconMap[itemId] || 'fa-circle'
}

function polarToPercent(angleDeg, radius) {
    const radians = (angleDeg * Math.PI) / 180
    return {
        x: 50 + (Math.cos(radians) * radius),
        y: 50 + (Math.sin(radians) * radius)
    }
}

function buildRadialSegmentPath(startAngle, endAngle, innerRadius, outerRadius, steps = 16) {
    const points = []

    for (let index = 0; index <= steps; index += 1) {
        const progress = index / steps
        const angle = startAngle + ((endAngle - startAngle) * progress)
        const point = polarToPercent(angle, outerRadius)
        points.push(`${point.x}% ${point.y}%`)
    }

    for (let index = steps; index >= 0; index -= 1) {
        const progress = index / steps
        const angle = startAngle + ((endAngle - startAngle) * progress)
        const point = polarToPercent(angle, innerRadius)
        points.push(`${point.x}% ${point.y}%`)
    }

    return `polygon(${points.join(',')})`
}

function createRadialMenuButton(item, index, total) {
    const button = document.createElement('button')
    button.type = 'button'
    button.className = 'radial-menu-item'
    button.dataset.index = String(index)
    button.dataset.itemId = item.id || ''

    const arc = 300
    const slotCount = Math.max(total, 6)
    const slotIndex = Number.isFinite(Number(item.slot)) ? Number(item.slot) : index
    const step = arc / slotCount
    const angle = -150 + (step * slotIndex) + (step / 2)
    const gap = Math.min(6, step * 0.14)
    const startAngle = angle - (step / 2) + (gap / 2)
    const endAngle = angle + (step / 2) - (gap / 2)
    const iconPoint = polarToPercent(angle, 34)

    button.style.clipPath = buildRadialSegmentPath(startAngle, endAngle, 28, 42)

    if (item.enabled === false) {
        button.classList.add('is-disabled')
    }

    const iconWrap = document.createElement('span')
    iconWrap.className = 'radial-menu-icon'
    iconWrap.style.left = `${iconPoint.x}%`
    iconWrap.style.top = `${iconPoint.y}%`

    const icon = document.createElement('i')
    icon.className = `fa-solid ${getRadialItemIcon(item)}`
    iconWrap.appendChild(icon)

    const kicker = document.createElement('span')
    kicker.className = 'radial-menu-item-kicker'
    kicker.textContent = String(item.kicker || 'MENU').toUpperCase()

    const label = document.createElement('strong')
    label.className = 'radial-menu-item-label'
    label.textContent = String(item.label || 'ITEM').toUpperCase()

    button.append(iconWrap, kicker, label)

    if (item.enabled === false) {
        const lock = document.createElement('i')
        lock.className = 'fa-solid fa-lock radial-menu-lock'
        button.appendChild(lock)
    }

    button.addEventListener('mouseenter', () => {
        setActiveRadialItem(index)
    })

    button.addEventListener('focus', () => {
        setActiveRadialItem(index)
    })

    button.addEventListener('click', () => {
        activateRadialItem(index)
    })

    return button
}

function buildRadialMenuButtons() {
    radialMenuItemsContainer.innerHTML = ''

    radialMenuItems.forEach((item, index) => {
        radialMenuItemsContainer.appendChild(createRadialMenuButton(item, index, radialMenuItems.length))
    })
}

radialMenuCore.addEventListener('click', () => {
    if (!radialMenuOpen || !radialCanGoBack) {
        return
    }

    postNui('backRadialMenu')
})

function setActiveRadialSummary(item) {
    if (!item) {
        radialMenuKicker.textContent = 'APEX'
        radialMenuTitle.textContent = 'RADIAL'
        radialMenuTitle.classList.remove('is-compact', 'is-xcompact')
        radialMenuSubtitle.textContent = 'EM BREVE'
        return
    }

    const title = String(item.label || 'RADIAL').toUpperCase()
    const compactTitle = title.length >= 14
    const extraCompactTitle = title.length >= 20

    radialMenuKicker.textContent = String(item.kicker || 'APEX').toUpperCase()
    radialMenuTitle.textContent = title
    radialMenuTitle.classList.toggle('is-compact', compactTitle)
    radialMenuTitle.classList.toggle('is-xcompact', extraCompactTitle)
    radialMenuSubtitle.textContent = item.enabled === false ? 'EM BREVE' : 'CLIQUE PARA ABRIR'
}

function setActiveRadialItem(index) {
    if (!radialMenuItems.length) {
        radialActiveIndex = 0
        setActiveRadialSummary(null)
        return
    }

    const clampedIndex = Math.max(0, Math.min(radialMenuItems.length - 1, Number(index) || 0))
    radialActiveIndex = clampedIndex
    const activeItem = radialMenuItems[radialActiveIndex]

    Array.from(radialMenuItemsContainer.children).forEach((button, buttonIndex) => {
        button.classList.toggle('is-active', buttonIndex === radialActiveIndex)
    })

    setActiveRadialSummary(activeItem)
}

function activateRadialItem(index = radialActiveIndex) {
    const item = radialMenuItems[index]
    if (!item || item.enabled === false) {
        return
    }

    postNui('activateRadialMenuItem', { itemId: item.id })
}

function renderRadialMenuContext(payload = {}) {
    radialCanGoBack = payload.canGoBack === true
    radialMenuItems = Array.isArray(payload.items) ? payload.items : []
    buildRadialMenuButtons()
    syncRadialCoreState()

    let selectedIndex = radialMenuItems.findIndex((item) => item.id === payload.selectedId)
    if (selectedIndex === -1) {
        selectedIndex = 0
    }

    setActiveRadialItem(selectedIndex)
}

escProfileRefreshButton.addEventListener('click', () => {
    postNui('refreshEscProfile')
})

escProfileEditButton.addEventListener('click', () => {
    postNui('openEscProfileEditor')
})

escProfileAvatarImage.addEventListener('error', () => {
    escProfileAvatarImage.removeAttribute('src')
    escProfileAvatarImage.classList.remove('is-visible')
    escProfileAvatarFallback.classList.add('is-visible')
})

window.addEventListener('keydown', (event) => {
    const key = String(event.key || '').toLowerCase()

    if (vehicleQuickMenuOpen) {
        const actionByKey = { '1': 'engine', '2': 'hazards', '3': 'doors', '4': 'repair' }
        if (actionByKey[key]) {
            event.preventDefault()
            postNui('vehicleQuickMenuAction', { actionId: actionByKey[key] })
        } else if (key === 'escape' || key === 'backspace') {
            event.preventDefault()
            postNui('closeVehicleQuickMenu')
        }
        return
    }

    if (radialMenuOpen) {
        if (key === 'escape' || key === 'backspace' || key === 'z') {
            event.preventDefault()
            postNui('closeRadialMenu')
            return
        }
        if (key === 'enter' || key === ' ' || key === 'arrowright' || key === 'arrowdown' || key === 'arrowleft' || key === 'arrowup' || key === 'd' || key === 's' || key === 'a' || key === 'w') {
            event.preventDefault()
        }
        return
    }

    if (!escMenuOpen) {
        return
    }

    if (escProfileOpen) {
        if (key === 'escape' || key === 'backspace') {
            event.preventDefault()
            postNui('closeEscMenu')
        }
        return
    }

    if (key === 'escape' || key === 'backspace') {
        event.preventDefault()
        postNui('closeEscMenu')
        return
    }

    if (key === 'arrowdown' || key === 's') {
        event.preventDefault()
        moveEscSelection(1)
        return
    }

    if (key === 'arrowup' || key === 'w') {
        event.preventDefault()
        moveEscSelection(-1)
        return
    }

    if (key === 'enter' || key === ' ') {
        event.preventDefault()
        activateEscItem()
    }
})

window.addEventListener('message', (event) => {
    if (event.data && event.data.action === 'setVehicleSwapHudHidden') {
        document.body.classList.toggle('vehicle-swap-camera-active', event.data.hidden === true)
        return
    }

    // O novo menu ESC roda em um iframe. Quando ele precisa executar
    // uma acao Lua, pede ao documento principal para fazer o callback NUI.
    if (event.data && event.data.type === 'apex-close-esc') {
        postNui('closeEscMenu')
        return
    }

    if (event.data && event.data.type === 'apex-open-garage-catalog') {
        postNui('openApexGarageCatalog')
        return
    }

    if (event.data && event.data.type === 'apex-open-multiplayer-vehicle-picker') {
        postNui('openMultiplayerVehiclePicker')
        return
    }

    if (event.data && event.data.type === 'apex-preview-garage-vehicle') {
        postNui('previewApexGarageVehicle', { model: event.data.model })
        return
    }

    if (event.data && event.data.type === 'apex-stop-garage-preview') {
        postNui('stopApexGaragePreview')
        return
    }

    if (event.data && event.data.type === 'apex-spawn-garage-vehicle') {
        postNui('spawnApexGarageVehicle', {
            model: event.data.model,
            handlingType: event.data.handlingType
        })
        return
    }

    if (event.data && event.data.type === 'apex-activate-esc-item') {
        postNui('activateEscMenuItem', { itemId: event.data.itemId || 'continue' })
        return
    }

    if (event.data && event.data.type === 'apex-set-environment-time') {
        postNui('setEnvironmentTime', { hour: event.data.hour, minute: event.data.minute })
        return
    }

    if (event.data && event.data.type === 'apex-set-environment-weather') {
        postNui('setEnvironmentWeather', { weather: event.data.weather })
        return
    }

    if (event.data && event.data.type === 'apex-reset-environment') {
        postNui('resetEnvironment')
        return
    }

    if (event.data && event.data.type === 'apex-set-environment-lock') {
        postNui('setEnvironmentLock', { enabled: event.data.enabled === true })
        return
    }

    if (event.data && event.data.type === 'apex-set-environment-sync') {
        postNui('setEnvironmentServerSync', { enabled: event.data.enabled === true })
        return
    }

    if (event.data && event.data.type === 'apex-set-hud-option') {
        postNui('setHudOption', { option: event.data.option, value: event.data.value })
        return
    }

    if (event.data && event.data.type === 'apex-get-race-tracks') {
        postNui('getApexRaceTracks', { forceRefresh: event.data.forceRefresh === true })
        return
    }

    if (event.data && event.data.type === 'apex-start-race-practice') {
        postNui('startApexPractice', { trackId: event.data.trackId, laps: event.data.laps })
        return
    }

    if (event.data && event.data.type === 'apex-start-race-timetrial') {
        postNui('startApexTimeTrial', { trackId: event.data.trackId, laps: event.data.laps })
        return
    }

    if (event.data && event.data.type === 'apex-start-race-creation') {
        postNui('startApexTrackCreation', {})
        return
    }

    if (event.data && event.data.type === 'apex-get-my-tracks') {
        postNui('getMyApexTracks', {})
        return
    }

    if (event.data && event.data.type === 'apex-start-new-track') {
        postNui('startApexNewTrack', {})
        return
    }

    if (event.data && event.data.type === 'apex-get-track-records') {
        postNui('getApexTrackRecords', { trackId: event.data.trackId })
        return
    }

    if (event.data && event.data.type === 'apex-edit-track') {
        postNui('startApexTrackEdit', { trackId: event.data.trackId })
        return
    }

    if (event.data && event.data.type === 'apex-get-autohost-state') {
        postNui('getApexAutoHostState', {})
        return
    }

    if (event.data && event.data.type === 'apex-join-autohost') {
        postNui('joinApexAutoHost', { lobbyId: event.data.lobbyId })
        return
    }

    if (event.data && event.data.type === 'apex-leave-autohost') {
        postNui('leaveApexAutoHost', {})
        return
    }

    if (event.data && event.data.type === 'apex-send-lobby-chat') {
        postNui('sendApexLobbyChat', { message: event.data.message })
        return
    }

    if (event.data && event.data.type === 'apex-autohost-vote') {
        postNui('voteApexAutoHost', { choice: event.data.choice })
        return
    }

    const data = event.data || {}

    if (data.action === 'showApexGarageSite') {
        openApexGarageSite(data)
        return
    }
    if (data.action === 'hideApexGarageSite') {
        closeApexGarageSite(false)
        return
    }

    if (data.action === 'worldInteractionDot') {
        const dot = document.getElementById('world-interaction-dot')
        if (dot) {
            dot.classList.toggle('is-visible', data.visible === true)
            dot.classList.toggle('is-near', data.visible === true && data.near === true)
            if (data.visible === true) {
                const dx = Math.max(0, Math.min(1, Number(data.x) || 0)) * 100
                const dy = Math.max(0, Math.min(1, Number(data.y) || 0)) * 100
                dot.style.transform = `translate3d(calc(${dx}vw - 50%), calc(${dy}vh - 50%), 0)`
            }
        }
        return
    }

    if (data.action === 'worldInteractionPrompt') {
        const prompt = document.getElementById('world-interaction-prompt')
        if (prompt) {
            prompt.classList.toggle('is-visible', data.visible === true)
            if (data.visible === true) {
                const px = Math.max(0, Math.min(1, Number(data.x) || 0)) * 100
                const py = Math.max(0, Math.min(1, Number(data.y) || 0)) * 100
                prompt.style.transform = `translate3d(calc(${px}vw - 50%), calc(${py}vh - 50%), 0)`
                prompt.querySelector('.world-interaction-key').textContent = data.key || 'E'
                prompt.querySelector('.world-interaction-label').textContent = data.label || 'INTERAGIR'
            }
        }
        return
    }

    if (data.action === 'setTrackCreatorPermission') {
        apexTrackCreationAllowed = data.canCreate === true
        forwardApexTrackCreationPermission()
        return
    }

    if (data.action === 'setCreatorHudMode') {
        document.body.classList.toggle('creator-hud-active', data.active === true)
        return
    }

    if (data.action === 'updateHint') {
        document.body.classList.toggle('hide-hint', data.visible === false)
        return
    }

    if (data.action === 'updateSpeedUnit') {
        renderUnit(data.unit)

        const unit = String(data.unit || 'KM/H').toUpperCase()
        if (svgSpeedUnit) {
            svgSpeedUnit.innerText = unit.toLowerCase()
        }
        return
    }

    if (data.action === 'setEscMenuState') {
        const isVisible = data.visible === true
        setEscMenuOpenState(isVisible)

        if (isVisible) {
            renderEscMenuContext(data.payload || {})
        }
        return
    }

    if (data.action === 'apexEconomyUpdate') {
        if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
            apexNewEscFrame.contentWindow.postMessage({ type: 'apex-economy-summary', economy: data.economy || {} }, '*')
        }
        return
    }

    if (data.action === 'loadApexRaceTracks') {
        if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
            apexNewEscFrame.contentWindow.postMessage({
                type: 'apex-race-tracks',
                loading: data.loading === true,
                available: data.available === true,
                tracks: Array.isArray(data.tracks) ? data.tracks : []
            }, '*')
        }
        return
    }

    if (data.action === 'loadApexMyTracks') {
        if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
            apexNewEscFrame.contentWindow.postMessage({
                type: 'apex-my-tracks',
                tracks: Array.isArray(data.tracks) ? data.tracks : []
            }, '*')
        }
        return
    }

    if (data.action === 'openApexCreatorPage') {
        if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
            apexNewEscFrame.contentWindow.postMessage({ type: 'apex-open-my-tracks' }, '*')
        }
        return
    }

    if (data.action === 'openApexGarageCatalog') {
        if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
            apexNewEscFrame.contentWindow.postMessage({ type: 'apex-garage-open' }, '*')
            if (lastApexGarageCatalogPayload) {
                const delivery = ++apexGarageCatalogDelivery
                setTimeout(() => forwardApexGarageCatalog(lastApexGarageCatalogPayload, delivery), 80)
            }
        }
        return
    }

    if (data.action === 'showApexGaragePurchaseConfirm') {
        if (!apexGaragePurchaseModal) return
        apexGaragePurchaseKind = data.kind === 'upgrade' ? 'upgrade' : 'purchase'
        apexGaragePurchaseLocationId = Number(data.locationId) || null
        apexGaragePurchaseCapacity = Number(data.capacity) || null
        apexGaragePurchaseOpen = apexGaragePurchaseKind === 'upgrade'
            ? apexGaragePurchaseCapacity !== null
            : apexGaragePurchaseLocationId !== null
        const name = document.getElementById('apex-garage-purchase-title')
        const price = document.getElementById('apex-garage-purchase-price')
        const kicker = document.getElementById('apex-garage-purchase-kicker')
        const description = document.getElementById('apex-garage-purchase-description')
        const priceLabel = document.getElementById('apex-garage-purchase-price-label')
        const payment = document.getElementById('apex-garage-purchase-payment')
        const includedTitle = document.getElementById('apex-garage-purchase-included-title')
        const includedDescription = document.getElementById('apex-garage-purchase-included-description')
        if (apexGaragePurchaseKind === 'upgrade') {
            if (kicker) kicker.innerHTML = 'APEX <b>/</b> EVOLUÇÃO DE GARAGEM'
            if (name) name.textContent = 'EXPANSÃO DISPONÍVEL'
            if (description) description.textContent = `Confirme para ampliar sua garagem para ${apexGaragePurchaseCapacity} vagas.`
            if (priceLabel) priceLabel.textContent = 'VALOR DA EXPANSÃO'
            if (payment) payment.textContent = 'Pagamento direto pelo banco'
            if (includedTitle) includedTitle.textContent = `${apexGaragePurchaseCapacity} VAGAS`
            if (includedDescription) includedDescription.textContent = 'Capacidade total da sua garagem'
            if (apexGaragePurchaseConfirm) apexGaragePurchaseConfirm.textContent = 'CONFIRMAR EXPANSÃO'
        } else {
            if (kicker) kicker.innerHTML = 'APEX <b>/</b> AQUISIÇÃO DE GARAGEM'
            if (name) name.textContent = String(data.locationName || 'GARAGEM DISPONÍVEL').toLocaleUpperCase('pt-BR')
            if (description) description.textContent = 'Confirme a compra para registrar esta garagem no seu perfil e liberar suas vagas pessoais.'
            if (priceLabel) priceLabel.textContent = 'VALOR'
            if (payment) payment.textContent = 'Pagamento direto pelo banco'
            if (includedTitle) includedTitle.textContent = `${Number(data.capacity) || 2} VAGAS`
            if (includedDescription) includedDescription.textContent = `Garagem Tier ${Number(data.tier) || 1} · endereço independente`
            if (apexGaragePurchaseConfirm) apexGaragePurchaseConfirm.textContent = 'CONFIRMAR COMPRA'
        }
        if (price) price.textContent = String(data.price || '$25.000')
        apexGaragePurchaseModal.classList.add('is-open')
        apexGaragePurchaseModal.setAttribute('aria-hidden', 'false')
        apexGaragePurchaseCancel?.focus()
        return
    }

    if (data.action === 'hideApexGaragePurchaseConfirm') {
        closeApexGaragePurchase(false)
        return
    }

    if (data.action === 'apexGaragePreviewStatus') {
        if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
            apexNewEscFrame.contentWindow.postMessage({
                type: 'apex-garage-preview-status',
                active: data.active === true,
                model: data.model || '',
                message: data.message || ''
            }, '*')
        }
        return
    }

    if (data.action === 'loadApexGarageCatalog') {
        lastApexGarageCatalogPayload = data.payload || {}
        const delivery = ++apexGarageCatalogDelivery
        ;[0, 120, 350, 800].forEach((delay) => setTimeout(() => forwardApexGarageCatalog(lastApexGarageCatalogPayload, delivery), delay))
        return
    }

    if (data.action === 'setMultiplayerShowcaseVehicle') {
        if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
            apexNewEscFrame.contentWindow.postMessage({
                type: 'apex-multiplayer-vehicle',
                vehicle: data.vehicle || { available: false }
            }, '*')
        }
        return
    }

    if (data.action === 'returnToMultiplayer') {
        if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
            apexNewEscFrame.contentWindow.postMessage({ type: 'apex-multiplayer-picker-return' }, '*')
        }
        return
    }

    if (data.action === 'loadApexTrackRecords') {
        if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
            apexNewEscFrame.contentWindow.postMessage({
                type: 'apex-track-records',
                trackId: data.trackId,
                records: data.records || null
            }, '*')
        }
        return
    }

    if (data.action === 'loadApexAutoHostState') {
        if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
            apexNewEscFrame.contentWindow.postMessage({
                type: 'apex-autohost-state',
                state: data.state || null
            }, '*')
        }
        return
    }

    if (data.action === 'loadApexLobbyRoom') {
        if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
            apexNewEscFrame.contentWindow.postMessage({
                type: 'apex-lobby-room',
                room: data.room || null
            }, '*')
        }
        return
    }

    if (data.action === 'closeApexLobbyRoom') {
        if (apexNewEscFrame && apexNewEscFrame.contentWindow) {
            apexNewEscFrame.contentWindow.postMessage({ type: 'apex-lobby-room-closed' }, '*')
        }
        return
    }

    if (data.action === 'setRadialMenuState') {
        const isVisible = data.visible === true
        setRadialMenuOpenState(isVisible)

        if (isVisible) {
            renderRadialMenuContext(data.payload || {})
        }
        return
    }

    if (data.action === 'setVehicleQuickMenuState') {
        setVehicleQuickMenuState(data.visible === true, data.payload || {})
        return
    }

    if (data.action !== 'updateSpeedometer') {
        return
    }

    const isVisible = data.visible === true
    const speedoType = data.speedometerType || 'apexnui'

    // Gere a visibilidade dos dois velocímetros independentemente
    speedometer.classList.toggle('is-hidden', !isVisible || speedoType !== 'apexnui')
    if (svgSpeedometer) {
        svgSpeedometer.classList.toggle('is-hidden', !isVisible || speedoType !== 'svg')
    }

    if (!isVisible) {
        renderRpm(0)
        renderSvgRpm(0)
        renderAssist(false, false)
        return
    }

    // Se for o velocímetro padrão da base
    if (speedoType === 'apexnui') {
        renderSpeed(data.speed)
        renderGear(data.gear)
        renderUnit(data.unit)
        renderRpm(data.rpm)
        renderAssist(data.abs === true, data.hbk === true)
    } 
    // Velocímetro SVG baseado diretamente nas artes fornecidas em html/images.
    else if (speedoType === 'svg') {
        const currentSpeed = Math.max(0, Math.min(999, Math.floor(Number(data.speed) || 0)))

        if (svgSpeedValue) {
            svgSpeedValue.innerText = currentSpeed
        }

        const unit = String(data.unit || 'KM/H').toUpperCase()
        if (svgSpeedUnit) {
            svgSpeedUnit.innerText = unit.toLowerCase()
        }

        const gearElement = document.getElementById('svg-gear-value')
        if (gearElement) {
            gearElement.innerText = String(data.gear || 'N').slice(0, 1)
        }

        renderSvgRpm(data.rpm)
    }
});
