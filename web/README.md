# Monster Battle — browser build

A real, playable browser version of the game that runs the **actual Lua engine**
(`offline_server` / `offline_battle` / `campaign_service`) inside WebAssembly via
[wasmoon](https://github.com/ceifa/wasmoon). The rules are the *same source of
truth* as the Android APK — nothing is reimplemented in JS. Only the
presentation layer (campaign map + battle screen) is new (HTML/DOM).

```
┌─────────────────────────────────────────────┐
│  UI  (src/ui.js)         HTML/DOM screens     │
├─────────────────────────────────────────────┤
│  Bridge (lua/web_bridge.lua)  clean snapshots │
│         + player actions -> engine handlers   │
├─────────────────────────────────────────────┤
│  REAL engine (decrypted/*.lua) in WASM        │
│  offline_server · offline_battle · campaign_* │
├─────────────────────────────────────────────┤
│  Platform shim (src/engine.js PLATFORM_STUBS) │
│  cc/ccui/aandm/socket · UserDefault→localStg  │
└─────────────────────────────────────────────┘
```

## Run it

```bash
cd web
npm install
npm run dev        # prepares assets, then starts Vite on 0.0.0.0:5173
```

`npm run dev` first runs `scripts/prepare_web.py`, which:
1. runs `../scripts/setup_test_env.py` if needed (decrypts the APK's Lua +
   makes plain CSVs), then
2. copies the decrypted Lua tree + CSVs + `lua/web_bridge.lua` into `public/`
   and writes `public/game-manifest.json`.

Those copied assets are gitignored (generated from the APK, like the existing
`decrypted/` / `csv_plain/` test fixtures).

## Build

```bash
npm run build      # static site in web/dist/
npm run preview
```

## What works today

- **Campaign map** — all 4 acts / 19 nodes from `campaign_data`, with real
  progression (cleared / playable / locked), commander vitality, win/loss/boss
  counts. Progress persists to `localStorage`.
- **Battle** — start any playable node; it runs a real commander-HP duel on the
  native engine. Deploy monsters / equip / consume from hand, sacrifice for
  crystals, end turn to resolve combat (enemy AI + combat all run in the Lua
  engine). Win/lose is decided by the engine.

## Next steps

- Recruit-draft chooser UI after a first clear (bridge methods
  `recruit_offers` / `recruit` / `skip_recruit` already exist; the battle-over
  screen currently auto-skips).
- Sprite/atlas art extracted from the APK instead of text cards.
- Scripted boss-power callouts (the engine already emits them on `cmd_battle`).
- PWA manifest + service worker for offline/installable parity with the app.
