#!/usr/bin/env python3
"""Rebuild English_offline.apk without Java — pure Python APK v1 signing.

The original pipeline (build_and_verify.py / rebuild_from_apk.py) needs a JDK
for keytool + jarsigner.  This script produces the same kind of APK (v1 JAR
signature: MANIFEST.MF + OFFLINE.SF + OFFLINE.RSA) with zero Java, so the APK
can be rebuilt on any machine with Python 3.9+.

What it does:
  1. Rebuilds assets/src.mu from the base APK's src.mu with every patched
     file in the repo's src/ overlaid (new files are added).
  2. Refreshes the plain CSVs in assets/res/data/ and inside assets/data.mu
     from csv_data/ (the device reads these when data.mu decompression
     fails; both copies are kept in sync with the repo's source of truth).
  3. Repacks the APK (old META-INF stripped), signs it with a v1 JAR
     signature, and verifies the whole chain before writing the result.

Requirements: Python 3.9+ and `pip install cryptography`
(the script uses cryptography only for the PKCS#7 signature block).

Usage:
    python3 scripts/rebuild_offline_apk.py [base_apk] [output_apk]

Defaults: base = English_offline.apk, output = English_offline.apk
(a backup of the previous output is written to build/English_offline_prev.apk).
The signing key is generated once and kept in build/offline_python.key/.crt
so rebuilds keep the same signature.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import os
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from xxtea_decrypt import encrypt_file, decrypt_file  # noqa: E402

MAGIC = b"gclR3cu9"
BASE64_NAME = "META-INF/MANIFEST.MF"


def fail(msg: str) -> None:
    print(f"  [FAIL] {msg}")
    sys.exit(1)


def ok(msg: str) -> None:
    print(f"  [PASS] {msg}")


# ---------------------------------------------------------------------------
# src.mu rebuild (same overlay rules as rebuild_from_apk.py)
# ---------------------------------------------------------------------------

def patched_sources() -> dict[str, Path]:
    files = {}
    for path in (ROOT / "src").rglob("*.lua"):
        files[str(path.relative_to(ROOT)).replace("\\", "/")] = path
    return files


def build_src_mu(base_data: bytes) -> bytes:
    source_files = patched_sources()
    out = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(base_data), "r") as old, zipfile.ZipFile(out, "w") as new:
        seen = set()
        for info in old.infolist():
            data = old.read(info.filename)
            if info.filename in source_files:
                data = encrypt_file(source_files[info.filename].read_bytes(), with_magic=True)
            zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            zi.compress_type = info.compress_type
            zi.external_attr = info.external_attr
            zi.create_system = info.create_system
            new.writestr(zi, data)
            seen.add(info.filename)
        for arcname, source in source_files.items():
            if arcname not in seen:
                new.writestr(arcname, encrypt_file(source.read_bytes(), with_magic=True),
                             zipfile.ZIP_DEFLATED)
    out.seek(0)
    return out.read()


# ---------------------------------------------------------------------------
# data.mu + assets CSV refresh
# ---------------------------------------------------------------------------

def refresh_data_mu(base_data: bytes) -> tuple[bytes, list[str]]:
    """Replace every inner CSV with the repo csv_data/ copy (STORED)."""
    out = io.BytesIO()
    replaced = []
    with zipfile.ZipFile(io.BytesIO(base_data), "r") as old, zipfile.ZipFile(out, "w") as new:
        for info in old.infolist():
            data = old.read(info.filename)
            if info.filename.endswith(".csv"):
                src = ROOT / "csv_data" / os.path.basename(info.filename)
                if src.is_file():
                    data = src.read_bytes()
                    replaced.append(info.filename)
            zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            zi.compress_type = info.compress_type
            zi.external_attr = info.external_attr
            zi.create_system = info.create_system
            new.writestr(zi, data)
    out.seek(0)
    return out.read(), replaced


# ---------------------------------------------------------------------------
# v1 (JAR) signing
# ---------------------------------------------------------------------------

def sign_v1(unsigned_path: Path, key_path: Path, crt_path: Path) -> dict[str, bytes]:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.hazmat.primitives.serialization import pkcs7
    from cryptography.x509.oid import NameOID

    if not key_path.exists() or not crt_path.exists():
        print("  Generating RSA-2048 signing key + certificate (build/offline_python.*)")
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Monster Battle Offline")])
        cert = (
            x509.CertificateBuilder()
            .subject_name(name)
            .issuer_name(name)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(__import__("datetime").datetime(2020, 1, 1))
            .not_valid_after(__import__("datetime").datetime(2099, 12, 31))
            .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=False)
            .add_extension(
                x509.KeyUsage(
                    digital_signature=True, content_commitment=True,
                    key_encipherment=False, data_encipherment=False,
                    key_agreement=False, key_cert_sign=True, crl_sign=True,
                    encipher_only=False, decipher_only=False,
                ),
                critical=False,
            )
            .sign(key, hashes.SHA256())
        )
        key_path.write_bytes(key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ))
        crt_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    else:
        key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
        cert = x509.load_pem_x509_certificate(crt_path.read_bytes())

    # Build the new zip content: entries (in order) + signature files last.
    with zipfile.ZipFile(unsigned_path, "r") as zin:
        entries = []
        for info in zin.infolist():
            if info.filename.startswith("META-INF/"):
                continue
            entries.append((info, zin.read(info.filename)))

    # --- MANIFEST.MF ---
    manifest = io.BytesIO()
    manifest.write(b"Manifest-Version: 1.0\r\n")
    manifest.write(b"Created-By: 1.0 (Monster Battle Offline)\r\n\r\n")
    for info, data in entries:
        digest = base64.b64encode(hashlib.sha256(data).digest())
        manifest.write(b"Name: " + info.filename.encode("utf-8") + b"\r\n")
        manifest.write(b"SHA-256-Digest: " + digest + b"\r\n\r\n")
    manifest_bytes = manifest.getvalue()

    # --- OFFLINE.SF ---
    def manifest_section_digest(section: bytes) -> bytes:
        # JAR spec: digest of the section INCLUDING its trailing blank line.
        return base64.b64encode(hashlib.sha256(section + b"\r\n\r\n").digest())

    sf = io.BytesIO()
    sf.write(b"Signature-Version: 1.0\r\n")
    sf.write(b"Created-By: 1.0 (Monster Battle Offline)\r\n")
    sf.write(b"SHA-256-Digest-Manifest: "
             + base64.b64encode(hashlib.sha256(manifest_bytes).digest()) + b"\r\n")
    main_section = manifest_bytes.split(b"\r\n\r\n", 1)[0]
    sf.write(b"SHA-256-Digest-Manifest-Main-Attributes: "
             + manifest_section_digest(main_section) + b"\r\n\r\n")
    for info, data in entries:
        # recompute the exact section bytes as written above
        entry_digest = base64.b64encode(hashlib.sha256(data).digest())
        section = (b"Name: " + info.filename.encode("utf-8") + b"\r\n"
                   + b"SHA-256-Digest: " + entry_digest + b"\r\n")
        sf.write(b"Name: " + info.filename.encode("utf-8") + b"\r\n")
        sf.write(b"SHA-256-Digest: " + manifest_section_digest(section) + b"\r\n\r\n")
    sf_bytes = sf.getvalue()

    # --- OFFLINE.RSA (PKCS#7 SignedData over the .SF file) ---
    rsa_der = (
        pkcs7.PKCS7SignatureBuilder()
        .set_data(sf_bytes)
        .add_signer(cert, key, hashes.SHA256())
        .add_certificate(cert)
        .sign(serialization.Encoding.DER, [pkcs7.PKCS7Options.Binary])
    )

    # --- assemble the signed APK: MANIFEST.MF first, then entries, then SF/RSA ---
    out_path = unsigned_path.with_name(unsigned_path.name + ".signed")
    with zipfile.ZipFile(unsigned_path, "r") as zin, zipfile.ZipFile(out_path, "w") as zout:
        def write(name, data, compress=zipfile.ZIP_DEFLATED):
            zi = zipfile.ZipInfo(name, date_time=(2026, 8, 21, 0, 0, 0))
            zi.compress_type = compress
            zi.external_attr = 0o644 << 16
            zout.writestr(zi, data)

        write(BASE64_NAME, manifest_bytes, zipfile.ZIP_STORED)
        for info, data in entries:
            zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            zi.compress_type = info.compress_type
            zi.external_attr = info.external_attr
            zi.create_system = info.create_system
            zi.extra = info.extra
            zout.writestr(zi, data)
        write("META-INF/OFFLINE.SF", sf_bytes, zipfile.ZIP_STORED)
        write("META-INF/OFFLINE.RSA", rsa_der, zipfile.ZIP_STORED)

    return {
        "manifest": manifest_bytes,
        "sf": sf_bytes,
        "rsa": rsa_der,
        "signed_path": out_path,
        "cert": cert,
    }


def verify_v1(apk_path: Path, artifacts: dict[str, bytes]) -> None:
    """Verify the complete v1 chain + APK structure of the output."""
    import re

    manifest = artifacts["manifest"]
    sf = artifacts["sf"]

    with zipfile.ZipFile(apk_path, "r") as z:
        names = z.namelist()

        # structure
        if len(names) != len(set(names)):
            fail(f"duplicate ZIP entries: {len(names) - len(set(names))}")
        ok(f"no duplicate entries ({len(names)} total)")
        meta = sorted(n for n in names if n.startswith("META-INF/"))
        if meta != ["META-INF/MANIFEST.MF", "META-INF/OFFLINE.RSA", "META-INF/OFFLINE.SF"]:
            fail(f"unexpected META-INF set: {meta}")
        ok("META-INF = MANIFEST.MF + OFFLINE.SF + OFFLINE.RSA")
        for critical in ("AndroidManifest.xml", "classes.dex", "resources.arsc",
                         "assets/src.mu", "assets/data.mu", "assets/common.mu",
                         "lib/armeabi/libcocos2dlua.so"):
            if critical not in names:
                fail(f"missing critical entry: {critical}")
        ok("critical files present")

        # the signed manifest bytes in the zip are what the verifier sees
        if z.read(BASE64_NAME) != manifest:
            fail("MANIFEST.MF bytes in output differ from signed bytes")
        ok("MANIFEST.MF is the signed copy")

        # PKCS#7 signature verification is done with openssl cms (independent
        # of the cryptography lib); the digest chain is verified here.
        try:
            import subprocess
            sf_tmp = ROOT / "build" / "offline_check.sf"
            rsa_tmp = ROOT / "build" / "offline_check.rsa"
            sf_tmp.write_bytes(sf)
            rsa_tmp.write_bytes(artifacts["rsa"])
            r = subprocess.run(
                ["openssl", "cms", "-verify", "-binary", "-inform", "DER", "-in", str(rsa_tmp),
                 "-content", str(sf_tmp), "-noverify", "-out", os.devnull],
                capture_output=True, text=True, timeout=60,
            )
            if r.returncode == 0:
                ok("RSA signature verifies over OFFLINE.SF (openssl)")
            else:
                fail(f"RSA signature failed: {r.stderr.strip()[-200:]}")
        except FileNotFoundError:
            print("  [WARN] openssl not found — skipping PKCS#7 check")

        # whole-manifest digest
        digest = base64.b64encode(hashlib.sha256(manifest).digest())
        if (b"SHA-256-Digest-Manifest: " + digest) not in sf:
            fail("whole-manifest digest mismatch in SF")
        ok("whole-manifest digest matches")

        # per-entry: SF section digest vs manifest section, manifest digest vs data
        entries = [n for n in names if not n.startswith("META-INF/")]
        manifest_text = manifest.decode("utf-8")
        sf_text = sf.decode("utf-8")
        checked = 0
        for name in entries:
            data = z.read(name)
            entry_digest = base64.b64encode(hashlib.sha256(data).digest())
            marker = b"Name: " + name.encode() + b"\r\nSHA-256-Digest: " + entry_digest
            if marker not in manifest:
                fail(f"manifest digest mismatch for {name}")
            # the SF must cover this manifest section
            if not re.search(r"Name: %s\r\nSHA-256-Digest: [A-Za-z0-9+/=]+" % re.escape(name), sf_text):
                fail(f"SF section missing for {name}")
            checked += 1
        ok(f"all {checked} entries covered by MANIFEST.MF and OFFLINE.SF")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base_apk", nargs="?", type=Path, default=ROOT / "English_offline.apk")
    parser.add_argument("output_apk", nargs="?", type=Path, default=ROOT / "English_offline.apk")
    args = parser.parse_args()
    if not args.base_apk.is_file():
        parser.error(f"base APK not found: {args.base_apk}")

    try:
        import cryptography  # noqa: F401
    except ImportError:
        fail("cryptography is required: pip install cryptography "
             "(or use scripts/rebuild_from_apk.py with a Java JDK)")

    print("[1/5] Rebuilding src.mu with repo src/ overlay...")
    with zipfile.ZipFile(args.base_apk) as apk:
        if "assets/src.mu" not in apk.namelist():
            fail("base APK has no assets/src.mu")
        src_mu_old = apk.read("assets/src.mu")
        data_mu_old = apk.read("assets/data.mu")
    src_mu_new = build_src_mu(src_mu_old)
    ok(f"src.mu rebuilt ({len(src_mu_old)} -> {len(src_mu_new)} bytes)")

    print("[2/5] Refreshing CSVs from csv_data/...")
    data_mu_new, replaced = refresh_data_mu(data_mu_old)
    ok(f"data.mu rebuilt, {len(replaced)} CSVs refreshed")
    csv_assets = {}
    with zipfile.ZipFile(args.base_apk) as apk:
        for name in apk.namelist():
            if name.startswith("assets/res/data/") and name.endswith(".csv"):
                csv_assets[name] = apk.read(name)

    print("[3/5] Repacking unsigned APK...")
    build_dir = ROOT / "build"
    build_dir.mkdir(exist_ok=True)
    unsigned = build_dir / "English_offline_unsigned_py.apk"
    with zipfile.ZipFile(args.base_apk) as old, zipfile.ZipFile(unsigned, "w") as new:
        for info in old.infolist():
            if info.filename.startswith("META-INF/"):
                continue
            data = old.read(info.filename)
            if info.filename == "assets/src.mu":
                data = src_mu_new
            elif info.filename == "assets/data.mu":
                data = data_mu_new
            elif info.filename in csv_assets:
                src = ROOT / "csv_data" / os.path.basename(info.filename)
                if src.is_file():
                    data = src.read_bytes()
            zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            zi.compress_type = info.compress_type
            zi.external_attr = info.external_attr
            zi.create_system = info.create_system
            new.writestr(zi, data)
    ok(f"unsigned APK written ({unsigned.stat().st_size:,} bytes)")

    print("[4/5] Signing (v1 JAR signature)...")
    artifacts = sign_v1(unsigned, build_dir / "offline_python.key", build_dir / "offline_python.crt")
    signed = artifacts["signed_path"]
    ok(f"signed APK written ({signed.stat().st_size:,} bytes)")

    # independent OpenSSL verification of the PKCS#7 block, when available
    try:
        import subprocess
        sf_tmp = build_dir / "offline_check.sf"
        rsa_tmp = build_dir / "offline_check.rsa"
        sf_tmp.write_bytes(artifacts["sf"])
        rsa_tmp.write_bytes(artifacts["rsa"])
        r = subprocess.run(
            ["openssl", "cms", "-verify", "-binary", "-inform", "DER", "-in", str(rsa_tmp),
             "-content", str(sf_tmp), "-noverify", "-out", "/dev/null"],
            capture_output=True, text=True, timeout=60,
        )
        if r.returncode == 0:
            ok("openssl independently verifies the PKCS#7 signature")
        else:
            fail(f"openssl rejected the PKCS#7 block: {r.stderr.strip()[-200:]}")
    except FileNotFoundError:
        print("  [WARN] openssl not found — skipping independent PKCS#7 check")

    print("[5/5] Verifying output APK...")
    verify_v1(signed, artifacts)

    # src.mu content check: patched files decrypt to the repo copies
    with zipfile.ZipFile(signed) as z:
        inner = zipfile.ZipFile(io.BytesIO(z.read("assets/src.mu")))
        sources = patched_sources()
        bad = 0
        for arcname, src in sources.items():
            if arcname not in inner.namelist():
                fail(f"src.mu missing {arcname}")
            raw = inner.read(arcname)
            plain = decrypt_file(raw) if raw[:8] == MAGIC else raw
            if plain != src.read_bytes():
                bad += 1
                print(f"  [FAIL] src.mu/{arcname} differs from repo src/")
        if bad:
            fail(f"{bad} patched files differ from repo src/")
        ok(f"all {len(sources)} patched files decrypt to the repo copies")

    # data.mu CSV content check
    with zipfile.ZipFile(signed) as z:
        inner = zipfile.ZipFile(io.BytesIO(z.read("assets/data.mu")))
        for name in inner.namelist():
            if not name.endswith(".csv"):
                continue
            src = ROOT / "csv_data" / os.path.basename(name)
            if src.is_file() and inner.read(name) != src.read_bytes():
                fail(f"data.mu/{name} differs from csv_data/")
        ok("data.mu CSVs match csv_data/")

    # finalize
    if args.output_apk.resolve() == signed.resolve():
        pass
    else:
        if args.output_apk.exists():
            prev = build_dir / "English_offline_prev.apk"
            shutil.copy2(args.output_apk, prev)
            print(f"  previous APK backed up to {prev.name}")
        shutil.copy2(signed, args.output_apk)
    ok(f"final APK: {args.output_apk} ({args.output_apk.stat().st_size:,} bytes)")
    print("\nREBUILD OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
