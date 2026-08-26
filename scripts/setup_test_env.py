#!/usr/bin/env python3
"""Build the headless test fixtures used by tests/*.lua.

The test suites load the REAL game Lua modules, which on the device live
XXTEA-encrypted inside the APK (assets/src.mu, assets/common.mu) and which
the tests cannot read directly.  This script regenerates the fixtures from
the APK:

    decrypted/   game Lua tree (src.mu + common.mu decrypted), with the
                 patched files from the repo's src/ overlaid on top so the
                 tests exercise the CURRENT source, not the APK's copy
    csv_plain/   plain-text copies of csv_data/*.csv, consumed by the
                 tests' aandm.loadConfig stub (the device reads these CSVs
                 through the native aandm module from data.mu)

Both directories are gitignored build artifacts; delete them freely, then
re-run this script to regenerate.

Usage:
    python3 scripts/setup_test_env.py [path/to/English_offline.apk]

The default source APK is ./English_offline.apk (the output of
build_and_verify.py).  The tests then run under LuaJIT 2.1 from the repo
root:

    luajit tests/sim_test.lua
    luajit tests/integration_test.lua
    luajit tests/guide_battle_test.lua
"""

import io
import shutil
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import xxtea_decrypt as xx  # noqa: E402
from archived_sources import is_archived  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
DECRYPTED = REPO_ROOT / "decrypted"
CSV_PLAIN = REPO_ROOT / "csv_plain"
MAGIC = b"gclR3cu9"

def decrypt_mu_entry(raw: bytes, rel_name: str) -> str:
    if raw[:8] != MAGIC:
        raise RuntimeError("bad magic on %r: %r" % (rel_name, raw[:8]))
    return xx.decrypt_body(raw[8:])


def extract_mu(apk_zip: zipfile.ZipFile, mu_name: str, strip: str) -> None:
    """Decrypt every entry of an inner .mu zip into DECRYPTED."""
    data = apk_zip.read(mu_name)
    with zipfile.ZipFile(io.BytesIO(data)) as inner:
        for name in inner.namelist():
            if name.endswith("/"):
                continue
            rel = name[len(strip):].lstrip("/")
            if not rel:
                continue
            # archived modules stay out of the fixtures, exactly as they stay
            # out of the shipped APK (see scripts/archived_sources.py)
            if is_archived(rel):
                continue
            raw = inner.read(name)
            try:
                body = decrypt_mu_entry(raw, name)
            except RuntimeError:
                # non-encrypted payloads (protobuf .pb files etc.) - copy raw
                body = raw
            dst = DECRYPTED / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if isinstance(body, str):
                dst.write_text(body, encoding="utf-8", newline="")
            else:
                dst.write_bytes(body)
    print("extracted %s -> %s/" % (mu_name, DECRYPTED))


def overlay_repo_src() -> None:
    """Overlay the patched repo sources onto the decrypted tree.

    The repo's src/ only tracks the files that were patched for the offline
    build, so overlaying all of it is exactly right: patched files replace
    their APK counterparts, and everything else comes from the APK.
    """
    src = REPO_ROOT / "src"
    overlaid = 0
    for path in src.rglob("*"):
        if not path.is_file():
            continue
        dst = DECRYPTED / path.relative_to(src)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, dst)
        overlaid += 1
    print("overlaid %d repo src/ files onto %s/" % (overlaid, DECRYPTED))


def copy_csv_plain() -> None:
    """Copy csv_data/*.csv to csv_plain/ (the tests' aandm.loadConfig stub)."""
    csv_dir = REPO_ROOT / "csv_data"
    if CSV_PLAIN.exists():
        shutil.rmtree(CSV_PLAIN)
    CSV_PLAIN.mkdir(parents=True)
    n = 0
    for csv in sorted(csv_dir.glob("*.csv")):
        shutil.copyfile(csv, CSV_PLAIN / csv.name)
        n += 1
    print("copied %d CSVs -> %s/" % (n, CSV_PLAIN))


def main() -> None:
    apk_path = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO_ROOT / "English_offline.apk"
    if not apk_path.exists():
        sys.exit(
            "APK not found: %s\n"
            "Run scripts/build_and_verify.py first (its output lands at "
            "English_offline.apk in the repo root), or pass an APK path: "
            "python3 scripts/setup_test_env.py /path/to/apk" % apk_path
        )
    if DECRYPTED.exists():
        shutil.rmtree(DECRYPTED)
    DECRYPTED.mkdir(parents=True)

    with zipfile.ZipFile(apk_path) as apk:
        extract_mu(apk, "assets/src.mu", "src/")
        # common.mu entries are already common/...-prefixed and the tests
        # require "common.constants" etc., so keep the prefix
        extract_mu(apk, "assets/common.mu", "")
    overlay_repo_src()
    copy_csv_plain()
    print("test fixtures ready; run: luajit tests/guide_battle_test.lua")


if __name__ == "__main__":
    main()
