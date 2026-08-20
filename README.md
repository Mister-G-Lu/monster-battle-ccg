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
2. Install `build/English_offline.apk`
3. Launch — the game starts as a guest, fully offline

### Play the Web Prototype

Open `build/web/game.html` in any browser to try the card battle system with real game data (1,580 cards from the original CSVs). No server required.

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

## Language Behavior

This is an English-only offline build. The text loader always loads `client_lang_en-US.csv` regardless of the device locale, preventing Chinese UI strings from appearing on non-Chinese systems.

## File Structure

```
monster-battle-ccg/
├── src/                          # Patched Lua source files
│   ├── main.lua                  # Entry point (splash screen, offline bypass)
│   ├── manager/
│   │   ├── network.lua           # TCP → offline intercept layer
│   │   ├── offline_server.lua    # In-process game server (1,679 lines)
│   │   ├── offline_battle.lua    # AI battle engine (1,424 lines)
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
│   └── xxtea_decrypt.py          # XXTEA encryption/decryption
├── tests/                        # Headless test suites
│   ├── sim_test.lua              # 29-check game logic simulation
│   └── integration_test.lua      # 106-check integration tests
├── csv_data/                     # Game configuration (plain CSV)
├── build/
│   ├── English_offline.apk       # Final installable APK (~55 MB)
│   └── web/
│       ├── game.html             # Browser-playable card battle prototype
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
