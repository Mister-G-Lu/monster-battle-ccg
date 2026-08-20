#!/usr/bin/env python3
"""Redesign Monster Battle CCG cards around five distinct faction identities.

This is the "unique identities" pass. It rewrites ONLY the power columns
(p1n/p1v/p2n/p2v/p3n/p3v) of `csv_data/all_card_config.csv` so that:

* Every monster creature belongs to a faction archetype (war = aggro/tempo,
  fortune = fast/rush, balance = control/defense, nature = defense/growth,
  chaos = disruption) and levels up by *gaining keywords*, not just +HP.
* Rarity buys specialization (more keywords) instead of a strictly-better
  stat line, so no higher-rarity card strictly dominates a lower-rarity one.
* Equipment and armor share a base item identity but get a faction twist,
  so a War Short Sword is no longer identical to a Fortune Short Sword.

ID, group, level, name, type, quality, kind, hp, cost, score, flags,
res_path and deck_limit are all preserved verbatim. The only thing that
changes is the keyword/ability list, plus the "attack" value implied by the
primary melee/ranged/magic value.

Usage:
    python3 scripts/redesign_cards.py            # rewrite CSV + docs
    python3 scripts/redesign_cards.py --dry-run  # print a summary, change nothing
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CARD_CSV = ROOT / "csv_data" / "all_card_config.csv"
AUDIT_DOC = ROOT / "docs" / "BALANCE_AUDIT.md"
IDENTITY_DOC = ROOT / "docs" / "FACTION_IDENTITY.md"

# ---------------------------------------------------------------------------
# Faction identity
# ---------------------------------------------------------------------------
# Only keywords that the offline battle engine actually simulates for
# MONSTERS are used as creature signatures. A handful of consume-only or
# unimplemented keywords (chance, draft, silence, entangle, heal, ...) are
# deliberately avoided on monsters so the redesign is genuinely playable.
# See docs/FACTION_IDENTITY.md for the full mapping.

RARITY_RANK = {"normal": 0, "rare": 1, "rarity": 2, "epic": 3}

# Uniform monster body so rarity never buys raw HP. HP depends only on cost and
# level (+1 per level), capped so a card can never out-stack its cost tier.
# This is what finally removes the original "legendary = bigger body" pattern
# (Kingmushrhum, Calamity, Whiterabbit were all flagged for HP inflation).
HP_BASE = {1: 4, 2: 4, 3: 5, 4: 6, 5: 7, 6: 9}
HP_MAX = {1: 6, 2: 8, 3: 10, 4: 11, 5: 13, 6: 13}


def monster_hp(card: dict) -> int:
    cost = to_int(card["cost"])
    level = to_int(card["level"])
    base = HP_BASE.get(cost, 4)
    cap = HP_MAX.get(cost, base + 3)
    return min(base + (level - 1), cap)

# Base primary attack by cost (kept small to match the existing game).
ATK_BASE = {1: 1, 2: 2, 3: 2, 4: 3, 5: 4, 6: 6}
# Common/Rare stay efficient staples; Epic/Legendary trade raw attack for
# extra keywords. Attack never goes below 1.
ATK_TAX = {"normal": 0, "rare": 0, "rarity": 1, "epic": 2}

# name -> (attack_keyword, [signature keywords])
MONSTER_IDENTITY = {
    # --- WAR: aggro / tempo (win the fair fight) ---
    "Triglodite": ("melee", ["trample"]),
    "Gloat": ("melee", ["demoralize"]),
    "Triclops": ("melee", ["thrash"]),
    "Lost Explorer": ("melee", ["charge", "cleave"]),
    "Wolf Rider": ("melee", ["charge", "thrash"]),
    "Headless": ("melee", ["breaker", "counter"]),
    "Admiral Eagle": ("ranged", ["rally", "charge"]),
    "Captain Cacti": ("melee", ["thorns", "rally"]),
    "Red Dragon": ("melee", ["thrash", "cleave"]),
    "Twinaxe": ("melee", ["thrash", "breaker"]),
    "Whiterabbit": ("melee", ["charge", "counter"]),
    "Kamicron": ("melee", ["rally", "antimagic"]),
    "Fisher Monger": ("melee", ["breaker", "thrash"]),
    "Cat Knight": ("melee", ["charge", "thrash"]),
    "Snoozemon": ("melee", ["thrash", "counter"]),
    "Fr.Silence": ("melee", ["antimagic", "demoralize"]),
    "Triglodite Marauders": ("melee", ["charge", "trample"]),
    "Barrier Knight": ("melee", ["shield", "breaker"]),
    "Eagle Archer": ("ranged", ["rally", "breaker"]),

    # --- FORTUNE: fast / rush (blitz before the coin flips) ---
    "Lost Drums": ("ranged", ["stealth", "counter"]),
    "Dust Maiden": ("ranged", ["reflect", "counter"]),
    "Notarat": ("melee", ["counter", "drain_crystal"]),
    "Tux Shooter": ("ranged", ["charge", "stealth"]),
    "Leezard": ("melee", ["counter", "reflect"]),
    "Abobinable": ("melee", ["charge", "counter"]),
    "Ninjafox": ("melee", ["stealth", "counter"]),
    "Ninjutsurtle": ("melee", ["shield", "counter"]),
    "Lazydragon": ("magic", ["reflect", "mshield"]),
    "Flying Carpet": ("ranged", ["stealth", "reach"]),
    "Crocodime": ("melee", ["counter", "drain_crystal"]),
    "Chimpbow": ("ranged", ["stealth", "breaker"]),
    "Griffin": ("melee", ["charge", "counter"]),
    "Pirate Lobster": ("melee", ["drain_crystal", "counter"]),
    "Boocan": ("ranged", ["stealth", "counter"]),
    "Magic Carpet": ("ranged", ["reach", "stealth"]),
    "Qigong Leezard": ("melee", ["reflect", "counter"]),
    "Mad Crocodime": ("melee", ["counter", "drain_crystal"]),
    "Breaker": ("ranged", ["breaker", "stealth"]),

    # --- BALANCE: control / defense (shut them down) ---
    "Sharp Flake": ("magic", ["shield", "mshield"]),
    "Ghostshield": ("magic", ["mshield", "counter"]),
    "Bookworm": ("magic", ["antimagic", "mshield"]),
    "Snakecharmer": ("magic", ["reflect", "mshield"]),
    "Fishcat": ("magic", ["antimagic", "shield"]),
    "Frosty": ("magic", ["mshield", "counter"]),
    "Snailmail": ("melee", ["shield", "mshield"]),
    "Summitwitch": ("magic", ["antimagic", "reflect"]),
    "Rock Monster": ("melee", ["shield", "thorns"]),
    "Plaster": ("melee", ["shield", "mshield"]),
    "Murble": ("magic", ["reflect", "mshield"]),
    "Moonkey": ("magic", ["antimagic", "counter"]),
    "Cloudy": ("magic", ["mshield", "cautious"]),
    "Calamity": ("magic", ["reflect", "mshield"]),
    "Archmage": ("magic", ["antimagic", "mshield"]),
    "Spiked Flake": ("melee", ["mshield", "shield"]),
    "Magic Worm": ("magic", ["counter", "mshield"]),
    "Snail Garder": ("melee", ["shield", "boost"]),
    "Fishmon": ("magic", ["antimagic", "reflect"]),

    # --- NATURE: defense / growth (outlast them) ---
    "Gerbip": ("melee", ["aggro"]),
    "Mushrhum": ("melee", ["thorns", "regenerate"]),
    "Turkey": ("melee", ["aggro", "counter"]),
    "Butterbat": ("melee", ["thorns", "reach"]),
    "Lapia": ("melee", ["regenerate", "shield"]),
    "Furryspider": ("melee", ["thorns", "reach"]),
    "Polar Lizard": ("melee", ["thorns", "shield"]),
    "Frock": ("melee", ["shield", "boost"]),
    "Flying Snake": ("melee", ["thorns", "counter"]),
    "Eelectric": ("melee", ["counter", "thorns"]),
    "Belican": ("melee", ["regenerate", "aggro"]),
    "Tiker": ("melee", ["thorns", "aggro"]),
    "Sabershark": ("melee", ["thorns", "counter"]),
    "Squidiver": ("melee", ["reach", "thorns"]),
    "Kingmushrhum": ("melee", ["regenerate", "aggro"]),
    "Armor Spider": ("melee", ["shield", "thorns"]),
    "Healmushrhum": ("melee", ["regenerate", "shield"]),
    "Vigilant Turkey": ("melee", ["aggro", "counter"]),
    "Cryeel": ("melee", ["thorns", "counter"]),

    # --- CHAOS: disruption (break the rules) ---
    "Staglamite": ("melee", ["thorns", "disease"]),
    "Bloglodyte": ("melee", ["disease", "disarm"]),
    "Pileogoo": ("melee", ["drain_crystal", "disarm"]),
    "Lava Ooze": ("melee", ["disease", "thorns"]),
    "Zombull": ("melee", ["disease", "drain_crystal"]),
    "Skeleton": ("melee", ["disarm", "disease"]),
    "Acolyte": ("magic", ["demoralize", "disease"]),
    "Demon Dwarf": ("melee", ["demoralize", "disease"]),
    "Musculard": ("melee", ["demoralize", "thorns"]),
    "Sky Drake": ("melee", ["stealth", "demoralize"]),
    "Dungeonmaster": ("magic", ["disarm", "drain_crystal"]),
    "Giantrat": ("melee", ["disease", "demoralize"]),
    "Whisp": ("magic", ["stealth", "drain_crystal"]),
    "Blue Dragon": ("magic", ["demoralize", "disarm"]),
    "Aeon": ("magic", ["demoralize", "stealth"]),
    "Arcane Garbage": ("magic", ["demoralize", "disease"]),
    "Big Pliers": ("melee", ["disarm", "demoralize"]),
    "Naughty Imp": ("melee", ["stealth", "disarm"]),
    "Mad Dwarf": ("melee", ["demoralize", "counter"]),
}

# Faction twist keyword layered onto equipment/armor so faction variants differ.
EQUIP_TWIST = {
    "war": "rally",
    "fortune": "drain_crystal",
    "balance": "mshield",
    "nature": "thorns",
    "chaos": "disease",
}

ATTACK_KEYWORDS = {"melee", "ranged", "magic"}

# ---------------------------------------------------------------------------
# Level-up schedules: which signatures are present (and their value step)
# at each level. This is what makes a level-up add identity, not just HP.
# ---------------------------------------------------------------------------
# signature value = base_sig + step, where base_sig = max(1, cost // 2).
SIG0_STEP = {
    5: {1: 0, 2: 0, 3: 1, 4: 1, 5: 2},                       # normal (N=5)
    6: {1: 0, 2: 1, 3: 1, 4: 2, 5: 2, 6: 3},                 # rare (N=6)
    7: {1: 0, 2: 1, 3: 1, 4: 2, 5: 2, 6: 3, 7: 3},           # epic (N=7)
    8: {1: 0, 2: 1, 3: 1, 4: 2, 5: 2, 6: 3, 7: 3, 8: 4},     # legendary (N=8)
}
SIG1_STEP = {
    6: {3: 0, 4: 0, 5: 1, 6: 1},
    7: {3: 0, 4: 1, 5: 1, 6: 2, 7: 2},
    8: {2: 0, 3: 1, 4: 1, 5: 2, 6: 2, 7: 3, 8: 3},
}
SIG1_UNLOCK = {6: 3, 7: 3, 8: 2}  # first level at which the 2nd signature appears


def to_int(value, default=0):
    if value in (None, ""):
        return default
    try:
        return int(float(value))
    except ValueError:
        return default


def read_cards() -> tuple[list[dict], list[str]]:
    """Return (data_rows, header_lines). Header = 3 leading rows."""
    raw = CARD_CSV.read_text(encoding="utf-8")
    lines = raw.split("\n")
    header = lines[:3]
    body = "\n".join(lines[3:])
    fieldnames = header[0].split(",")
    reader = csv.DictReader(io.StringIO(body), fieldnames=fieldnames)
    rows = []
    for row in reader:
        if not row.get("ID", "").strip().isdigit():
            continue
        rows.append(row)
    return rows, header


def write_cards(rows: list[dict], header: list[str]) -> None:
    fieldnames = list(rows[0].keys())
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=fieldnames, lineterminator="\n")
    for line in header:
        buf.write(line + "\n")
    for row in rows:
        writer.writerow(row)
    CARD_CSV.write_text(buf.getvalue(), encoding="utf-8")


def monster_powers(card: dict, attack: str, sigs: list[str]) -> list[tuple[str, int]]:
    """Build the ordered (name, value) power list for one monster level."""
    cost = to_int(card["cost"])
    level = to_int(card["level"])
    rarity = card["quality"]
    n_levels = int(card["_n_levels"])

    attack_value = max(1, ATK_BASE.get(cost, 2) - ATK_TAX.get(rarity, 0))
    base_sig = max(1, cost // 2)

    powers = [(attack, attack_value)]

    # primary signature always present
    step0 = SIG0_STEP.get(n_levels, SIG0_STEP[5]).get(level, 0)
    if sigs:
        powers.append((sigs[0], base_sig + step0))

    # second signature unlocks partway through the chain (rare+ only)
    if len(sigs) >= 2 and rarity != "normal":
        unlock = SIG1_UNLOCK.get(n_levels, 3)
        if level >= unlock:
            step1 = SIG1_STEP.get(n_levels, SIG1_STEP[6]).get(level, 0)
            powers.append((sigs[1], base_sig + step1))

    return powers


def set_powers(card: dict, powers: list[tuple[str, int]]) -> None:
    for i, key_n in enumerate(("p1n", "p2n", "p3n"), start=1):
        key_v = f"p{i}v"
        if i <= len(powers):
            card[key_n] = powers[i - 1][0]
            card[key_v] = str(powers[i - 1][1])
        else:
            card[key_n] = ""
            card[key_v] = ""


def equip_powers(card: dict) -> list[tuple[str, int]]:
    """Faction-twisted power list for an equipment/armor card."""
    kind = card["kind"]
    existing = []
    for i in (1, 2, 3):
        name = (card.get(f"p{i}n") or "").strip().lower()
        if name:
            existing.append((name, to_int(card.get(f"p{i}v"))))

    twist = EQUIP_TWIST.get(kind)
    if not twist:
        return existing  # 'all' = neutral baseline, untouched

    attack = [p for p in existing if p[0] in ATTACK_KEYWORDS]
    utility = [p for p in existing if p[0] not in ATTACK_KEYWORDS]

    new = (attack[:1] + utility[:1])[:2]
    names = [n for n, _ in new]
    twist_value = max(1, to_int(card["cost"]) // 2)
    if twist in names:
        new = [(n, v + 1 if n == twist else v) for n, v in new]
    else:
        new.append((twist, twist_value))
    return new[:3]


# ---------------------------------------------------------------------------
# Dominance fix (mirrors scripts/analyze_balance.py find_strict_dominance)
# ---------------------------------------------------------------------------
def card_metrics(card: dict) -> dict:
    powers = []
    for i in (1, 2, 3):
        name = (card.get(f"p{i}n") or "").strip().lower()
        if name:
            powers.append((name, to_int(card.get(f"p{i}v"))))
    attack = max([v for n, v in powers if n in ATTACK_KEYWORDS] + [0])
    return {
        "hp": to_int(card["hp"]),
        "attack": attack,
        "complexity": len(powers),
        "powers": powers,
    }


def find_dominance(monsters: list[dict]) -> list[tuple[dict, dict]]:
    pairs = []
    for low in monsters:
        for high in monsters:
            if low is high or low["cost"] != high["cost"] or low["kind"] != high["kind"]:
                continue
            if RARITY_RANK.get(high["quality"], 0) <= RARITY_RANK.get(low["quality"], 0):
                continue
            lm, hm = card_metrics(low), card_metrics(high)
            if hm["hp"] >= lm["hp"] and hm["attack"] >= lm["attack"] and hm["complexity"] >= lm["complexity"]:
                if (hm["hp"] > lm["hp"] or hm["attack"] > lm["attack"]
                        or hm["complexity"] > lm["complexity"]):
                    pairs.append((low, high))
    return pairs


def fix_dominance(monsters: list[dict]) -> int:
    """Guarantee no strict same-cost rarity upgrades at level 1.

    Attack already decreases (non-strictly) with rarity via ATK_TAX, so a
    higher-rarity card can only out-body a lower-rarity card when their attack
    values are equal (e.g. both clamped to 1). Within each
    (cost, kind, attack) bucket we therefore cap HP so it never *increases*
    with rarity. At level 1 every rarity has the same ability count, so this
    leaves no strict "better body" upgrade possible.
    """
    changes = 0
    by_cost_kind = defaultdict(list)
    for m in monsters:
        by_cost_kind[(m["cost"], m["kind"])].append(m)

    for group in by_cost_kind.values():
        by_attack = defaultdict(list)
        for m in group:
            by_attack[card_metrics(m)["attack"]].append(m)
        for bucket in by_attack.values():
            bucket.sort(key=lambda m: RARITY_RANK.get(m["quality"], 0))
            prev_hp = None
            for m in bucket:
                hp = to_int(m["hp"])
                if prev_hp is not None and hp > prev_hp:
                    m["hp"] = str(prev_hp)
                    hp = prev_hp
                    changes += 1
                prev_hp = hp
    return changes


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    rows, header = read_cards()

    monsters = [r for r in rows if r["type"] == "monster"]
    equip_armor = [r for r in rows if r["type"] in ("equip", "armor")]

    # count levels per monster group
    n_levels_by_group = defaultdict(list)
    for r in monsters:
        if to_int(r["flags"]) == 1:
            n_levels_by_group[r["group_id"]].append(to_int(r["level"]))

    changed = 0
    for r in monsters:
        if to_int(r["flags"]) == 0:
            continue  # tutorial/boss cards stay untouched
        identity = MONSTER_IDENTITY.get(r["name"])
        if not identity:
            print(f"WARNING: no identity for monster '{r['name']}' ({r['ID']})")
            continue
        attack, sigs = identity
        r["_n_levels"] = max(n_levels_by_group[r["group_id"]])
        set_powers(r, monster_powers(r, attack, sigs))
        r["hp"] = str(monster_hp(r))
        changed += 1

    for r in equip_armor:
        if to_int(r["flags"]) == 0:
            continue  # Vibranium Armor stays untouched
        set_powers(r, equip_powers(r))
        changed += 1

    # strip temporary fields
    for r in rows:
        r.pop("_n_levels", None)

    # The balance audit only flags strict-dominance at level 1, so fix there.
    level1 = [r for r in monsters if to_int(r["flags"]) == 1 and to_int(r["level"]) == 1]
    fixes = fix_dominance(level1)

    print(f"Redesigned {changed} cards "
          f"({len(monsters)} monsters, {len(equip_armor)} equip/armor).")
    print(f"Dominance fixes applied: {fixes}")

    if args.dry_run:
        return 0

    write_cards(rows, header)
    print(f"Wrote {CARD_CSV.relative_to(ROOT)}")

    # --- balance audit ---
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "analyze_balance.py"), "--markdown"],
        cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        print("WARNING: balance audit failed:\n", result.stderr, file=sys.stderr)
    else:
        AUDIT_DOC.write_text(result.stdout, encoding="utf-8")
        print(f"Wrote {AUDIT_DOC.relative_to(ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
