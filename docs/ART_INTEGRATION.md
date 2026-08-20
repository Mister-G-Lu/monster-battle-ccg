# Art Integration — Making the Web Prototype Look Like the Android Game

**Goal:** replace the text-only cards in `index.html` / `build/web/game.html`
with a proper "card game" look that resembles the original Android title.

**Bottom line:** we do **not** need to scrape "cool websites" or generate art
for the cards — the original game already ships *all* of its artwork inside
`English_offline.apk`, and every card in our pool maps to a real image with
100% coverage. The only thing worth generating ourselves is a logo/banner
(which we did). This document evaluates the three options and records what was
implemented.

---

## 1. What the APK already gives us (the "use existing Pictures" option)

The card art lives in zip archives under `assets/` inside the APK. `scripts/extract_web_art.py`
unpacks them into a flat, browser-friendly tree under `build/web/assets/`:

| Asset | Source (inside APK) | Count | Notes |
|---|---|---|---|
| Creature art | `assets/monster_{war,balance,chaos,fortune,nature}.zip` | 97 | 250×292 painted scenes, fully opaque |
| Item art | `assets/pic_card_item.zip` | 77 | transparent sprites (weapon/armor/potion) |
| Card backing | `assets/kind_bg.zip` | 7 | full-card backgrounds per cost tier |
| Battlefield backdrop | `assets/pic_bg_battlemap.zip` | 2 | 640×1136 portrait battle map + decorations |
| World-map backdrop | `assets/pic_bg_world.zip` | 1 | 640×1136 map art |
| Card-frame atlas | `assets/atlas_card.zip` (`card.png` + `card.plist`) | 117 sprites | rarity gems, faction icons, type icons, **~80 skill icons**, card borders/frames, crystal & HP icons |

The `card.plist` atlas is a Cocos2d-x TexturePacker sheet; `extract_web_art.py`
parses it and slices each sprite (including the 90°-rotation un-packing).

### Coverage check

`csv_data/all_card_config.csv` has a `res_path` column per card. Every one of
the 1,595 playable/tutorial card rows resolves to an existing PNG:

```
monster …/pic_card/monster/{kind}/{res_path}.png   (601/601 found)
armor/equip/consume …/pic_card/item/{res_path}.png (994/994 found)
missing: 0
```

So the real game art is complete, authentic, and already the exact look the
user asked to "resemble". This is option A and it is the one we implemented.

### Licensing caveat

These are the original game's assets. This project is already a fan-made
offline modification of that game (see README "Credits"), so reusing its art
inside that same fan build carries the same status as shipping the APK itself —
fine for personal/fan use, **not** for redistribution or monetisation. If the
project is ever published commercially, the card art must be replaced with
original or openly-licensed art (see §3).

---

## 2. Option A — use the game's own art (implemented ✅)

### Data flow

```
csv_data/all_card_config.csv   (already has res_path + group_id)
        │  scripts/redesign_cards.py build_web_data()  — now emits "res_path" & "group_id"
        ▼
build/web/game_data.json  +  `const GAME_DATA = …` blob inside index.html / game.html
        │
        ▼
index.html runtime:
  ART_BASE  →  "build/web/assets/"   (repo root)  or  "assets/"  (build/web/)
  cardArtUrl(card)  →  cards/monster/{kind}/{res_path}.png | cards/item/{res_path}.png
  createCardEl()    →  renders <div class="card-art" style="background-image:url(…)">
```

### What changed in `index.html`

- **Cards** now show the creature scene (or item sprite) with a bottom stat bar
  (name + faction emblem, ⚔ attack, ❤ hp, keyword line), a rarity gem top-right,
  and a crystal-cost badge top-left — the same composition the Android card uses.
- **Battle screen** gets the extracted battlefield backdrop (`bg/battle_empty.png`),
  subtly dimmed so the UI stays readable.
- **World/campaign screen** gets the world-map backdrop (`bg/world.png`).
- **Header** gets an AI-generated logo emblem next to the "The Shadow Road" title.
- Token creatures (Sapling, Whelp, Wraithguard) have no art of their own, so they
  show their **faction emblem** as a placeholder.

`ART_BASE` is resolved from the page's own path so both `index.html` (repo root)
and `build/web/game.html` (which the headless sim loads) find the same assets.
The two files are kept byte-identical.

### Verification

- `node tests/campaign_sim.js 60` still **PASSES** (49/60 full-road completions,
  every scripted power firing, difficulty curve unchanged) — rendering changes
  are purely presentational and don't touch game logic.
- All asset URLs return HTTP 200 when served.

### Regenerate

```bash
python3 scripts/extract_web_art.py     # re-extract art from the APK
python3 scripts/refresh_web_data.py    # rebuild GAME_DATA with res_path
```

---

## 3. Option B — generate our own art (used for the logo only)

The environment can AI-generate imagery. We used it for one thing the APK does
not have: a **game logo/banner** (`build/web/assets/logo.png`).

**Where generation is a good idea**

- Logo, title banner, favicon, loading/splash screen.
- Menu/backdrop images where a stylised but generic scene is fine.
- Placeholder art while real art is still being wired up.

**Where generation is *not* a good idea for this project**

- Per-card art: the pool has **~97 unique monsters + 77 items**. Generating that
  many images and keeping one creature consistent across its 5 level-ups is
  slow, expensive, and will drift stylistically. We already own the real,
  consistent set — using it is strictly better.
- Anything that must stay pixel-faithful to the Android original.

**Decision:** generate logos/banners; keep the APK's art for cards.

---

## 4. Option C — pull from "cool websites" (free game-art sources)

Valid for a scratch-built game or for *replacing* the copyrighted card art if
this is ever published. Each source has a specific license — verify the
individual asset's license page before shipping; the common ones:

| Source | Typical license | Notes |
|---|---|---|
| **Kenney.nl** | CC0 (public domain) | Safest option; huge packs of UI, icons, cards |
| **OpenGameArt.org** | per-asset: CC0 / CC-BY / CC-BY-SA / GPL | Great CCG bits, but filter by license |
| **Game-icons.net** | CC BY 3.0 | 4,000+ icons — ideal for keyword/skill icons, needs attribution |
| **itch.io (free game assets)** | per-asset (many CC0/CC-BY) | Card frames, fantasy art, UI kits |
| **ambientCG / cc0textures** | CC0 | Seamless textures for backgrounds |
| **Unsplash / Pexels / Pixabay** | free-use photo licenses | Photos only — good for textured backdrops, poor for stylised card art |

**Fit for this project:** lower than option A for cards (we have the real art),
but the *skill-icon* slot could be filled from Game-icons.net if we ever need
icons the APK atlas lacks. For a commercially-safe re-release, Kenney + OpenGameArt
(CC0 only) is the recommended combination.

---

## 5. Roadmap — how far the Android look can be pushed next

Wired into the DOM (presentation-parity slice):

1. **Full card frame** — `ui/border/card_border.png` / equip frames layered over art.
2. **Skill icons on cards** — `ui/skill/*.png` for each keyword (missing names fall back to a blank icon tile).
3. **Crystal & HP icons** — `ui/crystal.png`, `ui/border/hp_bg.png` on cards and the crystal bar.
4. **Encounter intro portraits** — boss/elite deck art (faction emblem placeholder for pool-only skirmishes).
5. **Animated sprites** — `assets/animation.zip` (6.9 MB) holds Cocos2d-x
   animations that could drive attack/death effects.
6. **Sound** — `assets/sound.zip` (4.9 MB) for card/battle SFX.

---

## 6. Files added/changed

- `scripts/extract_web_art.py` — **new**: APK → `build/web/assets/` extractor
  (palette→RGBA conversion + TexturePacker atlas slicer).
- `scripts/refresh_web_data.py` — **new**: rebuild `game_data.json` + the
  embedded `GAME_DATA` blob in both HTML files.
- `scripts/redesign_cards.py` — `build_web_data()` now emits `res_path` and
  `group_id` so future redesign passes keep the art wiring.
- `build/web/assets/` — **new**: ~300 web-ready PNGs extracted from the APK
  (cards, frames, backgrounds, UI sprites) + the generated `logo.png`.
- `index.html` / `build/web/game.html` — card renderer, backdrops, and header
  updated (kept identical).
- `docs/ART_INTEGRATION.md` — this document.
