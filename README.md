# Monster Battle CCG — Offline Single-Player Android Build

A fully offline, single-player version of the English Card Battle game — originally an online-only Cocos2d-x Android title. This build runs entirely on-device with no Internet connection required, and the home **Play** button opens **The Shadow Road** — a handcrafted 4-act campaign fought on the native battle engine.

## What This Does

- **Decrypts** the game's XXTEA-encrypted Lua source code
- **Replaces** the online TCP transport with an in-process Lua server (`offline_server.lua`)
- **Adds** an AI battle engine (`offline_battle.lua`) that emits the same `cmd_battle` commands the client already animates
- **Adds** the Shadow Road campaign as a native feature: map, commander-HP duels, scripted boss powers, rewards, and progression — served by `campaign_service.lua`, replacing the stock PvE mission list as the Play destination
- **Bypasses** all HTTP authentication, hot-update checks, and third-party SDK calls
- **Patches** the Android manifest for modern devices (targetSdk 33, exported=true)
- **Patches** Java-level SDK calls in smali to prevent crashes on Android 7+
- **Adds** a splash/loading screen for immediate visual feedback

> The earlier HTML prototype (web campaign + JS battle engine + PWA shell) has been **scrapped** — the HTML battle was a poor parallel of the native mechanics. There is no browser version; the Android app is the client. `index.html` is now a simple landing page that points at the APK.

## Quick Start

### Install on Android

1. Uninstall the original game (different signing key required)
2. Install `English_offline.apk` (repo root — the output of `scripts/build_and_verify.py`)
3. Launch — the game starts as a guest, fully offline

> ⚠️ The checked-in APK may predate the latest fixes: rebuild with
> `scripts/build_and_verify.py` (requires Java 17) and install the
> `English_offline.apk` it writes to the repo root.

## The Shadow Road campaign (native)

The campaign is defined **once** in `content/campaign_data.json` and generated
into `src/manager/campaign_data_generated.lua` by
`scripts/refresh_campaign_data.py` (edit the JSON, re-run the generator — never
hand-edit the copy).

- **4 acts, 19 encounters**: Whispering Woods (nature), Sunken Caverns (chaos),
  Emberpeak (war) and Shadowspire (balance), each ending in a boss, plus a
  final boss — the Shadow Sovereign.
- **Commander-HP duels**: every battle is fought on the native engine with
  commander vitality (`node.hp` is the enemy commander's HP; your vitality
  grows with bosses slain). Unblocked creatures strike the commander, and a
  killing blow's **overkill damage carries through** to the commander.
- **Elites and bosses have scripted powers**: Muster, Plunder, Bloodlust,
  Warding, Overgrowth, Hungering Dark, Molten Core (with an ENRAGE phase) and
  Umbral Toll (with an ECLIPSE phase).
- **Gathering Power**: every boss grows +1 ATK on every third turn and strikes
  you directly — walls can't save you, so turtling always loses.
- **Progression**: recruit a card after every first victory (3-card draft,
  skip for +EXP), gain +2 max Vitality per boss slain, and your save persists
  in the game save. Cleared nodes can be replayed; the campaign can be reset.

In battle, both commanders' HP is shown in the battle scene (the server pushes
`cmd_battle_hero`; the campaign HUD renders it).

## Rebuild from Source

```bash
# Requires: Python 3.12+, Java 17 (keytool + jarsigner), apktool, androguard
python scripts/build_and_verify.py
```

The script rebuilds `src.mu`, patches the manifest and smali, signs the APK, and runs automated verification checks (Lua syntax, XXTEA round-trip, APK structure, src.mu content, manifest, and a full login → queries → battle → save → re-login cycle). The output lands at `English_offline.apk` in the project root.

## Debug on BlueStacks

If the app shows a blank screen or crashes, pull the logcat to find the exact failure:

```bash
adb logcat -s cocos2d  # Lua print output
adb logcat -s AndroidRuntime  # Java crashes
```

The game also writes startup breadcrumbs to `offline_debug.log` in its writable directory on device.

## Run the balance/static checks

```bash
python3 scripts/analyze_balance.py --markdown > docs/BALANCE_AUDIT.md
python3 tests/static_checks.py   # includes refresh_campaign_data.py --verify
make verify                      # static checks + Lua campaign tests
```

The balance audit is a heuristic design review for obvious CCG pitfalls: rarity-as-raw-power, strict same-cost upgrades, and tutorial/boss cards leaking into random pools.

## Card identity redesign

`scripts/redesign_cards.py` rebuilds the card powers in `csv_data/all_card_config.csv`
around five faction identities (see `docs/FACTION_IDENTITY.md`): War = aggro/tempo,
Fortune = fast/rush, Balance = control/defense, Nature = defense/growth,
Chaos = disruption. It gives every creature a distinct keyword identity, makes
level-ups add keywords instead of just HP, de-duplicates the equipment/armor
faction variants, and keeps rarity as "specialization, not raw stats". It also
regenerates `docs/BALANCE_AUDIT.md`.

```bash
python3 scripts/redesign_cards.py
```

## Run the headless test suites

The tests load the REAL game Lua modules under LuaJIT 2.1 (the same language
family the game runs on) and replay battles frame by frame, including the
tutorial battle's match-panel standby handshake that historically hung on
"loading" forever.

```bash
python3 scripts/setup_test_env.py     # decrypt game Lua from the APK into decrypted/ + csv_plain/
luajit tests/sim_test.lua             # game logic simulation
luajit tests/integration_test.lua     # integration tests
luajit tests/level_w1_test.lua        # native w1 slice: canonical pool → decks, win/loss
luajit tests/campaign_service_test.lua # native campaign service + w1 end-to-end through the server
luajit tests/campaign_battle_test.lua # hero-HP duel end-to-end (w1 skirmish + w5 boss powers)
luajit tests/guide_battle_test.lua    # tutorial battle end-to-end regression (client side)
```

`tests/campaign_battle_test.lua` boots the real offline server and plays
campaign battles with a greedy bot: commander HP sync, face hits, overkill
carry-through, Gathering Power, scripted boss powers, recruit drafts, reset,
and persistence across re-login.

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
│   │   ├── offline_server.lua    # In-process game server (incl. campaign handlers)
│   │   ├── offline_battle.lua    # AI battle engine + campaign hero-HP duel
│   │   ├── offline_battle_model.lua  # Actor/Slot domain model
│   │   ├── campaign_service.lua  # Native Shadow Road service (info/battle/rewards/recruit)
│   │   ├── campaign_data.lua     # Native adapter onto campaign_data_generated.lua
│   │   ├── campaign_data_generated.lua  # GENERATED from content/campaign_data.json
│   │   ├── global.lua            # Scene manager (patched)
│   │   └── data_template.lua     # CSV data loader (patched; exposes flags)
│   ├── logic/
│   │   ├── battle.lua            # Client battle controller (patched: cmd_battle_hero,
│   │   │                         #   refresh_campaign dispatch)
│   │   ├── login.lua             # Login flow (patched)
│   │   └── account/
│   │       └── mu77_account.lua  # HTTP auth bypass
│   ├── modules/
│   │   ├── battle/battle_ui_panel.lua   # Battle scene (patched: commander HP HUD)
│   │   └── world/system/campaign_panel.lua  # Native campaign map + recruit chooser
│   └── scenes/
│       └── login_scene.lua       # Login scene (offline fallback)
├── scripts/                      # Build & verification tools
│   ├── build_and_verify.py       # Unified build + verification (73 checks)
│   ├── rebuild_apk_v2.py         # APK rebuild pipeline
│   ├── setup_test_env.py         # Builds decrypted/ + csv_plain/ test fixtures from the APK
│   ├── refresh_campaign_data.py  # campaign_data.json → campaign_data_generated.lua
│   ├── redesign_cards.py         # Faction-identity card redesign (CSV + docs)
│   ├── analyze_balance.py        # Balance audit
│   └── xxtea_decrypt.py          # XXTEA encryption/decryption
├── tests/                        # Headless test suites
│   ├── sim_test.lua              # game logic simulation
│   ├── integration_test.lua      # integration tests
│   ├── level_w1_test.lua         # Native w1 slice (canonical pool → decks, win/loss)
│   ├── campaign_service_test.lua # Native campaign service + w1 end-to-end
│   ├── campaign_battle_test.lua  # Hero-HP campaign duels end-to-end (w1 + w5)
│   ├── campaign_test.lua         # Canonical campaign data checks
│   ├── campaign_balance_diag.lua # Node HP / deck-size sanity
│   ├── guide_battle_test.lua     # Tutorial battle client-side end-to-end regression
│   ├── campaign_data_test.py     # Canonical JSON vs generated module (python)
│   └── static_checks.py          # Fast repo-wide checks (no LuaJIT needed)
├── csv_data/                     # Game configuration (plain CSV)
├── content/campaign_data.json    # Canonical Shadow Road campaign (single source)
├── English_offline.apk           # Final installable APK (~55 MB) — install THIS one
├── index.html                    # Landing page only (points at the APK)
└── .gitignore
```

## Verification

The `build_and_verify.py` script runs these checks automatically on every build:

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
