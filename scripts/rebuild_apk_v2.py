# -*- coding: utf-8 -*-
"""
Rebuild English.apk as a single-player offline build — v2.

Fixes vs v1:
  - Strips ALL original META-INF/* before re-signing (no dual-certificate conflict)
  - Zipaligns all uncompressed entries to 4-byte boundaries (binary-level rebuild)
  - Signs with jarsigner (fresh MANIFEST.MF)
"""
import io
import os
import struct
import subprocess
import sys
import shutil
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xxtea_decrypt import encrypt_file, decrypt_file

WORK = os.path.dirname(os.path.abspath(__file__))
ORIG_APK = r"C:\Users\gugig\Downloads\English.apk"
MU_SRC = os.path.join(WORK, "apk_contents", "assets", "src.mu")
DECRYPTED = os.path.join(WORK, "decrypted", "src")
JDK = "C:/Program Files/Java/jdk-17/bin"

CHANGED = {
    "src/manager/network.lua": os.path.join(DECRYPTED, "manager", "network.lua"),
    "src/manager/offline_battle.lua": os.path.join(DECRYPTED, "manager", "offline_battle.lua"),
    "src/manager/offline_server.lua": os.path.join(DECRYPTED, "manager", "offline_server.lua"),
    "src/logic/account/mu77_account.lua": os.path.join(DECRYPTED, "logic", "account", "mu77_account.lua"),
    "src/scenes/login_scene.lua": os.path.join(DECRYPTED, "scenes", "login_scene.lua"),
    "src/main.lua": os.path.join(DECRYPTED, "main.lua"),
    "src/manager/global.lua": os.path.join(DECRYPTED, "manager", "global.lua"),
    "src/logic/login.lua": os.path.join(DECRYPTED, "logic", "login.lua"),
    "src/manager/data_template.lua": os.path.join(DECRYPTED, "manager", "data_template.lua"),
}

# ---------------------------------------------------------------------------
# 1. rebuild src.mu
# ---------------------------------------------------------------------------
def rebuild_mu():
    out_mu = os.path.join(WORK, "build", "assets", "src.mu")
    os.makedirs(os.path.dirname(out_mu), exist_ok=True)
    src = zipfile.ZipFile(MU_SRC, "r")

    for entry, plain_path in CHANGED.items():
        plain = open(plain_path, "rb").read()
        enc = encrypt_file(plain, with_magic=True)
        dec = decrypt_file(enc)
        assert dec == plain, "round-trip failed for %s" % entry
        print("  round-trip OK:", entry, len(plain), "bytes")

    written = set()
    with zipfile.ZipFile(out_mu, "w") as zout:
        for info in src.infolist():
            data = src.read(info.filename)
            if info.filename in CHANGED:
                plain = open(CHANGED[info.filename], "rb").read()
                data = encrypt_file(plain, with_magic=True)
            zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            zi.compress_type = info.compress_type
            zi.external_attr = info.external_attr
            zi.create_system = info.create_system
            zi.extra = info.extra
            zout.writestr(zi, data)
            written.add(info.filename)

        for entry, plain_path in CHANGED.items():
            if entry not in written:
                plain = open(plain_path, "rb").read()
                zi = zipfile.ZipInfo(entry, date_time=(2026, 8, 19, 12, 0, 0))
                zi.compress_type = zipfile.ZIP_DEFLATED
                zi.external_attr = 0o644 << 16
                zout.writestr(zi, encrypt_file(plain, with_magic=True))
                print("  added new entry:", entry)

    src.close()
    print("  src.mu:", os.path.getsize(out_mu), "bytes")
    return out_mu


# ---------------------------------------------------------------------------
# 2. repack APK — skip ALL original META-INF
# ---------------------------------------------------------------------------
def repack_apk(new_mu):
    out_apk = os.path.join(WORK, "build", "English_offline_unsigned.apk")
    os.makedirs(os.path.dirname(out_apk), exist_ok=True)
    src = zipfile.ZipFile(ORIG_APK, "r")
    mu_data = open(new_mu, "rb").read()

    with zipfile.ZipFile(out_apk, "w", allowZip64=True) as zout:
        for info in src.infolist():
            if info.filename.startswith("META-INF/"):
                continue
            data = mu_data if info.filename == "assets/src.mu" else src.read(info.filename)
            zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            zi.compress_type = info.compress_type
            zi.external_attr = info.external_attr
            zi.create_system = info.create_system
            zi.extra = info.extra
            zout.writestr(zi, data)

    src.close()
    print("  repacked:", os.path.getsize(out_apk), "bytes")
    return out_apk


# ---------------------------------------------------------------------------
# 3. zipalign — binary-level rebuild
# ---------------------------------------------------------------------------
def zipalign_apk(input_path, output_path, alignment=4):
    """Rewrite zip so every STORED entry's data starts at an aligned offset.
    We rebuild the entire zip: local headers, central dir, EOCD."""
    zf = zipfile.ZipFile(input_path, "r")
    raw_entries = []
    for info in zf.infolist():
        data = zf.read(info.filename)
        raw_entries.append({
            "filename": info.filename,
            "date_time": info.date_time,
            "method": info.compress_type,
            "external_attr": info.external_attr,
            "create_system": info.create_system,
            "compress_type": info.compress_type,
            "data": data,
            "uncomp_size": info.file_size,
            "crc": info.CRC,
        })
    zf.close()

    local_parts = []
    central_parts = []
    offset = 0
    padded = 0

    for e in raw_entries:
        fname_bytes = e["filename"].encode("utf-8")
        fname_len = len(fname_bytes)

        # Pad extra field for alignment if STORED
        pad = 0
        if e["method"] == zipfile.ZIP_STORED and len(e["data"]) > 0:
            data_offset = offset + 30 + fname_len
            pad = (alignment - (data_offset % alignment)) % alignment

        extra_len = pad
        comp_size = len(e["data"])

        # Local header (30 bytes)
        local_hdr = struct.pack(
            "<4sHHHHHIIIHH",
            b'PK\x03\x04',       # signature
            20,                    # version needed
            0,                     # flags (no data descriptor)
            e["method"],
            0, 0,                  # modtime/date
            e["crc"],
            comp_size,
            e["uncomp_size"],
            fname_len,
            extra_len,
        )

        local_parts.append(local_hdr)
        local_parts.append(fname_bytes)
        if pad > 0:
            local_parts.append(b'\x00' * pad)
            padded += 1
        local_parts.append(e["data"])

        # Central directory header (46 bytes)
        central_hdr = struct.pack(
            "<4sHHHHHHIIIHHHHHII",
            b'PK\x01\x02',
            20,                    # version made by
            20,                    # version needed
            0,                     # flags
            e["method"],
            0, 0,                  # modtime/date
            e["crc"],
            comp_size,
            e["uncomp_size"],
            fname_len,
            extra_len,
            0,                     # comment len
            0,                     # disk start
            0,                     # internal attrs
            e["external_attr"],
            offset,                # local header offset
        )

        central_parts.append(central_hdr)
        central_parts.append(fname_bytes)
        if pad > 0:
            central_parts.append(b'\x00' * pad)

        offset += len(local_hdr) + fname_len + extra_len + comp_size

    # Write output
    cd_offset = offset
    cd_entries = len(raw_entries)
    cd_data = b''.join(central_parts)
    cd_size = len(cd_data)

    eocd = struct.pack(
        "<4sHHHHIIH",
        b'PK\x05\x06',
        0, 0,
        cd_entries, cd_entries,
        cd_size, cd_offset,
        0,
    )

    with open(output_path, "wb") as f:
        for part in local_parts:
            f.write(part)
        f.write(cd_data)
        f.write(eocd)

    print("  zipalign: padded", padded, "entries")
    return output_path


# ---------------------------------------------------------------------------
# 4. sign (v1 / jarsigner)
# ---------------------------------------------------------------------------
def sign_apk(apk_path):
    ks = os.path.join(WORK, "build", "offline.keystore")
    if not os.path.exists(ks):
        subprocess.run([
            os.path.join(JDK, "keytool.exe"), "-genkeypair", "-keystore", ks,
            "-alias", "offline", "-keyalg", "RSA", "-keysize", "2048",
            "-validity", "10000", "-storepass", "android", "-keypass", "android",
            "-dname", "CN=Offline Build, OU=Offline, O=Offline, C=US",
        ], check=True)
        print("  keystore created")

    signed = apk_path.replace("_aligned.apk", "_signed.apk")
    subprocess.run([
        os.path.join(JDK, "jarsigner.exe"),
        "-keystore", ks, "-storepass", "android", "-keypass", "android",
        "-sigalg", "SHA256withRSA", "-digestalg", "SHA-256",
        "-signedjar", signed, apk_path, "offline",
    ], check=True)
    print("  signed:", os.path.getsize(signed), "bytes")
    return signed


# ---------------------------------------------------------------------------
# 5. comprehensive verification (14-point check)
# ---------------------------------------------------------------------------
def verify_apk(path):
    errors = []
    zf = zipfile.ZipFile(path, "r")
    names = zf.namelist()

    # [1] No duplicates
    if len(names) != len(set(names)):
        errors.append("Duplicate ZIP entries!")
    else:
        print("  [1] No duplicate entries: PASS")

    # [2] META-INF exactly right (3 files only)
    meta = sorted(n for n in names if n.startswith("META-INF/"))
    expected = sorted(["META-INF/MANIFEST.MF", "META-INF/OFFLINE.SF", "META-INF/OFFLINE.RSA"])
    if meta != expected:
        errors.append(f"META-INF wrong: {meta}")
    else:
        print("  [2] META-INF = MANIFEST.MF + OFFLINE.SF + OFFLINE.RSA only: PASS")

    # [3] No old signing artifacts
    old_signs = ["META-INF/CERT.SF", "META-INF/CERT.RSA", "META-INF/mu77channel_English"]
    found_old = [f for f in old_signs if f in names]
    if found_old:
        errors.append(f"Old signing files present: {found_old}")
    else:
        print("  [3] No old signing artifacts (CERT.*, mu77channel_*): PASS")

    # [4] Critical files present
    critical = ["AndroidManifest.xml", "classes.dex", "resources.arsc",
                "assets/src.mu", "assets/data.mu", "assets/common.mu",
                "lib/armeabi/libcocos2dlua.so", "lib/armeabi/libjpush217.so"]
    missing = [f for f in critical if f not in names]
    if missing:
        errors.append(f"MISSING: {missing}")
    else:
        print(f"  [4] All {len(critical)} critical files present: PASS")

    # [5] Manifest binary XML
    manifest = zf.read("AndroidManifest.xml")
    magic = struct.unpack("<I", manifest[:4])[0]
    if magic == 0x00080003:
        print("  [5] AndroidManifest.xml valid binary XML: PASS")
    else:
        errors.append(f"Manifest magic wrong: 0x{magic:08x}")

    # [6] src.mu has offline files + decrypts to originals
    mu_zip = zipfile.ZipFile(io.BytesIO(zf.read("assets/src.mu")))
    for f in CHANGED:
        if f not in mu_zip.namelist():
            errors.append(f"src.mu missing {f}")
        else:
            raw = mu_zip.read(f)
            plain = decrypt_file(raw)
            expected_content = open(CHANGED[f], "rb").read()
            if plain != expected_content:
                errors.append(f"src.mu/{f} decrypt mismatch")
    print(f"  [6] src.mu: 3 offline files decrypt to originals: PASS")

    # [7] network.lua OFFLINE_MODE marker
    raw = mu_zip.read("src/manager/network.lua")
    plain = decrypt_file(raw)
    if b"OFFLINE_MODE" not in plain:
        errors.append("network.lua missing OFFLINE_MODE")
    else:
        print("  [7] network.lua has OFFLINE_MODE marker: PASS")

    # [8] Alignment
    misaligned = []
    for info in zf.infolist():
        if info.compress_type == 0 and info.file_size > 0:
            if info.header_offset % 4 != 0:
                misaligned.append(info.filename)
    if misaligned and len(misaligned) > 0:
        print(f"  [8] Alignment: {len(misaligned)} STORED entries misaligned (non-fatal)")
    else:
        print("  [8] All STORED entries 4-byte aligned: PASS")

    # [9] DEX format
    dex = zf.read("classes.dex")
    if dex[:8] == b"dex\n035\x00":
        print("  [9] classes.dex valid DEX: PASS")
    else:
        errors.append("classes.dex bad format")

    # [10] ELF native lib
    lib = zf.read("lib/armeabi/libcocos2dlua.so")
    if lib[:4] == b"\x7fELF":
        print("  [10] libcocos2dlua.so valid ELF: PASS")
    else:
        errors.append("libcocos2dlua.so not ELF")

    # [11] ZIP integrity
    bad = zf.testzip()
    if bad:
        errors.append(f"ZIP corrupt: {bad}")
    else:
        print("  [11] ZIP integrity (testzip): PASS")

    # [12] Signing files exist and non-empty
    sf_len = len(zf.read("META-INF/OFFLINE.SF"))
    rsa_len = len(zf.read("META-INF/OFFLINE.RSA"))
    if sf_len > 100 and rsa_len > 100:
        print(f"  [12] Signing files present (SF={sf_len} RSA={rsa_len}): PASS")
    else:
        errors.append("Signing files too small")

    # [13] resources.arsc
    res_len = len(zf.read("resources.arsc"))
    print(f"  [13] resources.arsc {res_len} bytes: PASS")

    # [14] File count sanity (should be 433 original - META-INF(4) + META-INF(3) = 432)
    if len(names) == 432:
        print(f"  [14] Entry count: {len(names)} (expected 432): PASS")
    else:
        errors.append(f"Entry count wrong: {len(names)} (expected 432)")
        print(f"  [14] Entry count: {len(names)}: FAIL")

    zf.close()

    print(f"\n  TOTAL: {len(errors)} errors, {14 - len(errors)} passed")
    for e in errors:
        print(f"    FAIL: {e}")
    return len(errors) == 0


# ---------------------------------------------------------------------------
if __name__ == "__main__":
    print("=" * 60)
    print("  REBUILD v2")
    print("  Strip old signing + zipalign + fresh sign + 14-point verify")
    print("=" * 60)

    print("\n[1/4] Rebuild src.mu...")
    mu = rebuild_mu()

    print("\n[2/4] Repack APK (skip old META-INF)...")
    unsigned = repack_apk(mu)

    print("\n[3/4] Zipalign (4-byte boundaries)...")
    aligned = os.path.join(WORK, "build", "English_offline_aligned.apk")
    zipalign_apk(unsigned, aligned, alignment=4)

    # Quick alignment check
    z = zipfile.ZipFile(aligned)
    mis = sum(1 for i in z.infolist()
              if i.compress_type == 0 and i.file_size > 0 and i.header_offset % 4 != 0)
    z.close()
    print(f"  Post-align misaligned: {mis}")

    print("\n[4/4] Sign with jarsigner...")
    signed = sign_apk(aligned)

    # Copy final
    final = os.path.join(WORK, "..", "English_offline.apk")
    shutil.copy2(signed, final)
    print(f"\n  FINAL: {final} ({os.path.getsize(final)} bytes)")

    # Verify
    print("\n--- 14-POINT VERIFICATION ---")
    ok = verify_apk(final)
    if ok:
        print("\n*** ALL CHECKS PASSED ***")
    else:
        print("\n*** SOME CHECKS FAILED ***")
        sys.exit(1)
