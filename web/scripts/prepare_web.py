#!/usr/bin/env python3
"""Copy the decrypted Lua engine + plain CSVs into web/public so the Vite dev
server can serve them, and generate the manifest the loader fetches.

Run automatically by `npm run dev` / `npm run build` (see package.json).
"""
from __future__ import annotations
import json
import shutil
import subprocess
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1]          # web/
ROOT = WEB.parent                                  # repo root
DECRYPTED = ROOT / "decrypted"
CSV_PLAIN = ROOT / "csv_plain"
PUBLIC = WEB / "public"
GAME_OUT = PUBLIC / "game"
CSV_OUT = PUBLIC / "csv"
BRIDGE = WEB / "lua" / "web_bridge.lua"


def ensure_decrypted() -> None:
    if DECRYPTED.exists() and CSV_PLAIN.exists():
        return
    print("decrypted/ or csv_plain/ missing — running setup_test_env.py …")
    subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "setup_test_env.py")],
        cwd=ROOT, check=True,
    )


def copy_tree(src: Path, dst: Path, exts: set[str]) -> list[str]:
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True, exist_ok=True)
    rels: list[str] = []
    for p in sorted(src.rglob("*")):
        if p.is_file() and p.suffix in exts:
            rel = p.relative_to(src)
            out = dst / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, out)
            rels.append(str(rel).replace("\\", "/"))
    return rels


def main() -> int:
    ensure_decrypted()
    PUBLIC.mkdir(parents=True, exist_ok=True)

    lua_files = copy_tree(DECRYPTED, GAME_OUT, {".lua"})
    csv_files = copy_tree(CSV_PLAIN, CSV_OUT, {".csv"})

    # the UI-facing bridge is served at the web root (fetched as /web_bridge.lua)
    shutil.copy2(BRIDGE, PUBLIC / "web_bridge.lua")

    manifest = {"lua": lua_files, "csv": csv_files}
    (PUBLIC / "game-manifest.json").write_text(json.dumps(manifest, indent=0))

    print(f"prepared web assets: {len(lua_files)} lua, {len(csv_files)} csv")
    print(f"  -> {GAME_OUT}")
    print(f"  -> {CSV_OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
