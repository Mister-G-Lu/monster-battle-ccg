# Browser build — next steps

The browser build (`web/`) runs the **real Lua engine in WebAssembly** and is
already playable: campaign map + commander-HP battles. This is the roadmap to
take it from "playable proof" to "shippable identical web version."

See `web/README.md` for architecture and how to run it.

---

## 0. Run what exists

```bash
cd web
npm install
npm run dev        # prepares assets from the APK, starts Vite on 0.0.0.0:5173
```

Progress persists to `localStorage`. To reset: clear site data, or in the
console `localStorage.removeItem('mb_save')`.

---

## 1. Recruit-draft chooser UI  ✅ done

After a node's *first* clear the campaign opens a 3-card recruit draft
("collection IS your deck" — it's what keeps later acts winnable). The victory
screen (and the map, if a draft is still pending) renders the chooser:
`engine.recruitOffers(node.id)` → pick `engine.recruit(node.id, card.id)` or
`Skip (+15 EXP)` → `engine.skipRecruit()`. Card names resolve from
`data_template.card_config`. Covered by `web/tests/ui.test.mjs`,
`tests/web_bridge_test.lua`, and `web/tests/bridge_recruit.mjs`.

---

## 2. Card art from the APK  (visual parity, now highest value)

**Why:** cards/monsters are text tiles right now. The APK ships the real sprites.

**Do:**
1. Find the atlases/pngs in the APK (`assets/`, `res/`), likely plist+png
   TexturePacker atlases. Add extraction to `scripts/prepare_web.py` (copy the
   needed pngs into `web/public/art/` — keep it gitignored like other generated
   assets).
2. Map a card/monster to its image. `res_path` already comes through on the card
   record (`offline_battle.BuildCardInfo`), and `data_template.card_config`
   carries icon fields — expose whichever resolves to a real file via the bridge.
3. Render `<img>`/CSS-background in the hand + board cells in `src/ui.js`.
4. If atlases are used, either slice them at build time or render with
   background-position from the plist frames.

---

## 3. Scripted boss powers + battle feedback  (polish)

**Why:** bosses have scripted powers (Gathering Power, Overgrowth, phase-2
triggers). The engine already emits them on the `cmd_battle` stream; the UI just
doesn't surface them, and combat currently "snaps" between states.

**Do:**
1. The bridge already captures `cmd_battle` into `battle_log`. Expose a
   `drain_battle_log()` bridge method returning new commands since last drain.
2. In `src/ui.js`, after each action, drain the log and show toasts/animations
   for `cmd_battle_hero` (HP change), attacks, deaths, and boss power callouts.
3. Animate HP-bar changes and attack lunges (CSS transitions are already partly
   there on `.hpfill`).

---

## 4. PWA (installable + offline parity with the app)

**Why:** the app's whole identity is "fully offline." Match it on web.

**Do:**
1. Add `web/public/manifest.webmanifest` (name, icons, `display: standalone`,
   theme color `#0e1116`).
2. Add a service worker that precaches the app shell + the Lua/CSV/WASM assets so
   it runs with no network after first load. `vite-plugin-pwa` is the easy path.
3. Link the manifest in `index.html`; test "Add to Home Screen".

---

## 5. Parity harness (guardrail)

**Why:** guarantee the web build's mechanics never drift from the APK.

**Done so far:** `web/tests/bridge_recruit.mjs` boots the real engine in WASM and
asserts the recruit-draft API (real card names, pick grows the collection, skip
via the server handler, invalid picks rejected). `tests/web_bridge_test.lua`
covers the same path under LuaJIT. `make verify` runs the WASM harness.

**Still to do:**
1. Reuse the existing Lua tests (`tests/campaign_*_test.lua`) as the oracle.
2. Assert the same battle invariants in WASM: 19 nodes, 30/14 hero HP on w1,
   deterministic battle outcome for a fixed RNG seed + scripted moves.
3. Wire a full CI job so a broken bridge/shim fails the build.

---

## 6. Deployment

**Why:** `npm run build` already emits a static site in `web/dist/`.

**Do:**
1. Host `web/dist/` on any static host (GitHub Pages, Netlify, Cloudflare Pages).
2. Ensure the host serves `.wasm` with `application/wasm` and (ideally) the Lua
   files with long-cache headers + a content hash.
3. Point the repo's landing `index.html` at the hosted web build alongside the
   APK download, so there's a real "Play in browser" option.

---

## Known limitations / gotchas

- **Generated assets are gitignored.** `web/public/game`, `web/public/csv`, the
  manifest, and the copied bridge are produced by `prepare_web.py` from the
  decrypted APK (same policy as `decrypted/` / `csv_plain/`). Run
  `npm run dev`/`build` to regenerate — a fresh checkout has no `public/game`
  until then.
- **Greedy fallback in `play_card`.** The bridge deploys to the current free
  monster slot and equips the first friendly monster. Manual target selection
  (which lane, which monster to equip) is a future refinement.
- **Save format.** Progress is the engine's own `UserDefault` blob serialized to
  `localStorage['mb_save']`; it is not compatible with an APK save file.
