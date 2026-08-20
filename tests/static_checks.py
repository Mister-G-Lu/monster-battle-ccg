#!/usr/bin/env python3
"""Fast repository checks that do not require LuaJIT or Android tooling."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHINESE_RE = re.compile(r"[\u4e00-\u9fff]")
ALLOWED_CHINESE_FILES = {
    Path("csv_data/client_lang_zh-CN.csv"),
    Path("csv_data/client_lang_zh-TW.csv"),
}
SKIP_SUFFIXES = {".apk", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".wav", ".mp3"}


def check_no_chinese_artifacts() -> list[str]:
    errors: list[str] = []
    for path in ROOT.rglob("*"):
        rel = path.relative_to(ROOT)
        if ".git" in rel.parts or not path.is_file():
            continue
        if rel in ALLOWED_CHINESE_FILES or path.suffix.lower() in SKIP_SUFFIXES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if CHINESE_RE.search(text):
            errors.append(f"unexpected Chinese characters in {rel}")
    return errors


def check_text_loader_forces_english() -> list[str]:
    text = (ROOT / "src/manager/text_loader.lua").read_text(encoding="utf-8")
    if 'local ENGLISH_LANG = "en-US"' not in text or "lang = ENGLISH_LANG" not in text:
        return ["text_loader.lua must force the English CSV in this offline build"]
    return []


def check_web_data_marks_special_cards() -> list[str]:
    data = json.loads((ROOT / "build/web/game_data.json").read_text(encoding="utf-8"))
    errors: list[str] = []
    for cid in ("119001", "149018", "21901"):
        card = data["cards"].get(cid)
        if not card:
            errors.append(f"special card {cid} missing from web data")
        elif card.get("flags") != 0:
            errors.append(f"special card {cid} must remain flags=0")
    html = (ROOT / "build/web/game.html").read_text(encoding="utf-8")
    if "c.flags === 1" not in html:
        errors.append("web prototype random/starter pools must filter to flags=1 collectible cards")
    if "card.attack || 1" not in html and "attacker.attack || 1" not in html:
        errors.append("web prototype should use attack values, not current HP as damage")
    return errors


def check_campaign_generators() -> list[str]:
    """PR F: checked-in campaign/web blobs must match the generators."""
    errors: list[str] = []
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts/refresh_campaign_data.py"), "--verify"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        errors.append("refresh_campaign_data.py --verify failed")
        errors.append(result.stdout)
        errors.append(result.stderr)
    html_a = (ROOT / "index.html").read_bytes()
    html_b = (ROOT / "build/web/game.html").read_bytes()
    if html_a != html_b:
        errors.append("index.html and build/web/game.html must stay byte-identical")
    return errors


def check_balance_audit() -> list[str]:
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts/analyze_balance.py"), "--fail-on-critical"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        return ["balance audit found collectible critical outliers", result.stdout, result.stderr]
    return []


def main() -> int:
    errors: list[str] = []
    result = subprocess.run(
        [sys.executable, str(ROOT / "tests/campaign_data_test.py")],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    extra = []
    if result.returncode != 0:
        extra.append("campaign_data_test.py failed")
        extra.append(result.stdout)
        extra.append(result.stderr)

    for check in (
        check_no_chinese_artifacts,
        check_text_loader_forces_english,
        check_web_data_marks_special_cards,
        check_campaign_generators,
        check_balance_audit,
    ):
        errors.extend(check())
    errors.extend(extra)
    if errors:
        print("STATIC CHECKS FAILED")
        for err in errors:
            print(" -", err)
        return 1
    print("STATIC CHECKS PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
