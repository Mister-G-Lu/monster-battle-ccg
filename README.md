# Monster Battle CCG — Offline Single-Player Build

A fully offline, single-player version of the English Card Battle game — originally an online-only Cocos2d-x Android title. This build runs entirely on-device with no Internet connection required.

## What This Does

- **Decrypts** the game's XXTEA-encrypted Lua source code
- **Replaces** the online TCP transport with an in-process Lua server (`offline_server.lua`)
- **Adds** an AI battle engine (`offline_battle.lua`) that emits the same `cmd_battle` commands the client already animates
- **Bypasses** all HTTP authentication, hot-update checks, and third-party SDK calls
- **Patches** the Android manifest for modern devices (targetSdk 33, exported=true)
- **Patches** Java-level SDK calls in smali to prevent crashes on Android 7+
- **Adds** a splash/loading screen for immediate visual feedback

## Quick Start

### Install on Android

1. Uninstall the original game (different signing key required)
2. Install `English_offline.apk` (repo root — the output of `scripts/build_and_verify.py`)
3. Launch — the game starts as a guest, fully offline

> ⚠️ The checked-in APKs predate the latest fixes: `build/English_offline.apk`
> contains an earlier loading-screen fix but is still missing the battle
> identity/desync fixes, and the repo-root `English_offline.apk` predates all
> of them. Rebuild with `scripts/build_and_verify.py` (requires Java 17) and
> install the `English_offline.apk` it writes to the repo root.

### Play the Web App

The campaign also ships as an **installable web game** — a clean, full-bleed
game view with no fake Android chrome. The Android app owns the frame (the OS
draws the real status/navigation bars); the page renders only the game: a slim
in-game HUD, the campaign screens, and a compact tab strip.

```bash
make web     # http://localhost:8000/
```

Serve it over HTTP rather than opening the file directly, so the service worker
and the *Add to Home screen* install prompt work (`file://` is not a secure
context). Once installed it launches standalone (`display: standalone`) with no
browser UI, edge-to-edge. Everything runs client-side with real game data
(1,580 cards from the original CSVs) and works fully offline after the first
load.

`build/web/game.html` is a byte-identical mirror of `index.html` and can be
opened the same way. See `docs/WEB_DELIVERY.md` for the delivery options
evaluated (cloud APK streaming, dead Chrome runtimes, engine web exports) and
why the PWA app-shell approach won.

The prototype is a **handcrafted single-player campaign — "The Shadow Road"**:

- **4 acts, 19 encounters**: Whispering Woods (nature), Sunken Caverns (chaos),
  Emberpeak (war) and Shadowspire, each ending in a boss, plus a final boss —
  the Shadow Sovereign.
- **Elites and bosses have scripted powers**: Muster, Plunder, Bloodlust,
  Warding, Overgrowth, Hungering Dark, Molten Core (with an ENRAGE phase) and
  Umbral Toll (with an ECLIPSE phase).
- **Gathering Power**: every boss grows +1 ATK on every third turn and strikes
  you directly — walls can't save you, so turtling always loses.
- **Overkill carry-through**: a killing blow's excess damage hits the enemy
  commander, so trades always progress the game.
- **Progression**: recruit a card after every first victory (tiered rewards),
  gain +2 max Vitality per boss slain, and your save persists in
  `localStorage`. Cleared nodes can be replayed; the campaign can be reset.

Difficulty was tuned with a headless bot (see `tests/campaign_sim.js` below):
skirmishes sit at ~85–100% first-try for a greedy bot, elites ~85%, bosses
~30–60% — real players retry freely and pick rewards, so the campaign
completes in a few boss-attempt cycles.

### Art

The prototype now renders the original game's own artwork (extracted from
`English_offline.apk` into `build/web/assets/` by `scripts/extract_web_art.py`),
so cards, the battlefield and the campaign map look like the Android game
instead of plain text. See `docs/ART_INTEGRATION.md` for how it works and the
alternatives evaluated (generated art, free asset sites).

The web page frames it as a clean game view — no fake Android chrome; the real
app (or the device's own bars) owns the frame. See `docs/WEB_DELIVERY.md`.

### Consolidation (Android engine + Web campaign)

The Shadow Road campaign is now defined **once** in
`content/campaign_data.json`, and `scripts/refresh_campaign_data.py` regenerates
every platform's copy from it: the `CAMPAIGN_DATA` blob in `index.html` /
`build/web/game.html`, the `build/web/campaign_data.json` mirror, and the native
`src/manager/campaign_data_generated.lua`. Edit the JSON, re-run the generator —
never hand-edit the copies. See `docs/CONSOLIDATION_PLAN.md` for the
decision and the architecture map.

The campaign is also integrated into the **Android app's own service**: the
in-process game server (`offline_server.lua`) serves the Shadow Road through
`src/manager/campaign_service.lua` — campaign info, battle start (enemy deck
from the canonical node pool, run on the real `offline_battle` engine),
first-clear rewards/recruit, boss vitality, reset — with progress persisted in
the game save. `tests/campaign_service_test.lua` and `tests/level_w1_test.lua`
cover the w1 slice end-to-end. See `docs/WEB_DELIVERY.md`.

### Rebuild from Source

```bash
# Requires: Python 3.12+, Java 17 (keytool + jarsigner), apktool, androguard
python scripts/build_and_verify.py
```

The script rebuilds `src.mu`, patches the manifest and smali, signs the APK, and runs 73 automated verification checks. The output lands at `English_offline.apk` in the project root.

### Debug on BlueStacks

If the app shows a blank screen or crashes, pull the logcat to find the exact failure:

```bash
adb logcat -s cocos2d  # Lua print output
adb logcat -s AndroidRuntime  # Java crashes
```

The game also writes startup breadcrumbs to `offline_debug.log` in its writable directory on device.

### Run the balance/static checks

```bash
python3 scripts/analyze_balance.py --markdown > docs/BALANCE_AUDIT.md
python3 tests/static_checks.py   # includes refresh_campaign_data.py --verify + the PWA checks
make verify                      # static checks + app shell test + Lua campaign tests
```

The balance audit is a heuristic design review for obvious CCG pitfalls: rarity-as-raw-power, strict same-cost upgrades, and tutorial/boss cards leaking into random pools.

### Card identity redesign

`scripts/redesign_cards.py` rebuilds the card powers in `csv_data/all_card_config.csv`
around five faction identities (see `docs/FACTION_IDENTITY.md`): War = aggro/tempo,
Fortune = fast/rush, Balance = control/defense, Nature = defense/growth,
Chaos = disruption. It gives every creature a distinct keyword identity, makes
level-ups add keywords instead of just HP, de-duplicates the equipment/armor
faction variants, and keeps rarity as "specialization, not raw stats". It also
regenerates `build/web/game_data.json`, the `GAME_DATA` blob in
`build/web/game.html`, and `docs/BALANCE_AUDIT.md`.

```bash
python3 scripts/redesign_cards.py
```

### Run the headless test suites

The tests load the REAL game Lua modules under LuaJIT 2.1 (the same language
family the game runs on) and replay battles frame by frame, including the
tutorial battle's match-panel standby handshake that historically hung on
"loading" forever.

```bash
python3 scripts/setup_test_env.py     # decrypt game Lua from the APK into decrypted/ + csv_plain/
luajit tests/sim_test.lua             # 29-check game logic simulation
luajit tests/integration_test.lua     # 106-check integration tests
luajit tests/level_w1_test.lua        # native w1 slice: canonical pool → decks, win/loss
luajit tests/campaign_service_test.lua # native campaign service + w1 end-to-end through the server
luajit tests/guide_battle_test.lua    # tutorial battle end-to-end regression (client side)
node tests/campaign_sim.js 80         # web campaign: engine regression + difficulty curve report
node tests/app_shell_test.js          # game-view HUD/tabs + PWA manifest/SW/icons
```

`tests/campaign_sim.js` loads the real page script with a stubbed DOM, plays
the full campaign dozens of times with a greedy bot (deploy best affordable,
attack with everything), and asserts the difficulty curve: early nodes winnable,
bosses non-trivial but beatable with retries, every scripted power firing,
reward drafts and `localStorage` saves round-tripping.

`decrypted/` and `csv_plain/` are gitignored fixtures regenerated by
`setup_test_env.py` — never commit them.

## Language Behavior

This is an English-only offline build. The text loader always loads `client_lang_en-US.csv` regardless of the device locale, preventing Chinese UI strings from appearing on non-Chinese systems.

## File Structure

```
monster-battle-ccg/
├── src/                          # Patched Lua source files
│   ├── main.lua                  # Entry point (splash screen, offline bypass)
│   ├── manager/
│   │   ├── network.lua           # TCP → offline intercept layer
│   │   ├── offline_server.lua    # In-process game server (~1,700 lines)
│   │   ├── offline_battle.lua    # AI battle engine (~1,500 lines)
│   │   ├── campaign_service.lua  # Native Shadow Road service (info/battle/rewards/recruit)
│   │   ├── campaign_data.lua     # Native adapter onto campaign_data_generated.lua
│   │   ├── global.lua            # Scene manager (patched)
│   │   └── data_template.lua     # CSV data loader (patched)
│   ├── logic/
│   │   ├── login.lua             # Login flow (patched)
│   │   └── account/
│   │       └── mu77_account.lua  # HTTP auth bypass
│   └── scenes/
│       └── login_scene.lua       # Login scene (offline fallback)
├── scripts/                      # Build & verification tools
│   ├── build_and_verify.py       # Unified build + 73-check verification
│   ├── rebuild_apk_v2.py         # APK rebuild pipeline
│   ├── setup_test_env.py         # Builds decrypted/ + csv_plain/ test fixtures from the APK
│   └── xxtea_decrypt.py          # XXTEA encryption/decryption
├── tests/                        # Headless test suites
│   ├── sim_test.lua              # 29-check game logic simulation
│   ├── integration_test.lua      # 106-check integration tests
│   ├── level_w1_test.lua         # Native w1 slice (canonical pool → decks, win/loss)
│   ├── campaign_service_test.lua # Native campaign service + w1 end-to-end
│   └── guide_battle_test.lua     # Tutorial battle client-side end-to-end regression
├── csv_data/                     # Game configuration (plain CSV)
├── English_offline.apk           # Final installable APK (~55 MB) — install THIS one
├── index.html                    # The web game view (no fake OS chrome; HUD + campaign)
├── manifest.webmanifest          # PWA manifest (installable, standalone display)
├── sw.js                         # Offline service worker
├── build/
│   ├── English_offline.apk       # Earlier build — see Quick Start (rebuild first)
│   └── web/
│       ├── game.html             # Byte-identical mirror of index.html
│       ├── manifest.webmanifest  # The mirror's manifest + service worker
│       ├── sw.js
│       ├── assets/icons/         # Launcher icons, incl. Android maskable/adaptive
│       └── game_data.json        # Card and PvE data for the prototype
└── .gitignore
```

## Verification (73 checks)

The `build_and_verify.py` script runs these automatically on every build:

| Category | Checks | What It Verifies |
|----------|--------|------------------|
| Lua syntax | 9 | All patched files compile without errors |
| XXTEA round-trip | 9 | Encrypt → decrypt produces identical output |
| APK structure | 8 | No duplicates, correct META-INF, ZIP integrity, DEX/ELF format |
| src.mu content | 11 | All patched files decrypt correctly, offline markers present |
| Android manifest | 14 | targetSdk ≥ 30, minSdk ≥ 21, exported=true, cert valid, not debuggable |
| Game logic | 29 | Full login → queries → battle → save → re-login cycle |

## Tech Stack

- **Original game**: Cocos2d-x 3.x, LuaJIT, ARM native (`libcocos2dlua.so`)
- **Offline server**: Pure Lua 5.1 (compatible with LuaJIT)
- **Encryption**: XXTEA with key `10cc4fdee2fcd047`
- **Build tools**: Python 3.12, apktool 2.9.3, jarsigner (JDK 17), androguard
- **Test framework**: Custom Lua test harness (no external dependencies)

## Credits

Based on the original English Card Battle game by mu77. This is a fan-made offline modification for personal use.
