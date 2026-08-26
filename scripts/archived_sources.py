#!/usr/bin/env python3
"""Game Lua modules that are archived: kept in the repo under archive/ for
reference but deliberately excluded from every shipped build.

Each entry is a path relative to the game Lua root (the layout inside
assets/src.mu, decrypted/ and web/dist/game/).  The three pipelines that
assemble a build all consult ARCHIVED_SOURCES so an archived module cannot
come back by accident:

  * scripts/rebuild_offline_apk.py  — skips it when rebuilding assets/src.mu
  * scripts/setup_test_env.py       — skips it when building decrypted/
  * web/scripts/prepare_web.py      — skips it when copying into web/public

Restoring a module: delete its entry here (and, if it was moved out of the
game tree, copy the file back from archive/ into src/).

Nothing in this list may be required by live code.  tests/static_checks.py
enforces that.
"""
from __future__ import annotations

# ---------------------------------------------------------------------------
# Gerbip Tide (a.k.a. "Gerbil Tide", play_id 1001) — the stock daily PvE
# mission list.  Archived: this build's only destination is The Shadow Road
# campaign, and the mode's daily-reset counters and mirrored system decks were
# server-side.  Source kept in archive/gerbip_tide/.
#
# pve_cardgroup_panel is the mirrored-deck viewer and is required only by the
# Gerbip Tide panel, so it goes with it.  pve_card_detail_panel stays live
# (modules/pvp/periphery_match_panel.lua uses it) and so does
# modules/common/pve_material_item.lua (battle_result_reward_panel.lua).
# ---------------------------------------------------------------------------
GERBIP_TIDE = [
    "modules/pve/pve_gerbil_tide_panel.lua",
    "modules/pve/pve_cardgroup_panel.lua",
]

ARCHIVED_SOURCES: set[str] = set(GERBIP_TIDE)


def is_archived(rel_path: str) -> bool:
    """rel_path: a game-Lua-relative path, '/' or '\\' separated.

    Accepts the bare game-Lua path (decrypted/, web/dist/game/) and the
    assets/src.mu form, which is the same path with a leading "src/" (that is
    how the entries are named inside the .mu zip, and how the repo's src/
    overlay is keyed).
    """
    norm = str(rel_path).replace("\\", "/").lstrip("/")
    if norm.startswith("src/"):
        norm = norm[len("src/"):]
    return norm in ARCHIVED_SOURCES


if __name__ == "__main__":
    for name in sorted(ARCHIVED_SOURCES):
        print(name)
