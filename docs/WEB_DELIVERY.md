# Serving the campaign: web view + Android service

Research and decisions behind `index.html` / `build/web/game.html` and the
campaign's home inside the Android app.

## The question

The Android build (`English_offline.apk`) looks far better than the old web
prototype: it has a real app frame — status bar, app bar, bottom navigation,
bottom sheets, a cold-start splash — while the web page was a flat, scrolling
wall of text blocks. We want the campaign on the web to *look and behave like
the Android game*, from a plain HTML file, **without** faking the Android OS on
top of the actual app.

## How the pros actually do it

There are four families of solution in production today. They are not
interchangeable — they solve different problems.

### 1. Cloud-streamed emulation (Appetize.io, now.gg / BlueStacks X, Genymotion Cloud, BrowserStack)

A real Android instance runs on a server; the browser gets a WebRTC video
stream and forwards touch/click input back. This is genuinely "your APK, in a
browser tab".

* **Used for**: stakeholder demos, QA device matrices, app-store "Try now"
  style previews, cloud gaming.
* **Cost**: Appetize is free for ~100 minutes/month then $59+/mo; Genymotion
  Cloud bills per minute; BrowserStack from $29/mo. Streaming a session is
  metered because it is literally a VM per viewer.
* **Downsides**: latency, session time limits, no persistence between sessions
  on the free tiers, and it dies the moment the vendor's free minutes run out.
  It also cannot be embedded in a static, dependency-free repo page.

Verdict: **wrong tool here.** We would be paying per viewer-minute to stream a
card game whose logic is a few hundred KB of JavaScript that the browser can
run natively.

### 2. Browser extensions / in-page Android runtimes (ARChon, ARC Welder, MyAndroid)

Historically these ran APKs inside Chrome via Native Client. **All dead.**
Chrome removed NaCl and the Chrome Apps platform, and Manifest V3 finished off
the stragglers in 2024–25. Nothing in this category works on a current browser.

Verdict: **not an option.**

### 3. Ship the same game as a real web build (Unity/Unreal WebGL, Cocos Creator web, Flutter web)

Cross-platform engines export a browser target from the same project. This is
how most studios put a playable build on their own site: it is the actual game,
not a stream, so it costs nothing per player and runs at native-ish speed.

The catch for *this* repo: the Android title is Cocos2d-x 3.x + LuaJIT with
`libcocos2dlua.so`, an ARM native binary. There is no supported path from that
APK to a Cocos web build without porting the whole client. We already made the
pragmatic version of this choice — the web campaign is an independent
JavaScript reimplementation of the battle system driven by the *same* extracted
game data and the *same* extracted art.

Verdict: **this is the model we follow**, and it is already in place.

### 4. Progressive Web App plumbing (installable, offline, no fake chrome)

The PWA layer is still valuable — but only the parts a real OS does *not*
provide: `display: standalone` launches with no browser UI once installed,
maskable icons keep the launcher icon on-brand, `theme_color` /
`background_color` tint the OS bars and the install splash, a service worker
makes the game work fully offline, `viewport-fit=cover` + safe-area insets
clear the display cutout and gesture bar, and `@media (display-mode: standalone)`
lets the page adapt when installed.

What the web page must **not** do is reproduce the Android OS chrome (status
bar, app bar, bottom navigation, bottom sheets, cold-start splash, gesture
pill, phone frame) in HTML. The Android game owns the frame; on a handset the
OS draws the real bars, and a fake set drawn *on top of the game* is what made
the campaign read as a second, overlaid copy of the app. That chrome was
removed: the page now renders only game content — a slim in-game HUD, the
campaign screens, and a compact tab strip.

## What we built

### Web: a clean game view (no fake OS chrome)

| What | Web implementation |
|---|---|
| In-game HUD | `#game-hud` — back button (sub-screens only), title/subtitle, overflow menu |
| Tabs | `#tab-campaign` / `#tab-deck` / `#tab-help` — compact strip inside the game view, not a Material bottom nav |
| Overlays | centered game panels (intro, result, rewards, deck, help, menu) |
| Snackbar | `toast()` for recruit / EXP / install feedback |
| Back behavior | `appBack()`, wired to `popstate`, closes the top overlay then retreats from a battle |
| Installable | `manifest.webmanifest` + `sw.js` (offline first, cache-first for art) |
| Safe areas | `viewport-fit=cover` + `env(safe-area-inset-*)` — the OS bars are real, content stays clear of them |

Removed: `.device` phone frame + stage caption, `.sysbar` fake status bar,
`.appbar` fake app bar, `.bottomnav` fake bottom navigation, sheet grip
handles, cold-start `.splash`, gesture pill. The Android game — or the device's
own bars — now provides all of that. `tests/app_shell_test.js` asserts the game
HUD/tabs/overlays are present and the fake chrome is gone.

### Android: the campaign is a native service feature

The same canonical campaign (`content/campaign_data.json` →
`src/manager/campaign_data_generated.lua`) is now served by the Android app's
own in-process game server, `src/manager/offline_server.lua`, through
`src/manager/campaign_service.lua`:

- `req_campaign_info` — regions, progress, collection, vitality.
- `req_campaign_battle_start{node_id}` — builds the enemy deck from the
  canonical node pool, the player deck from the campaign collection, and runs
  the **real Android battle engine** (`offline_battle.lua`); rejects locked
  nodes / pending recruits.
- Victory/defeat (`OnCampaignOver`) — first-clear EXP + 3-card recruit draft,
  replay EXP, +2 max vitality per boss, final-boss completion flag.
- `req_campaign_recruit_offers` / `req_campaign_recruit` /
  `req_campaign_skip_recruit` / `req_campaign_reset`.

Campaign progress lives in the game's own save file. `tests/level_w1_test.lua`
and `tests/campaign_service_test.lua` assert the w1 slice end-to-end (deck
plumbing plus win/loss through the native engine).

### Files

```
index.html                      the game view (served from the repo root)
manifest.webmanifest            PWA manifest, icons pointed at build/web/assets/
sw.js                           offline service worker
build/web/game.html             byte-identical mirror, served from build/web/
build/web/manifest.webmanifest, build/web/sw.js   the mirror's copies
build/web/assets/icons/         icon-{192,512}.png + maskable-{192,512}.png
src/manager/campaign_service.lua      native campaign service (pure data/logic)
src/manager/campaign_data.lua         native adapter onto campaign_data_generated
tests/app_shell_test.js         regression tests for the game view + PWA files
tests/campaign_service_test.lua regression tests for the native campaign service
```

Both HTML copies must stay byte-identical (enforced by
`tests/static_checks.py`), so the manifest/SW/icon paths are resolved at runtime
from the page's own directory — the same trick `ART_BASE` already used.

### Verifying

```bash
make verify            # static checks (including refresh_campaign_data.py --verify)
node tests/app_shell_test.js        # game view + manifest/SW/icon consistency
node tests/campaign_sim.js 40       # the campaign engine itself
luajit tests/campaign_service_test.lua   # native campaign service + w1 end-to-end
make web               # serve at http://localhost:8000/ and try it
```

Install prompts and service workers require a secure context: `http://localhost`
counts, `file://` does not. Opening the file directly still plays fine — the
service worker registration is skipped.

## Android Chrome pitfalls the shell now avoids

These are the mistakes that show up over and over in Android web games (Chrome
tab, installed PWA, and WebView). Each one had a concrete bug in this page:

| Mistake | What it did here | Fix |
|---|---|---|
| A second `body { overflow-x: hidden }` after `overflow: hidden` | CSS overflow pairing resets `overflow-y` to `auto`, so the document itself scrolled. Pull-to-refresh reloaded the game; the tab strip was no longer stuck to the bottom. | One `html, body { height: 100dvh / var(--app-h); overflow: hidden; overscroll-behavior: none }` rule. |
| `100vh` / `100dvh` without `visualViewport` | Android Chrome's URL bar lies about the viewport; the HUD/tabs clipped or left a gap. | `--app-h` is set from `visualViewport.height` on resize/orientation. |
| `position: absolute` overlays | Modals were tied to the document, not the visual viewport — they drifted under the URL bar and didn't cover the HUD. | `.overlay` / `.snackbar` are `position: fixed` and padded with `safe-area-inset-*` (including left/right for landscape notches). |
| `history.pushState` on every load | Hardware Back in a regular Chrome tab was hijacked so the first press did nothing. | Trap Back only in `display-mode: standalone`. |
| Sticky `:hover` after a tap | Buttons stayed in the hover color until the next tap. | Hover styles gated on `@media (hover: hover) and (pointer: fine)`. |
| Long-press on cards | Android Chrome showed Save-image / text-select / the system context menu. | `user-select: none`, `-webkit-touch-callout: none`, `contextmenu`/`dragstart` cancelled. |
| Android font boosting | `text-size-adjust` inflated the small card type and broke the frame. | `text-size-adjust: 100%`. |
| Cache-first HTML / cached `sw.js` | Players could be stuck on a stale build; `sw.js` itself sat in the HTTP cache. | Network-first for documents + manifest; `updateViaCache: 'none'`. |
| No save flush on background | Android may kill a background WebView; an unsaved recruit could vanish. | `pagehide` + `visibilitychange` call `writeSave()`. |
