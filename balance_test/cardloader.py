"""Load real card data from csv_data/all_card_config.csv into the engine's
card-config shape, mirroring decrypted/manager/data_template.lua.

kind is stored as a bitmask built from CARD_KIND via SetBitNum (bit_lshift(1, flag)):
  war=2, fortune=4, balance=8, nature=16, chaos=32, all=64.
power_list entries carry name/value/target_type/type (target/type not used by
combat math, but preserved for completeness).
"""
import csv, os
from constants import CARD_KIND

POWER_CONFIG_NAMES = {"melee","ranged","magic","magic_aoe","shield","mshield","rally",
    "demoralize","antimagic","heal","heal_all","thrash","thorns","resonate","explode",
    "damage","damage_all","chance","crystal","reach","poison","disease","disease_all",
    "flying","counter","armor","antidote","disarm","doom","deathstrike","stoneskin",
    "revive","invincible","breaker","entangle","regenerate","reflect","boost","swipe",
    "aggro","stealth","swap","paint","trample","charge","critical","berserk","backstab",
    "stun","silence","unsummon","decoy","antiair","immunity","cleave","draft","destroy",
    "repair","opportunity","cautious","drain_crystal"}

def load_card_configs(csv_path):
    configs = {}
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ID = row.get("ID")
            if not ID or not ID.isdigit():
                continue
            # kind bitmask
            kind = 0
            kind_field = (row.get("kind") or "").strip()
            for w in kind_field.split():
                w = w.strip().lower()
                if w in CARD_KIND:
                    kind |= (1 << CARD_KIND[w])
            # powers
            power_list = []
            for i in (1, 2, 3):
                pn = (row.get("p%dn" % i) or "").strip().lower()
                pv = row.get("p%dv" % i)
                if pn:
                    power_list.append({
                        "name": pn,
                        "value": int(pv) if pv and str(pv).isdigit() else 0,
                        "target_type": "",
                        "type": "passive",
                    })
            configs[ID] = {
                "uid": ID,
                "level": int(row.get("level") or 1),
                "name": row.get("name") or ID,
                "type": (row.get("type") or "monster"),
                "group_id": int(row.get("group_id") or 0),
                "deck_limit": int(row.get("deck_limit") or 0),
                "kind": kind,
                "quality": row.get("quality") or "normal",
                "hp": int(row.get("hp") or 0),
                "flags": row.get("flags") or "",
                "cost": int(row.get("cost") or 0),
                "score": int(row.get("score") or 0),
                "power_list": power_list,
            }
    return configs

def main_attack(card):
    """Best attack value a creature contributes (melee/ranged/magic)."""
    for p in card["power_list"]:
        if p["name"] in ("melee", "ranged", "magic"):
            return p["value"]
    return 0

def monster_deck_limit(card):
    return int(card.get("deck_limit") or 0)
