#!/usr/bin/env python3
"""Canonical campaign plumbing without LuaJIT (mirrors tests/campaign_test.lua)."""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CANON = json.loads((ROOT / "content/campaign_data.json").read_text(encoding="utf-8"))
CSV = ROOT / "csv_data/all_card_config.csv"


def load_cards() -> dict[int, dict]:
    cards: dict[int, dict] = {}
    with CSV.open(newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    header = rows[0]
    for row in rows[3:]:
        if not row or row[0] == "ID":
            continue
        rec = dict(zip(header, row))
        try:
            cid = int(rec["ID"])
        except (KeyError, ValueError):
            continue
        rec["id"] = cid
        rec["level"] = int(rec.get("level") or 1)
        rec["flags"] = int(rec.get("flags") or 0)
        rec["cost"] = int(float(rec.get("cost") or 0))
        cards[cid] = rec
    return cards


def resolve_pool(pool: dict, cards: dict[int, dict]) -> list[int]:
    kinds = set(pool["kinds"])
    lv_min, lv_max, size = pool["lvMin"], pool["lvMax"], pool["size"]

    def collect(pred):
        return sorted(
            [
                c
                for c in cards.values()
                if c.get("type") == "monster" and c["flags"] == 1 and pred(c)
            ],
            key=lambda c: c["id"],
        )

    cand = collect(lambda c: c["kind"] in kinds and lv_min <= c["level"] <= lv_max)
    if len(cand) < 4:
        cand = collect(lambda c: c["kind"] in kinds and c["level"] <= lv_max)
    if len(cand) < 4:
        cand = collect(lambda c: c["kind"] in kinds)
    if not cand:
        return []
    return [cand[i % len(cand)]["id"] for i in range(size)]


def main() -> int:
    errors = []
    nodes = [n for r in CANON["regions"] for n in r["nodes"]]
    if len(CANON["regions"]) != 4:
        errors.append("expected 4 regions")
    if len(nodes) != 19:
        errors.append(f"expected 19 nodes, got {len(nodes)}")
    w1 = next(n for n in nodes if n["id"] == "w1")
    if w1["name"] != "Forest Trail" or w1["hp"] != 14:
        errors.append("w1 identity mismatch")
    starter = CANON["starterCollection"]
    if len(starter) != 12:
        errors.append(f"starter collection should be 12 cards (6+6), got {len(starter)}")
    cards = load_cards()
    mons = [i for i in starter if cards.get(i, {}).get("type") == "monster"]
    equips = [i for i in starter if cards.get(i, {}).get("type") != "monster"]
    if len(mons) != 6 or len(equips) != 6:
        errors.append(f"starter should be 6 monsters + 6 equipment (got {len(mons)}+{len(equips)})")
    ids = resolve_pool(w1["pool"], cards)
    if len(ids) != 9:
        errors.append(f"w1 pool size {len(ids)}")
    for i in ids:
        c = cards[i]
        if c["kind"] != "nature" or c["type"] != "monster":
            errors.append(f"non-nature pool card {i}")
            break
    if errors:
        print("CAMPAIGN DATA TEST FAILED")
        for e in errors:
            print(" -", e)
        return 1
    print("CAMPAIGN DATA TEST PASSED")
    print(f"  w1 pool ids={ids}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
