#!/usr/bin/env python3
"""Rebuild the offline APK directly from a known-good base APK.

This small, host-independent pipeline exists because the original Windows-only
apktool workspace is not included in the repository.  It patches Lua files in
``assets/src.mu``, re-signs the result, and leaves the original APK untouched.

Usage:
  python3 scripts/rebuild_from_apk.py English.apk build/English_offline.apk

Requirements: Python 3, Java JDK (keytool and jarsigner).  The first run makes
an ``offline.keystore`` in build/.  Android considers that a different signer,
so uninstall any previously installed original build before installing output.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from xxtea_decrypt import decrypt_file, encrypt_file


def tool(name: str) -> str:
    value = shutil.which(name)
    if not value:
        raise RuntimeError(f"Required tool '{name}' was not found on PATH. Install a Java JDK.")
    return value


def patched_sources() -> dict[str, Path]:
    files = {}
    for path in (ROOT / "src").rglob("*.lua"):
        # Archive paths are rooted at src/, while local files are rooted at repo.
        files[str(path.relative_to(ROOT)).replace("\\", "/")] = path
    return files


def build_src_mu(base_data: bytes, destination: Path) -> None:
    source_files = patched_sources()
    with zipfile.ZipFile(__import__("io").BytesIO(base_data), "r") as old, \
         zipfile.ZipFile(destination, "w") as new:
        seen = set()
        for info in old.infolist():
            data = old.read(info.filename)
            if info.filename in source_files:
                data = encrypt_file(source_files[info.filename].read_bytes(), with_magic=True)
            copied = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            copied.compress_type = info.compress_type
            copied.external_attr = info.external_attr
            copied.create_system = info.create_system
            new.writestr(copied, data)
            seen.add(info.filename)
        for arcname, source in source_files.items():
            if arcname not in seen:
                new.writestr(arcname, encrypt_file(source.read_bytes(), with_magic=True), zipfile.ZIP_DEFLATED)


def make_keystore(path: Path) -> None:
    subprocess.run([
        tool("keytool"), "-genkeypair", "-keystore", str(path), "-alias", "offline",
        "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
        "-storepass", "android", "-keypass", "android",
        "-dname", "CN=Monster Battle Offline, OU=Offline, O=Offline, C=US",
    ], check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base_apk", type=Path, help="Unmodified or previously working APK")
    parser.add_argument("output_apk", type=Path, help="Path for the newly signed APK")
    args = parser.parse_args()
    if not args.base_apk.is_file():
        parser.error(f"Base APK not found: {args.base_apk}")
    tool("jarsigner")
    args.output_apk.parent.mkdir(parents=True, exist_ok=True)
    keystore = ROOT / "build" / "offline.keystore"
    if not keystore.exists():
        make_keystore(keystore)

    with zipfile.ZipFile(args.base_apk) as apk:
        if "assets/src.mu" not in apk.namelist():
            raise RuntimeError("Base APK has no assets/src.mu")
        mu = apk.read("assets/src.mu")

    with tempfile.TemporaryDirectory(prefix="monster-battle-") as tmpdir:
        new_mu = Path(tmpdir) / "src.mu"
        unsigned = Path(tmpdir) / "unsigned.apk"
        build_src_mu(mu, new_mu)
        with zipfile.ZipFile(args.base_apk) as old, zipfile.ZipFile(unsigned, "w") as new:
            for info in old.infolist():
                if info.filename.startswith("META-INF/"):
                    continue
                data = new_mu.read_bytes() if info.filename == "assets/src.mu" else old.read(info.filename)
                copied = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                copied.compress_type = info.compress_type
                copied.external_attr = info.external_attr
                copied.create_system = info.create_system
                new.writestr(copied, data)
        subprocess.run([
            tool("jarsigner"), "-keystore", str(keystore), "-storepass", "android",
            "-keypass", "android", "-sigalg", "SHA256withRSA", "-digestalg", "SHA-256",
            "-signedjar", str(args.output_apk), str(unsigned), "offline",
        ], check=True)

    with zipfile.ZipFile(args.output_apk) as check:
        assert "assets/src.mu" in check.namelist()
    print(f"Built {args.output_apk} ({args.output_apk.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
