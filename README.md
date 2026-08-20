# Monster Battle CCG - Offline Single-Player Build

A fully offline, single-player version of the English Card Battle game (originally an online-only Cocos2d-x Android game). The game runs entirely on-device with no Internet connection required.

## What This Does

- **Cracks** the game's XXTEA encryption to access Lua source code
- **Replaces** the online server transport with an in-process Lua "server" (`offline_server.lua`)
- **Adds** an AI battle engine (`offline_battle.lua`) that emits the same `cmd_battle` commands the client already animates
- **Bypasses** all HTTP auth, hot-update, and third-party SDK calls for offline operation
- **Fixes** the Android manifest for modern Android (targetSdk=33, exported=true)
- **Adds** a splash/loading screen for immediate visual feedback

## Quick Start

### Install on Android
1. Uninstall the original game (different signing key)
2. Install `build/English_offline.apk`
3. Launch — the game starts as a guest, fully offline

### Play Web Prototype
Open `build/web/game.html` in any browser to test the card battle system with real game data (1,580 cards from the original CSVs).

### Rebuild the APK
The historical `build_and_verify.py` pipeline requires its original Windows
apktool workspace. For a portable rebuild from an existing working APK, use:

```bash
# Requires Python 3 and a Java JDK (keytool + jarsigner)
python scripts/rebuild_from_apk.py English.apk build/English_offline.apk
```

The output is signed with a local offline key, so uninstall an older/original
installation before installing it. The patcher encrypts every Lua file under
`src/` and replaces it in `assets/src.mu`.

### Debug a BlueStacks startup failure
The game writes high-level startup breadcrumbs and full Lua tracebacks to
`offline_debug.log` in its Cocos writable directory. It also renders a visible
error panel when Lua reaches its exception handler, rather than silently
returning to BlueStacks. After reproducing the problem with Android Platform
Tools connected to the emulator, collect a shareable report with:

```bash
./scripts/collect_android_logs.sh com.mu77.english
```

This creates `build/android-diagnostics/<timestamp>/` containing full logcat,
a startup-focused filtered log, device properties, package metadata, and the
app log when Android storage permissions permit access. The offline build
never attempts to upload crash reports to the retired original service.

### Language behavior
This is intentionally an English-only offline build. The text loader now
always loads `client_lang_en-US.csv`, regardless of the Android/BlueStacks
locale; this prevents a Chinese-language emulator from selecting Chinese UI
strings. The English CSV has also been audited to remove its remaining
Chinese-visible strings.

## File Structure

```
monster-battle-ccg/
├── src/                          # Patched Lua source files
│   ├── main.lua                  # Entry point (splash screen, offline bypass)
│   ├── manager/
│   │   ├── network.lua           # TCP→offline intercept layer
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
│   ├── English_offline.apk       # Final installable APK (55 MB)
│   └── web/
│       └── game.html             # Browser-playable card battle prototype
└── .gitignore
```

## Verification (73 checks)

The `build_and_verify.py` script automatically checks:

| Category | Checks | What It Verifies |
|----------|--------|------------------|
| Lua syntax | 9 | All patched files compile |
| XXTEA round-trip | 9 | Encrypt→decrypt produces identical output |
| APK structure | 8 | No duplicates, correct META-INF, ZIP integrity, DEX/ELF format |
| src.mu content | 11 | All patched files decrypt correctly, markers present |
| Android manifest | 14 | targetSdk=33, minSdk=21, exported=true, cert valid, not debuggable |
| Game logic | 29 | Full login→queries→battle→save→re-login cycle |

## Tech Stack

- **Original game**: Cocos2d-x 3.x, LuaJIT, ARM native (libcocos2dlua.so)
- **Offline server**: Pure Lua 5.1 (compatible with LuaJIT)
- **Encryption**: XXTEA with custom key (`10cc4fdee2fcd047`)
- **Build tools**: Python 3.12, apktool 2.9.3, jarsigner (JDK 17), androguard
- **Test framework**: Custom Lua test harness (no external dependencies)

## Credits

Based on the original English Card Battle game by mu77. This is a fan-made offline modification for personal use.
