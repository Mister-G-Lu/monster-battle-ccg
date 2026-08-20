# Engine strategy — Android-only (decision, supersedes the web shell)

Status: **decided.** The HTML/web shell has been **removed**; the game ships
as the Android app alone.

## History

| Phase | Route | Outcome |
|---|---|---|
| Prototype | HTML campaign ("The Shadow Road") + JS battle engine | Proved the campaign content, but the HTML battle was a parallel implementation of the native mechanics |
| Interim | Route (3): thin JS port + canonical data + APK art | Kept one canonical campaign (`content/campaign_data.json`) across both hosts |
| **Now** | **Android only** | The campaign (map, duel engine, powers, rewards) is fully native; the web shell and its JS battle engine are scrapped |

## Why Android-only

1. The user-facing client is the **Android app** (Cocos2d-x / LuaJIT). Its
   battle scene is the polished interface; the HTML battle was "terrible"
   and duplicated the Lua mechanics.
2. The Shadow Road campaign is now served by the app's own offline service
   (`campaign_service.lua`) and fought on the native battle engine
   (`offline_battle.lua` hero-HP duel + scripted powers) — no web port to
   keep in sync.
3. Routes (1) LuaJIT→WASM and (2) WebView/Capacitor are **no-go**: there is
   no HTML host left to justify them.

## Current architecture

```
content/campaign_data.json            ← canonical campaign (data only)
        │  scripts/refresh_campaign_data.py
        └─► src/manager/campaign_data_generated.lua   (native Lua tables)

csv_data/all_card_config.csv          ← canonical cards/items
        │  scripts/redesign_cards.py / data_template.lua
        └─► src/manager/data_template.lua             (native card config)

English_offline.apk                   ← the client (Android)
src/manager/offline_battle.lua        ← canonical battle mechanics (+ campaign duel)
src/manager/campaign_service.lua      ← canonical campaign service
src/modules/world/system/campaign_panel.lua  ← native campaign map UI
```

One campaign, one engine, one client.
