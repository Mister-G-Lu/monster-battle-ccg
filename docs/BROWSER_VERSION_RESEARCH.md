# Serving the game in a browser — research + feasibility

**Question:** Can we serve the APK directly in the browser, like the iOS apps that
have an identical web version?

**Short answer:** You cannot make a browser *natively run* an `.apk`. An APK is
compiled Android (Dalvik/ART bytecode + native `.so` libraries) that needs the
Android OS runtime, which browsers do not have. Every "run an APK in the browser"
product does it one of two ways below. The apps that appear to be "the same app,
in a browser" are almost always a **separate web build compiled from a shared
codebase** — not the mobile binary running in a tab.

---

## Option A — Stream a real/emulated Android device to the browser

The device runs Android in the cloud; the browser shows a video stream and sends
back taps. The APK runs **unmodified**, so it is genuinely the same app.

- **Appetize.io** — upload the APK, get an embeddable `<iframe>` that boots the
  app in a cloud emulator. Closest thing to "native app with an identical web
  version." Free ~100 min/mo, paid from ~$59/mo.
- **now.gg / BlueStacks X** — cloud-streams Android to any browser tab; games.
- **ApkOnline, MyAndroid.org, Genymotion Cloud, BrowserStack** — same idea,
  aimed at QA/quick testing.

**Trade-offs:** per-minute/per-seat cost, needs a good connection (it's a video
stream), latency isn't native, doesn't scale cheaply to many public players.
Great for a **"try it in browser" demo button**; poor as a main channel.

**Dead ends:** Chrome-extension runtimes that ran APKs *locally* in the browser
(**ARChon**, **ARC Welder**) are dead — they relied on NaCl + Chrome Apps, both
removed from modern Chrome. No working local in-browser APK runtime exists today.

## Option B — Ship a real web build from a shared codebase (recommended)

What "identical iOS + web" apps actually are (Gmail, Figma, etc.): a real
HTML/JS/WebGL build compiled from the same source as the mobile app — Flutter →
Flutter Web, React Native + react-native-web, or a Capacitor/Ionic PWA where the
web app is the source of truth and the mobile app is a WebView of it.

---

## Why Option B is uniquely feasible for THIS game

This game is **Cocos2d-x + XXTEA-encrypted Lua**, not a Java/Kotlin app, and the
codebase is already cleanly layered:

- **Pure game logic, zero engine calls** (already unit-tested headlessly):
  `offline_battle.lua` (battle engine), `campaign_service.lua`,
  `offline_battle_model.lua`, `network.lua`, `data_template.lua`,
  `campaign_data*.lua`, `battle.lua`, `guide.lua`, `match_panel.lua`.
- **Cocos-coupled (presentation only):** `campaign_panel.lua`, `main.lua`,
  `login_scene.lua`, `battle_ui_panel.lua`, `home_panel.lua`.

The scrapped HTML prototype failed because it **reimplemented** mechanics in JS
("a poor parallel of the native mechanics"). The correct approach reuses the
**actual Lua** as the single source of truth so the browser rules are byte-for-byte
identical to the APK.

### Proven feasibility spike (see `web-poc/`)

Using **Wasmoon** (Lua 5.4 compiled to WebAssembly), the real decrypted Lua tree
was mounted into the WASM filesystem with the same platform stubs the headless
tests use, and the engine booted successfully:

```
RESULT nodes=19
RESULT w1_exists=true
RESULT final_boss=true
RESULT cards_loaded=1595
OK engine booted in WASM
```

Because this runs in Node's WASM, it runs in a browser's WASM. The unmodified
engine + all 1,595 cards + the 19-node campaign load and execute.

Reproduce:

```bash
python3 scripts/setup_test_env.py         # produces decrypted/ + csv_plain/
cd web-poc && npm install wasmoon
node prove_engine.mjs
```

---

## Recommended architecture for the real web version

1. **Rules core = the existing Lua**, run in the browser via Wasmoon (WASM).
   Same source of truth as the APK; no mechanics reimplementation.
2. **Platform shim in JS** replacing the Cocos/device stubs: file loading
   (fetch the Lua + CSVs), `cc.UserDefault` → `localStorage`, timers, RNG seed.
3. **New presentation layer** in HTML5 Canvas / WebGL (or a Cocos Creator web
   target if art/animation reuse is wanted). This is the only part that is
   genuinely rewritten, and it talks to the engine through the same
   `cmd_battle` command stream the native client already animates.
4. **Assets**: extract sprites/atlases from the APK and serve them statically.
5. **Ship** as a static site + PWA (installable, offline-capable), matching the
   existing offline-first design.

### Effort tiers

- **Quick demo (days):** Appetize.io embed of `English_offline.apk` on a landing
  page. Zero code changes; costs per-minute.
- **Real web version (weeks):** the Wasmoon architecture above — headless engine
  parity first (reuse the existing test suite as the web parity harness), then
  build the Canvas UI screen by screen (battle → campaign map → home).
