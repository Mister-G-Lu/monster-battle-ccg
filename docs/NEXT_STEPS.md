# Next Steps — PR Roadmap for the Android + Web Consolidation

Status after **PR #13 merged** (`arena/01a020de-monster-battle-ccg`):

- **PR #10–#12 merged** — canonical campaign JSON, web engine port, art extract.
- **PR #13 merged** — HTML presentation parity (Android card chrome, skill/crystal/HP
  icons, encounter portraits); `index.html` == `build/web/game.html`;
  `docs/ENGINE_STRATEGY.md` (stay on JS port + APK art for the HTML host);
  native `src/manager/campaign_data.lua` is an adapter over
  `campaign_data_generated.lua` (no hand-copied nodes).
- **Still open:** drive the *native* Lua battle engine from that same data for
  one full level; lift elite/boss powers out of web-only hooks; generator
  freshness in CI.

The order below is deliberately small, vertical slices (VP §10). Each PR must
land independently, with its own green tests, before the next starts.

---

## Next PR — One playable level end-to-end on the native engine (`w1`)

**Goal.** Prove the architecture on **one** complete level before migrating the
rest (VP §10: "start with ONE complete playable campaign level").

**Problem it solves.** Canonical JSON already drives the web engine and the
native data tables. We have not yet shown it driving `offline_battle.lua`
through a full Forest Trail (`w1`) with identical semantics.

**Scope.** Use `w1` (skirmish, nature pool, HP 14):
- Drive `offline_battle` from the canonical node: pool resolution → enemy deck,
  player starter deck, HP/crystal/round rules, win/loss.
- Capture the `cmd_battle` event stream from the native engine for `w1` and
  diff *state transitions* against the web engine log for the same seed/deck
  (mechanics-parity harness, not a pixel diff).

**Done when.**
- `w1` is playable end-to-end on the native build with no new gameplay code —
  only data plumbing (VP §4).
- The parity harness lists every observed difference; each is fixed (native is
  authoritative, VP §14) or explicitly waived.
- `tests/level_w1_test.lua` asserts victory and defeat for `w1`.

---

## Landed (do not re-open)

### PR A — Native campaign adapter — **done in #13**

`campaign_data.lua` has no node/deck/power literals; it requires
`campaign_data_generated.lua`. Remaining work if PR #9's panel still exists
elsewhere: rebase that panel onto this adapter, do not copy tables again.

### PR C — Engine strategy — **done in #13**

`docs/ENGINE_STRATEGY.md`: HTML host stays on the thin JS port + APK art.
WASM/Capacitor is a later spike only.

### PR D — Presentation parity (chrome) — **done in #13**

Frames, skill icons, crystal/HP sprites, encounter portraits. Follow-ups
(`animation.zip`, `sound.zip`) are optional polish, not blockers.

---

## After `w1`: remaining campaign powers (was PR E)

**Goal.** Move all 19 nodes fully onto the canonical data path and drop
web-only per-level JS hooks.

**Problem it solves.** The web engine still scripts the 8 elite/boss powers
(`muster` / `plunder` / `bloodlust` / `warding` / `overgrowth` / `hunger` /
`flamewave` / `toll`). If the native engine can express them, they become
**data + engine features**, not web-only code (VP §4).

**Done when.** Adding a level is **only** a JSON edit (VP §17), and every boss
power is validated by both `campaign_sim.js` and Lua integration tests.

---

## After powers: generator freshness (was PR F)

**Goal.** One campaign, one card set, one place to fix a bug.

**Scope.**
- CI check: `refresh_campaign_data.py --verify` and `refresh_web_data.py`
  leave a clean `git diff`.
- Optionally drop `GAME_DATA` vs `game_data.json` duplication while keeping
  `file://` playable.

**Done when.** `git status` is clean after generators; CI fails on stale blobs.

---

## Out of scope / risks to keep visible

- **Full shared runtime (WASM/WebView)** — decided against for the HTML host
  (`ENGINE_STRATEGY.md`). Do not start it speculatively.
- **Rewriting the Lua engine for "prettiness"** is forbidden (VP §13); adapters
  only.
- **PR #9 panel wiring** — if it still exists as a separate branch, rebase onto
  the adapter in `campaign_data.lua`; do not reintroduce literals.

## Overall "done" (VP §17, abbreviated)

- Android mechanics intact and canonical; web campaign is data; campaign not
  duplicated; web gameplay uses the real renderer/art; a bug in a shared
  mechanic has one fix; adding a level is a data edit; the web version feels
  like the Android game.
