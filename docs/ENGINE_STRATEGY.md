# Engine strategy — one engine, two shells (decision)

Status: **decided for this phase.** This is PR C from `docs/NEXT_STEPS.md`
(VP §8: decision first, no rewrite).

## Options

| Route | What it is | Cost | Risk | Closeness to Android graphics |
|---|---|---|---|---|
| **(1) LuaJIT → WASM** | Compile `offline_battle.lua` / `offline_server.lua` with a WASI Lua and host it from the HTML page | High (tooling, FFI, Cocos bindings) | High — Cocos2d-x is not WASI | Mechanics 1:1; **rendering still HTML** unless we also port Cocos |
| **(2) WebView / Capacitor wrapping the APK** | Ship the native binary inside a web wrapper | High for a *browser* page (no ARM libcocos in Chrome) | High — does not run as a static HTML file | Pixel-perfect **only on device**, not on the HTML host |
| **(3) Thin JS port + canonical data + real APK art** *(current)* | Keep the already-ported battle JS; feed it `content/campaign_data.json` + extracted sprites | Low | Low — already shipping | Visual language of Android (frames, skill icons, maps); not the Cocos scene graph |

## Recommendation

**Stay on route (3) for the HTML host.** Reasons:

1. The user-facing deliverable is an **HTML page**. Routes (1) and (2) do not put `libcocos2dlua.so` in a browser without a multi-month spike.
2. The JS battle engine is already a port of `offline_battle.lua` (items, keywords, AI). Mechanics bugs still have a canonical Lua fix; the web port tracks it.
3. Presentation parity (PR D) closes the visual gap using the **same art the APK already ships** (`build/web/assets/`), which is the highest-leverage way to “feel like Android” in HTML.
4. Route (1) remains the long-term *mechanics* unification if/when a WASI Lua spike is funded. First spike would be: run `offline_battle.lua` under `wasmer` with a fake `cmd_battle` sink, no UI.

## Go / no-go

- **GO** presentation parity + canonical campaign on the HTML shell (this work).
- **NO-GO** speculative WASM or Capacitor this slice (NEXT_STEPS “out of scope”).
- **Revisit** WASM only after a documented spike that runs one `w1` battle headlessly under Lua-in-WASM.

Recorded in `docs/CONSOLIDATION_PLAN.md` §5 as the chosen interim.
