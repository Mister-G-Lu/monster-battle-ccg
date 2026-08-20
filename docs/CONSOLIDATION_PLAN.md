# Consolidation — one campaign, one engine, one client (Android)

The Shadow Road campaign was prototyped as an HTML app with its own JS battle
engine. That web shell has been **scrapped**; the campaign now lives entirely
in the Android app, served by the app's own offline service and fought on the
native battle engine. This document records the architecture that remains.

## What the user gets

- The home **Play** button opens the native campaign map
  (`src/modules/world/system/campaign_panel.lua`) instead of the stock PvE
  mission list.
- Every node is a **commander-HP duel** on the real battle engine
  (`src/manager/offline_battle.lua` hero mode): face hits on empty lanes,
  overkill carry-through, Gathering Power on bosses, and the eight scripted
  elite/boss powers (Muster, Plunder, Bloodlust, Warding, Overgrowth,
  Hungering Dark, Molten Core, Umbral Toll with ENRAGE/ECLIPSE phase 2).
- First clears grant EXP and a 3-card recruit draft ("collection IS your
  deck"), bosses grant +2 max vitality, progress persists in the game save.
- The client battle scene shows both commanders' HP (`cmd_battle_hero` →
  `update_hero_hp`) for campaign battles.

## Architecture map

```
content/campaign_data.json            ← canonical campaign (regions/nodes/tokens/starter)
        │  scripts/refresh_campaign_data.py
        └─► src/manager/campaign_data_generated.lua

csv_data/all_card_config.csv          ← canonical cards/items
        │  data_template.lua (card_config + flags)
        └─► offline_server (deck building, recruit drafts)

src/manager/campaign_service.lua      ← campaign rules: save, gating, rewards, recruits
src/manager/offline_battle.lua        ← battle engine incl. hero-HP campaign duel
src/manager/offline_server.lua        ← req_campaign_info / battle_start / recruit_* / reset
src/logic/battle.lua                  ← client: cmd_battle_hero + refresh_campaign
src/modules/world/system/campaign_panel.lua  ← native campaign map + recruit chooser
src/modules/battle/battle_ui_panel.lua       ← commander HP HUD (campaign battles)
```

## Rules that stay in force

- **Android mechanics are canonical.** New levels are data edits
  (`content/campaign_data.json`), never engine copies.
- **One canonical fix location** for any shared-mechanic bug.
- No new abstractions without a concrete consumer; no rewriting working
  systems to be prettier.
- The HTML hosts (`index.html`, `build/web/*`, PWA files) and their
  generators/tests are gone; do not resurrect a parallel web engine.
