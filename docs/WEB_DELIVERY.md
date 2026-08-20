# Serving the Android app on the web

Research + the decision behind the app shell in `index.html` /
`build/web/game.html`.

## The question

The Android build (`English_offline.apk`) looks far better than the old web
prototype: it has a real app frame — status bar, app bar, bottom navigation,
bottom sheets, a cold-start splash — while the web page was a flat, scrolling
wall of text blocks. We want the campaign on the web to *look and behave like
the Android app*, from a plain HTML file.

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
pragmatic version of this choice — the web prototype is an independent
JavaScript reimplementation of the battle system driven by the *same* extracted
game data and the *same* extracted art.

Verdict: **this is the model we follow**, and it is already in place.

### 4. Progressive Web App: an app shell that *is* the app

The remaining gap was never the engine — it was the chrome. The industry answer
for "web content that must feel like a native mobile app" is the **app shell +
PWA** pattern, and the guidance is consistent across MDN, web.dev and the
practitioner writeups:

* A **web app manifest** with `display: standalone` launches the app in its own
  window with no browser UI, so it looks native once installed.
* **Maskable icons** are required on Android, or the launcher shoves your icon
  inside a white circle and instantly outs it as a web app.
* `theme_color` / `background_color` tint the system bars and the splash.
* A **service worker** caches the shell so the app boots with no network — the
  natural fit for a build whose entire selling point is being offline.
* `@media (display-mode: standalone)` lets the page adapt when it is launched
  as an installed app versus in a browser tab (e.g. hide the "install me" hint,
  disable overscroll/pull-to-refresh).
* `viewport-fit=cover` plus `env(safe-area-inset-*)` keeps content clear of
  display cutouts and the gesture bar.
* The **app shell** itself — persistent app bar, bottom navigation, bottom
  sheets, a cold-start splash — is what actually makes it read as an app.
  Content scrolls; the chrome does not.

Google's own `Play Instant` / "Try now" program is the native-side answer to
the same problem (play a demo without installing), but it publishes a stripped
APK through the Play Store — it does not put anything in a browser.

## What we built

A **PWA app shell that reproduces the Android build's chrome in HTML/CSS**, with
the existing campaign engine untouched underneath:

| Android affordance | Web implementation |
|---|---|
| Status bar | `.sysbar` — live clock, signal/wifi/battery glyphs, cutout. Hidden on real phones (the OS draws the real one) |
| App bar | `.appbar` — title + subtitle retitle per screen, back arrow appears only on sub-screens, overflow menu |
| Bottom navigation | `.bottomnav` — Campaign / Deck / How to play, with a Material pill indicator and a count badge; hidden during battles for an immersive view |
| Bottom sheets | every overlay (intro, result, rewards, deck, help, menu) slides up from the bottom with a grip handle |
| Snackbar | `toast()` for recruit / EXP / install feedback |
| Cold-start splash | `.splash` — logo + indeterminate progress bar, auto-dismissed on load |
| Hardware back button | `appBack()`, wired to `popstate`, closes the top sheet then retreats from a battle |
| Adaptive launcher icon | `assets/icons/maskable-*.png`, cropped from the game's own logo emblem |
| Install to home screen | `beforeinstallprompt` captured, offered in the overflow menu |
| Offline | `sw.js` — network-first for navigations, cache-first for art |

On a desktop browser the whole thing is presented inside a **phone frame** on a
blurred backdrop of the game's own world art, so the page reads as "here is the
Android app". Below 620px wide — or whenever the manifest's `standalone` display
mode is active — the frame, the fake status bar and the gesture pill all drop
away and the app goes edge-to-edge, because at that point it *is* the app.

The text-heavy blocks that motivated the request are gone: the world header is
now a hero banner over the game's key art, the stats line is a row of Material
chips, campaign progress is a real progress card, and "How to play" moved out of
the page body into a bottom sheet behind a nav tab.

### Files

```
index.html                 the app shell + campaign (served from the repo root)
manifest.webmanifest       PWA manifest, icons pointed at build/web/assets/
sw.js                      offline service worker
build/web/game.html        byte-identical mirror, served from build/web/
build/web/manifest.webmanifest, build/web/sw.js   the mirror's copies
build/web/assets/icons/    icon-{192,512}.png + maskable-{192,512}.png
tests/app_shell_test.js    regression tests for the chrome + the PWA files
```

Both HTML copies must stay byte-identical (enforced by
`tests/static_checks.py`), so the manifest/SW/icon paths are resolved at runtime
from the page's own directory — the same trick `ART_BASE` already used.

### Verifying

```bash
make verify            # static checks (now including the PWA/app-shell checks)
node tests/app_shell_test.js   # app shell chrome + manifest/SW/icon consistency
node tests/campaign_sim.js 40  # unchanged: the campaign engine itself
make web               # serve at http://localhost:8000/ and try it
```

Install prompts and service workers require a secure context: `http://localhost`
counts, `file://` does not. Opening the file directly still plays fine — the
service worker registration is skipped.
