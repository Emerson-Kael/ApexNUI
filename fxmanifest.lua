fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Codex'
description 'Apex NUI - HUD do atalho F4 com minimapa'

dependency 'ox_lib'

shared_scripts {
    '@ox_lib/init.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/input-glyphs.js',
    'html/input-glyphs.css',
    'html/input-icons/**/*.svg',
    'html/esc-menu.html',
    'html/esc-menu.css',
    'html/esc-menu-redesign.css',
    'html/garage-cards.css',
    'html/esc-menu.js',
    'html/garage-images/*',
    'html/esc-menu-images/*.webp',
    'html/discord-assets/*.png',
    'html/images/*.svg'
}

client_scripts {
    'radial-menu/config.lua',
    'client.lua',
    'discord-presence.lua',
    'garage-photo.lua'
}
