#!/usr/bin/env python3
"""Regenerate the web data blob (game_data.json + the embedded GAME_DATA in the
HTML prototypes) from csv_data/all_card_config.csv without touching the CSV.

This is the same splice ``scripts/redesign_cards.py`` performs at the end of a
redesign pass, factored out so the art/`res_path` wiring can be refreshed on
its own. It imports the card→JSON builder directly from that script, so the two
can never drift apart.

Usage:
    python3 scripts/refresh_web_data.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from redesign_cards import build_web_data, read_cards  # noqa: E402

WEB_JSON = ROOT / "build" / "web" / "game_data.json"
HTML_TARGETS = [ROOT / "index.html", ROOT / "build" / "web" / "game.html"]
BLOB_RE = re.compile(r"const GAME_DATA = .*?;\n", re.DOTALL)


def main() -> int:
    rows, _header = read_cards()
    existing = json.loads(WEB_JSON.read_text(encoding="utf-8"))
    web = build_web_data(rows, existing.get("pve", {}))

    blob_text = json.dumps(web, ensure_ascii=False, separators=(",", ":"))
    WEB_JSON.write_text(blob_text, encoding="utf-8")
    print(f"Wrote {WEB_JSON.relative_to(ROOT)} ({len(web['cards'])} cards)")

    for target in HTML_TARGETS:
        html = target.read_text(encoding="utf-8")
        new_html, n = BLOB_RE.subn(
            f"const GAME_DATA = {blob_text};\n", html, count=1
        )
        if n != 1:
            print(f"ERROR: could not locate `const GAME_DATA` in {target}", file=sys.stderr)
            return 1
        target.write_text(new_html, encoding="utf-8")
        print(f"Spliced GAME_DATA into {target.relative_to(ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
