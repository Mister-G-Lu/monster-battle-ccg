#!/usr/bin/env python3
"""Extract the Android game's real artwork from the APK into web-ready PNGs.

The original game ships all of its card art, card-frame UI and backgrounds
inside ``English_offline.apk`` as a set of zip archives under ``assets/``.
This script unpacks those archives and flattens every sprite/texture into a
single ``build/web/assets/`` tree that the browser prototype
(``index.html`` / ``build/web/game.html``) can reference directly.

What we get (and where it lands):

    build/web/assets/
      cards/monster/<faction>/<res_path>.png   # 97 painted creature scenes
      cards/item/<res_path>.png                # 77 transparent item sprites
      frame/bg_<n>.png                         # card backing per cost tier
      bg/battle_empty.png                      # 640x1136 battlefield backdrop
      bg/battle_decor.png                      # battlefield decorations layer
      bg/world.png                             # 640x1136 world-map backdrop
      ui/skill/<name>.png                      # ~80 keyword/skill icons
      ui/quality/<normal|rare|rarity|epic>.png # rarity gems
      ui/faction/<kind>.png                    # faction color icons
      ui/kind/<type>.png                       # card type icons
      ui/crystal.png, ui/hp.png                # stat icons
      ui/border/...                            # full card-frame chrome

Everything is converted to 8-bit RGBA PNG so browsers render it the same way
the Cocos2d-x client did (the source sprites are palette PNGs).

Usage:
    python3 scripts/extract_web_art.py            # extract everything
    python3 scripts/extract_web_art.py --apk PATH # use a different APK
    python3 scripts/extract_web_art.py --no-atlas # skip the atlas slice step
"""

from __future__ import annotations

import argparse
import io
import plistlib
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APK = ROOT / "English_offline.apk"
OUT = ROOT / "build" / "web" / "assets"

# zip archive inside the APK -> list of (internal pattern, destination prefix)
# Destination paths are relative to OUT.
ART_MAPS = [
    ("assets/monster_war.zip",     "res/ui/pic_card/monster/war/",     "cards/monster/war/"),
    ("assets/monster_balance.zip", "res/ui/pic_card/monster/balance/", "cards/monster/balance/"),
    ("assets/monster_chaos.zip",   "res/ui/pic_card/monster/chaos/",   "cards/monster/chaos/"),
    ("assets/monster_fortune.zip", "res/ui/pic_card/monster/fortune/", "cards/monster/fortune/"),
    ("assets/monster_nature.zip",  "res/ui/pic_card/monster/nature/",  "cards/monster/nature/"),
    ("assets/pic_card_item.zip",   "res/ui/pic_card/item/",            "cards/item/"),
    ("assets/kind_bg.zip",         "res/ui/kind_bg/",                  "frame/"),
    ("assets/pic_bg_battlemap.zip","res/ui/pic_bg/battlemap/",         "bg/"),
    ("assets/pic_bg_world.zip",    "res/ui/pic_bg/world/",             "bg/"),
]

# battlemap files get friendlier names than their archive names
BG_RENAME = {
    "battlemap_empty.png": "battle_empty.png",
    "battlemap_decorate1.png": "battle_decor.png",
    "main_bg.png": "world.png",
}

ATLAS_ZIP = "assets/atlas_card.zip"
ATLAS_PLIST = "res/atlas/card.plist"
ATLAS_PNG = "res/atlas/card.png"


def convert_png(data: bytes) -> bytes:
    """Re-encode any PNG as 8-bit RGBA (handles palette/indexed sources)."""
    from PIL import Image  # imported lazily so a missing Pillow is a clear error

    im = Image.open(io.BytesIO(data))
    if im.mode not in ("RGBA", "LA"):
        im = im.convert("RGBA")
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def extract_flat_art(apk: Path, out: Path) -> int:
    """Copy the standalone PNG archives into the flat web tree."""
    count = 0
    with zipfile.ZipFile(apk) as apkz:
        for archive, prefix, dest in ART_MAPS:
            if archive not in apkz.namelist():
                print(f"  WARN: {archive} not found in APK — skipping", file=sys.stderr)
                continue
            inner = zipfile.ZipFile(io.BytesIO(apkz.read(archive)))
            for name in inner.namelist():
                if not name.endswith(".png"):
                    continue
                rel = name[len(prefix):] if name.startswith(prefix) else name.split("/")[-1]
                if not rel:
                    continue
                # apply battlemap renames
                if dest == "bg/":
                    rel = BG_RENAME.get(rel, rel)
                target = out / dest / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(convert_png(inner.read(name)))
                count += 1
    return count


def parse_plist_frame(v: dict):
    """Return (rect, rotated, offset, source_size) for a TexturePacker frame."""
    m = re.match(r"\{\{(\d+),(\d+)\},\{(\d+),(\d+)\}\}", v["frame"])
    x, y, w, h = map(int, m.groups())
    rotated = bool(v.get("rotated", False))
    off = v.get("offset", "{0,0}")
    om = re.match(r"\{(-?\d+),(-?\d+)\}", off)
    ox, oy = (int(om.group(1)), int(om.group(2))) if om else (0, 0)
    sm = re.match(r"\{(\d+),(\d+)\}", v.get("sourceSize", f"{{{w},{h}}}"))
    sw, sh = (int(sm.group(1)), int(sm.group(2))) if sm else (w, h)
    return (x, y, w, h), rotated, (ox, oy), (sw, sh)


def slice_atlas(apk: Path, out: Path) -> int:
    """Unpack the card-frame texture atlas (card.png + card.plist) into sprites."""
    from PIL import Image

    with zipfile.ZipFile(apk) as apkz:
        archive = zipfile.ZipFile(io.BytesIO(apkz.read(ATLAS_ZIP)))
        plist = plistlib.loads(archive.read(ATLAS_PLIST))
        sheet = Image.open(io.BytesIO(archive.read(ATLAS_PNG))).convert("RGBA")

    frames = plist.get("frames", {})
    count = 0
    for key, v in frames.items():
        rect, rotated, (ox, oy), (sw, sh) = parse_plist_frame(v)
        x, y, w, h = rect
        if rotated:
            # TexturePacker format-2 stores sprites rotated 90° clockwise; the
            # on-sheet box therefore swaps the frame's width/height.
            box = (x, y, x + h, y + w)
            sprite = sheet.crop(box).rotate(90, expand=True)
        else:
            box = (x, y, x + w, y + h)
            sprite = sheet.crop(box)

        # Recreate the untrimmed sprite on a sourceSize canvas and apply the trim offset.
        canvas = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
        canvas.paste(sprite, (ox, oy), sprite)

        # Route each sprite into a friendly folder.
        name = key.split("/")[-1]
        if "/skill/" in key:
            dest = f"ui/skill/{name}"
        elif "/pic_card/" in key:
            if key.startswith("ui/pic_card/quality_"):
                dest = f"ui/quality/{name[len('quality_'):]}"
            elif name in ("battlecard_colorbg.png", "battlecard_colorbg2.png",
                          "battlecard_decorate.png", "battlecard_equip1.png",
                          "battlecard_equip2.png", "battlecard_equipempty.png",
                          "battlecard_light.png", "battlecard_light2.png",
                          "battlecard_shadow.png", "card_border.png",
                          "card_light.png", "card_small_border.png",
                          "handcard_shadow.png", "title.png", "title2.png",
                          "title_goldborder.png", "coloricon_bg.png",
                          "coloricon_border.png", "kindicon_bg.png",
                          "skill1_bg.png", "skill2_bg.png", "skill2_shadow.png",
                          "armor_bg.png", "hp_bg.png"):
                dest = f"ui/border/{name}"
            elif name == "crystal.png":
                dest = "ui/crystal.png"
            else:
                dest = f"ui/border/{name}"
        elif "/ui_icon/card/coloricon_" in key:
            dest = f"ui/faction/{name[len('coloricon_'):]}"
        elif "/ui_icon/card/kindicon_" in key:
            dest = f"ui/kind/{name[len('kindicon_'):]}"
        else:
            dest = f"ui/misc/{name}"

        target = out / dest
        target.parent.mkdir(parents=True, exist_ok=True)
        buf = io.BytesIO()
        sprite.save(buf, "PNG", optimize=True)
        target.write_bytes(buf.getvalue())
        count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", type=Path, default=DEFAULT_APK)
    parser.add_argument("--out", type=Path, default=OUT)
    parser.add_argument("--no-atlas", action="store_true", help="skip atlas slicing")
    args = parser.parse_args()

    if not args.apk.exists():
        print(f"ERROR: APK not found: {args.apk}", file=sys.stderr)
        return 1

    try:
        import PIL  # noqa: F401
    except ImportError:
        print("ERROR: Pillow is required (pip install Pillow)", file=sys.stderr)
        return 1

    args.out.mkdir(parents=True, exist_ok=True)
    print(f"Extracting art from {args.apk.name} -> {args.out.relative_to(ROOT)}")
    n = extract_flat_art(args.apk, args.out)
    print(f"  {n} standalone images extracted")
    if not args.no_atlas:
        m = slice_atlas(args.apk, args.out)
        print(f"  {m} atlas sprites sliced")
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
