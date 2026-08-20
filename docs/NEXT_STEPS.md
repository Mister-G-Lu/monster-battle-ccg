# Next Steps — PR Roadmap for the Android + Web Consolidation

Status of the consolidation at the time of writing (updated):

- **PR A done** — `src/manager/campaign_data.lua` is adapters only (`require` generated tables + pool resolution).
- **PR C done** — `docs/ENGINE_STRATEGY.md` records route (3).
- **PR B (this slice)** — `w1` decks are built from canonical JSON + CSV; `tests/level_w1_test.lua` covers plumbing and, with fixtures, win/loss.
- **PR F (partial)** — `make verify` / `static_checks` run `refresh_campaign_data.py --verify` and require identical HTML shells.

Status of the consolidation at the time of writing:

- **PR #10 merged** — the art integration **and** the first consolidation slice
  (one canonical campaign source: `content/campaign_data.json` →
  `scripts/refresh_campaign_data.py` → web blob + `campaign_data_generated.lua`).
- **PR #11 merged earlier** — the Android battle engine ported to the web shell
  (items/equip/armor/consume, full keywords, strategic AI).
- **Web shells are identical again** (`index.html` == `build/web/game.html`),
  both running the full engine + real art + the canonical campaign.
- **Web de-chrome landed** — the fake Android chrome (phone frame, status bar,
  app bar, bottom navigation, bottom sheets, splash) was removed from the page;
  it now renders only game content (HUD + tabs + screens), and the Android app
  / device OS owns the frame.
- **The campaign is now a native Android service feature** — the in-process
  server (`offline_server.lua`) serves the Shadow Road through
  `src/manager/campaign_service.lua` (info / battle start / rewards / recruit /
  reset), running battles on the real `offline_battle` engine, with progress in
  the game save. `tests/campaign_service_test.lua` + `tests/level_w1_test.lua`
  cover the w1 slice end-to-end (PR B, below, is substantially landed).
- **PR #9 is still OPEN** — the native campaign **client scene** (`campaign_panel.lua`):
  the service handlers it should call are in place, but the Cocos scene that
  drives them is not yet merged. That scene now consumes the canonical data via
  `src/manager/campaign_data.lua` (adapter over `campaign_data_generated.lua`) —
  no hand-copied campaign remains.

The order below is deliberately small, vertical slices (VP §10). Each PR must
land independently, with its own green tests, before the next starts.

---

## PR A — Reconcile the native campaign with the canonical data (unblock PR #9)

**Goal.** Kill the "AndroidCampaign vs WebCampaign" duplication (VP §16) that
PR #9 introduced: its `src/manager/campaign_data.lua` hand-copies the same
Shadow Road the web uses.

**Problem it solves.** Two definitions of the same 19 nodes/powers/tokens now
exist (the canonical JSON and PR #9's Lua). Any balance change must be made
twice; they are already drifting (PR #9's nodes lack the newest power text).

**Scope.**
- Rebase PR #9 (`arena/01a0205d-monster-battle-ccg`) onto the merged `main`.
- Replace the inline `REGIONS`/`TOKENS`/starter tables in
  `src/manager/campaign_data.lua` with `require("manager.campaign_data_generated")`
  and expose `M.REGIONS` / `M.TOKENS` / `M.STARTER_COLLECTION` from it
  (keeping any native-only helpers like `kind_flag`, pool resolution, lookups).
- Update the JSON if the generator's snake_case field names differ from what the
  panel/engine expect — add a small adapter in `campaign_data.lua`, **not** a
  second copy of the data.

**Done when.**
- `campaign_data.lua` contains **no** hand-written node/deck/power literals.
- `scripts/refresh_campaign_data.py --verify` passes.
- `luajit tests/campaign_test.lua` and `tests/campaign_balance_diag.lua` pass
  unchanged (same campaign semantics as before, VP §14).
- A one-line edit to a node in `content/campaign_data.json`, re-run of the
  generator, changes both the web and the native game.

---

## PR B — One playable level end-to-end on the native engine (the "proving slice")

**Goal.** Prove the architecture on **one** complete level before migrating the
rest (VP §10: "start with ONE complete playable campaign level").

**Problem it solves.** Right now the canonical data drives the web engine; we
have not yet demonstrated it driving the **canonical Android engine** through a
full level with identical semantics.

**Scope.** Use `w1` (Forest Trail, skirmish, nature pool, HP 14):
- Drive `offline_battle` from the canonical node: pool resolution → enemy deck,
  player starter deck, HP/crystal/round rules, win/loss.
- Keep the web and native outputs comparable: capture the `cmd_battle` event
  stream from the native engine for `w1` and diff the *state transitions* against
  the web engine's log for the same seed/deck (a mechanics-parity harness, not a
  pixel diff).

**Done when.**
- `w1` is playable end-to-end on the native build with no new gameplay code —
  only data plumbing (VP §4: "the campaign should configure the engine").
- The parity harness lists every observed difference and each is either fixed
  (native is authoritative, VP §14) or explicitly waived with a reason.
- A new test (`tests/level_w1_test.lua`) asserts victory and defeat for `w1`.

---

## PR C — Shared-engine feasibility decision (VP §8, decision first, no code)

**Goal.** Pick the long-term "one engine, two shells" route and stop the
speculative drift.

**Problem it solves.** The web shell is a JS **port** of the Lua engine, which
violates the spirit of "one canonical engine" — but the Cocos2d-x/LuaJIT binary
cannot run in a browser today. We need a documented, decided answer.

**Scope (a decision doc, not a rewrite).**
- Evaluate: (1) LuaJIT → WebAssembly (e.g. WASI/Lua.WASM hosting the existing
  `offline_battle.lua`/`offline_server.lua`), (2) a WebView/Capacitor wrapper
  shipping the existing APK core, (3) the current "thin JS port fed by the same
  canonical data + a parity harness" as a deliberate interim.
- Recommend one, with cost/risk, and the concrete first spike for it.

**Done when.** `docs/ENGINE_STRATEGY.md` exists with a recommendation and a
go/no-go; the choice is recorded in `docs/CONSOLIDATION_PLAN.md`.

---

## PR D — Presentation parity for the web shell (VP §7 / §15)

**Goal.** Close the visual gap between the web shell and the Android game now
that the engine is shared.

**Problem it solves.** The web cards/backdrops look good but are still
hand-built approximations; the Android atlas contains the real frames, icons and
effects we already extracted.

**Scope (incremental, one PR each if needed):**
- Item cards: verify the full-size art frame for equip/armor/consume reads
  clearly (the merge just reconciled the CSS; needs a visual pass).
- Card chrome: layer the real frame sprites (`ui/border/*`, `frame/bg_*.png`)
  behind the art instead of the gradient card background.
- Skill icons: replace the text keyword line with `ui/skill/*.png`.
- Stat icons: replace ⚔/❤ glyphs with `ui/crystal.png`, `ui/border/hp_bg.png`.
- Encounter intro: show boss/creature art instead of emoji.
- (Later) `animation.zip` sprite sequences and `sound.zip` SFX.

**Done when.** A side-by-side review of the web shell vs the Android game shows
the same visual language (VP §7), and `tests/campaign_sim.js` still passes.

---

## PR E — Migrate the remaining campaign nodes (the payoff)

**Goal.** Move all 19 nodes fully onto the canonical data path and drop any
remaining per-level JS hooks.

**Problem it solves.** The web engine still has `POWER_IMPL` scripted hooks for
the 8 elite/boss powers. If the native engine's power system can express them
(muster/plunder/bloodlust/warding/overgrowth/hunger/flamewave/toll), the powers
should become **data + engine features**, not web-only code (VP §4).

**Scope.**
- For each scripted power, decide: existing engine system vs new shared mechanic.
  New mechanics go into the engine (`offline_battle.lua` + the JS port), gated by
  the canonical power `id`, never a web-only workaround (VP §14).
- Delete the web-only `POWER_IMPL` in favour of the shared implementation.

**Done when.** Adding a level is **only** a JSON edit (VP §17), and every boss
power is validated by both `campaign_sim.js` and the Lua integration tests.

---

## PR F — Collapse the remaining "two sources" debt

**Goal.** One campaign, one card set, one place to fix a bug.

**Problem it solves.** The web copy drift we fixed for the HTML shells still
exists in spirit elsewhere: `build/web/game_data.json` vs the `GAME_DATA` blob,
and the CSV vs the web JSON (regeneration exists but is easy to forget).

**Scope.**
- Add a CI-able check: `refresh_campaign_data.py --verify` and
  `refresh_web_data.py` must produce a clean `git diff` (i.e. the checked-in
  artifacts are never stale). Wire it into the test suite / a `make verify`.
- Consider deleting `build/web/game_data.json` + the `GAME_DATA` blob duplication
  by having the page fetch one file (keep it working offline/`file://`-safe).

**Done when.** `git status` is clean after running all generators, and CI fails
if a content change is committed without regenerating.

---

## Out of scope / risks to keep visible

- **Full shared runtime (WASM/WebView)** is gated behind PR C's decision — do
  not start it speculatively.
- **Rewriting the Lua engine for "prettiness"** is forbidden (VP §13); adapters
  only.
- **PR #9 is a moving target** — it must be rebased/merged before PR B can rely
  on its panel wiring.

## Overall "done" (VP §17, abbreviated)

- Android mechanics intact and canonical; web campaign is data; campaign not
  duplicated; web gameplay uses the real renderer/art; a bug in a shared
  mechanic has one fix; adding a level is a data edit; the web version feels
  like the Android game.
