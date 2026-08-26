# Gerbip Tide — archived

The stock game's daily PvE mode, **"Gerbip Tide"** (`gerbil_tide_title`; the
code calls it *gerbil tide*, `play_id = "1001"`), is parked here. It is **not
deleted** and it is **not shipped** — it is out of the build but one restore
away.

## Why it is archived

This build has exactly one destination: **The Shadow Road** campaign
(`content/campaign_data.json`, served by `src/manager/campaign_service.lua`).
Gerbip Tide was the online game's daily grind: a rotating mission list with a
server-side reset timer, per-difficulty mirrored *system decks* pulled from
`all_pve_play_config.csv`, and a run counter capped by `PVE_INFO.limit_count`.
Offline none of that has a server behind it, and leaving the entry on the PvE
screen meant a second door that led somewhere the campaign was supposed to own.

So the mode is out of the APK and out of the browser build, and the home bar's
**Battle** button opens the campaign map directly instead.

## What is in this directory

| File | What it was |
| --- | --- |
| `modules/pve/pve_gerbil_tide_panel.lua` | The mode itself: difficulty picker, run counter, mirrored-deck preview, "start" into `req_pve_battle_start`. |
| `modules/pve/pve_cardgroup_panel.lua` | The mirrored system-deck viewer. Required **only** by the panel above, so it went with it. |
| `pve_panel.lua.stock` | The stock `modules/world/system/pve_panel.lua`, kept for reference — the patched live copy is `src/modules/world/system/pve_panel.lua`. |
| `pve.lua.stock` | The stock `logic/pve.lua`, kept for reference — the patched live copy is `src/logic/pve.lua`. |

The two files under `modules/pve/` are byte-identical to the APK originals
(Chinese comments included), so restoring them is a straight copy.

## What changed in the live tree

* `scripts/archived_sources.py` — new. Lists the archived module paths; every
  build pipeline consults it:
  * `scripts/rebuild_offline_apk.py` drops them from `assets/src.mu`
  * `scripts/setup_test_env.py` leaves them out of `decrypted/`
  * `web/scripts/prepare_web.py` leaves them out of the browser manifest
* `src/modules/world/system/pve_panel.lua` — new (was stock). The Gerbip Tide
  mission entry, its `show_gerbil_tide_panel` handler and its progress line are
  gone; the exam entry is untouched.
* `src/logic/pve.lua` — new (was stock). `Query()` no longer dispatches
  `show_gerbil_tide_panel`; it is a logged no-op.

Left alone on purpose:

* `csv_data/all_pve_play_config.csv` and the `gerbil_tide_title` row in
  `csv_data/client_lang_en-US.csv` (currently repurposed to
  `— Whispering Woods —`) are now unreferenced but harmless. They stay so the
  CSVs keep matching the stock data set.
* `modules/pve/pve_card_detail_panel.lua` stays live —
  `modules/pvp/periphery_match_panel.lua` uses it.
* `modules/common/pve_material_item.lua` stays live —
  `modules/battle/battle_result_reward_panel.lua` uses it.
* `logic/pve.lua` itself stays: `logic/battle.lua` and
  `modules/battle/match_panel.lua` require it, and it still owns the exam
  (`QueryExam`) flow.

## How to restore

1. Delete the `GERBIP_TIDE` entries from `scripts/archived_sources.py`
   (or empty the list).
2. Copy the panels back into the shipped tree:
   ```bash
   cp archive/gerbip_tide/modules/pve/pve_gerbil_tide_panel.lua src/modules/pve/
   cp archive/gerbip_tide/modules/pve/pve_cardgroup_panel.lua   src/modules/pve/
   ```
3. Revert `src/modules/world/system/pve_panel.lua` and `src/logic/pve.lua` to
   the `.stock` copies here (or re-add just the mission entry and the
   `show_gerbil_tide_panel` dispatch).
4. Rebuild: `python3 scripts/rebuild_offline_apk.py`, then
   `python3 scripts/setup_test_env.py`.

`tests/static_checks.py` fails if an archived module is required by live code,
ships in `web/dist/`, or turns up in `src/` — so a half-finished restore will
not pass CI.
