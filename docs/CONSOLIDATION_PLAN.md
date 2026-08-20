# Android + Web Consolidation — Decision & Architecture Map

**Decision: ACCEPT the VP's directive** — with a deliberately *minimal, incremental*
interpretation, because the VP's own points 10, 12, and 13 warn against a giant
rewrite. This document records the reasoning, the architecture map, and the
first slice that was implemented.

> Guiding rule (VP §18): **"Are we connecting existing mechanics to new content,
> or accidentally creating another implementation of an existing mechanic?"**
> If the answer is "another implementation", stop.

---

## 1. Verdict on the plan

**Accept**, on these grounds:

1. **The direction is correct.** The web prototype's *value* is the Shadow Road
   campaign *content* (4 acts, 19 nodes, bosses, powers, rewards, progression).
   The Android/Lua engine is the *canonical mechanics*. Those two truths should
   converge on one game, not two.
2. **It forbids the exact failure mode already happening.** The Android engine
   (PR #9, `src/manager/campaign_data.lua`) has **hand-copied** the same Shadow
   Road campaign the web prototype embeds in JS. That is precisely the
   "AndroidCampaign / WebCampaign" duplication the VP's §16 bans. The plan gives
   us the mandate to remove that duplication — the first slice below does.
3. **"Reject" is wrong** because the plan correctly rejects the two tempting
   mistakes (dumbing Android into HTML; keeping a parallel web engine).
   **"Accept wholesale" is dangerous** because it implies an open-ended rewrite
   of a working Cocos2d-x/Lua engine.

So: accept the *principles*, implement *incrementally*, keep Android mechanics
intact, and make the campaign the first truly shared asset.

## 2. Constraints & realities that shape how much we implement now

These come from inspecting the repo, and they change the scope:

- **The engine is a Cocos2d-x 3.x / LuaJIT binary** (`libcocos2dlua.so`). It does
  not run in a browser. A shared runtime (VP §8) — LuaJIT→WASM, Defold, Godot,
  Capacitor/WebView wrapper — is a large, risky project and is **out of scope
  for this slice**.
- **A native Shadow Road port is already in flight** as PR #9
  (`src/manager/campaign_data.lua`, `campaign_panel.lua`, `campaign_test.lua`).
  Consolidation must **coordinate with it**, not duplicate it.
- **The web engine has already been upgraded** by PR #11 (merged): items/equip/
  armor/consume cards, the full keyword set, strategic AI — a port of the
  Android battle logic into JS. The web side is no longer a "simplified" engine.
- **`main` currently has two diverging web copies** (`index.html` at repo root
  and `build/web/game.html`), because PR #11 only touched `game.html`. One
  canonical campaign source is the first step toward fixing that drift too.

## 3. Architecture map (current state)

```
content/campaign_data.json            ← canonical campaign (NEW — this slice)
        │  scripts/refresh_campaign_data.py
        ├─► index.html                 (web shell: CAMPAIGN_DATA blob)
        ├─► build/web/game.html        (web shell: CAMPAIGN_DATA blob)
        ├─► build/web/campaign_data.json  (mirror)
        └─► src/manager/campaign_data_generated.lua  (native Lua tables)

csv_data/all_card_config.csv           ← canonical cards/items
        │  scripts/redesign_cards.py / refresh_web_data.py
        ├─► build/web/game_data.json
        └─► GAME_DATA blob in both HTML files

English_offline.apk                    ← canonical engine + assets
        │  scripts/extract_web_art.py
        └─► build/web/assets/**        (art reused by the web shell)

src/manager/offline_battle.lua         ← canonical mechanics (Android)
build/web/game.html  (battle JS)       ← port of the same mechanics (web shell)
```

### Subsystem classification (VP §5)

| Subsystem | Where it lives | Class |
|---|---|---|
| Combat / rules / AI / state | `src/manager/offline_battle.lua` (canonical) + JS port in `game.html` | Core logic |
| Cards / items | `csv_data/all_card_config.csv` → `GAME_DATA` | Content/data |
| Campaign levels/powers/rewards | **`content/campaign_data.json` (this slice)** | Content/data |
| Rendering / sprites / effects | APK assets; web uses extracted PNGs | Rendering (per-platform) |
| Input | Lua touch / DOM events | Input (per-platform) |
| Persistence | Android storage / `localStorage` | Persistence (per-platform) |

## 4. What the first slice delivers (implemented)

The single highest-leverage, lowest-risk step toward "one campaign":

1. **`content/campaign_data.json`** — one canonical, platform-neutral definition
   of the Shadow Road (4 regions, 19 nodes, tokens, starter collection).
2. **`scripts/refresh_campaign_data.py`** — one generator that emits:
   - the `const CAMPAIGN_DATA` blob embedded in *both* web shells, and
   - `src/manager/campaign_data_generated.lua` for the native engine.
   Re-running it keeps every platform in lock-step (`--verify` asserts parity).
3. **Rewired `index.html` / `build/web/game.html`** to consume the blob
   (`REGIONS` / `TOKENS` / `STARTER_COLLECTION` are now derived from it), with
   zero gameplay change (verified by `tests/campaign_sim.js`).

This directly satisfies VP §3 (data layer), §16 (one campaign), and §10
(vertical slice 0: "establish the source of truth", no behavior change).

## 5. What the next slices should be (not done here)

In dependency order, each a small vertical slice:

- **Slice 2** — **done**: `campaign_data.lua` requires generated tables and
  resolves pools from CSV / card config.
- **Slice 3** — **in progress**: `w1` enemy/player decks come from canonical
  JSON (`tests/level_w1_test.lua`, `tests/campaign_data_test.py`). Full native
  play-through still needs `setup_test_env.py` fixtures.
- **Slice 4** — keep `index.html` ↔ `build/web/game.html` byte-identical.
- **Slice 5** — **DECIDED** (see `docs/ENGINE_STRATEGY.md`): stay on the thin JS
  port + APK art for the HTML host; do not start WASM/Capacitor this phase.
- **Slice 6** — presentation parity (card frames, skill icons, crystal/HP chrome,
  encounter portraits) so the HTML host uses the Android visual language.

## 6. Guardrails agreed from the VP plan (kept in force)

- Android mechanics stay canonical; no re-implementing combat in HTML when a
  ported/shared implementation already exists.
- New levels = new **data**, not new engine copies.
- One canonical fix location for any shared-mechanic bug.
- No new abstractions without a concrete consumer (§12); no rewriting working
  systems to be "prettier" (§13).
