# Ícones de entrada globais (teclado / PlayStation / Xbox)

Padrão de **todas** as interfaces do Apex: nunca desenhe tecla ou botão à mão.
Use sempre `data-input` / `data-key` / `data-pad` e o módulo troca sozinho entre
teclado, PlayStation e Xbox.

Pacote de ícones: **Kenney – Input Prompts** (teclado e mouse, PlayStation Series, Xbox Series;
distribuído como CC0/domínio público — confira a licença na página do pacote:
https://kenney-assets.itch.io/input-prompts). SVGs em `html/input-icons/{kb,ps,xbox}`.

## Como usar numa tela nova

No `<head>` e no fim do `<body>` da página (HTML da NUI ou iframe):

```html
<link rel="stylesheet" href="input-glyphs.css">
...
<script src="input-glyphs.js"></script>
```

No HTML:

```html
<span data-input="menu">ESC</span>                      <!-- ação pronta -->
<span data-key="z" data-pad="dpad-left">Z</span>        <!-- tecla + botão do controle -->
<span data-input="close" data-key="z">Z</span>          <!-- ação pronta, trocando só a tecla -->
```

O texto dentro do elemento é só o *fallback* (aparece se o ícone não existir).
Elementos criados depois por JavaScript também são atualizados automaticamente.
Em template JS: `ApexInput.html('confirm')`.

Tamanho: defina `--input-icon-size` no elemento ou no container (use **px**, não em/rem do pai):

```css
.minha-dica { --input-icon-size: 34px; }
```

Páginas dentro de iframe (como o menu ESC) pedem o modo ao documento pai sozinhas.

Para travar uma página no teclado (o menu ESC está assim enquanto a navegação por controle não existe), use
`<body data-input-force="keyboard">`; remova o atributo quando o controle passar a funcionar nela.

## Ações prontas (`data-input`)

| Ação | Teclado | Controle (genérico) | PlayStation / Xbox |
|---|---|---|---|
| `menu` | ESC | options | Options / Menu |
| `shortcuts` | Z | dpad-left | seta esquerda |
| `confirm` | Enter | face-bottom | ✕ / A |
| `back`, `close` | ESC | face-right | ○ / B |
| `nav-up/down/left/right` | setas | dpad-* | seta correspondente |
| `nav-horizontal`, `nav-vertical` | setas ←→ / ↑↓ | dpad-horizontal / vertical | |
| `tab-prev`, `tab-next` | Q / E | l1 / r1 | L1,R1 / LB,RB |

Botões genéricos do controle (`data-pad`): `face-bottom`, `face-right`, `face-left`, `face-top`,
`options`, `share`, `l1`, `r1`, `l2`, `r2`, `l3`, `r3`, `stick-l`, `stick-r`, `dpad`,
`dpad-up`, `dpad-down`, `dpad-left`, `dpad-right`, `dpad-horizontal`, `dpad-vertical`.

Teclas (`data-key`): qualquer arquivo `keyboard_<nome>.svg` de `html/input-icons/kb`
(`a`–`z`, `0`–`9`, `escape`, `enter`, `space`, `shift`, `ctrl`, `tab`, `f1`–`f12`, `arrow_up`…).
Apelidos aceitos: `esc`, `del`, `left`, `right`, `up`, `down`, `←`, `→`, `↑`, `↓`.

## Adicionar uma ação nova

Em `html/input-glyphs.js`, no objeto `ACTIONS`:

```js
'abrir-mapa': { key: 'm', pad: 'share' },
```

Para um botão do controle que ainda não existe, acrescente em `PAD` o nome dos arquivos
(PlayStation e Xbox).

## Lado Lua (`client.lua`)

O `client.lua` envia `{ action = 'setInputMode', mode = 'keyboard' | 'gamepad', padStyle = 'playstation' | 'xbox' }`.

- Modo automático (teclado/controle). Forçar: `/apexnui_inputmode auto | teclado | controle`.
- Estilo do controle (padrão PlayStation, fica salvo): `/apexnui_padstyle playstation | xbox`.
- Scripts Lua que precisam saber o modo atual podem ler `hintState.inputMode` dentro do `client.lua`.

## Observações

- **Tudo em preto e branco** (padrão Apex): ícones coloridos do pacote (`button_color_*`, setas do teclado com vermelho,
  D-pad com realce vermelho) foram removidos de propósito. Não adicione variantes coloridas.
  Teclas compostas usam `+` (ex.: `data-key="arrow_left+arrow_right"`).

- Foram incluídos só os ícones sem contorno, mais as setas direcionais `_outline` (cruz preta e branca, com a direção
  acionada em branco cheio). Se precisar de outro `_outline`, copie do pacote original para a mesma pasta.
- Novos ícones precisam estar listados no `fxmanifest.lua` (`html/input-icons/**/*.svg` já cobre a pasta).
