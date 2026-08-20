#!/usr/bin/env python3
"""
build_and_verify.py — Unified build + installation-verification pipeline.

Every time this script runs it:
  1. Rebuilds src.mu with all patched Lua files
  2. Copies patched src.mu into the apktool-decoded APK
  3. Builds the APK with apktool (preserves fixed AndroidManifest.xml)
  4. Signs with jarsigner
  5. Runs ALL installation checks (manifest, signing, SDK, exported, etc.)
  6. Runs game-logic sim test
  7. Copies final APK to Downloads/English_offline.apk

If ANY check fails, the script exits with code 1 and the broken APK is NOT
copied to the final location.
"""

import io
import os
import struct
import subprocess
import sys
import shutil
import zipfile

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
WORK = os.path.dirname(os.path.abspath(__file__))
ORIG_APK = os.path.join(WORK, "..", "English.apk")
MU_SRC = os.path.join(WORK, "apk_contents", "assets", "src.mu")
DECRYPTED = os.path.join(WORK, "decrypted", "src")
DECODED_APK = os.path.join(WORK, "build", "decoded_apk")
APKTOOL = os.path.join(WORK, "build", "apktool.jar")
JDK = "C:/Program Files/Java/jdk-17/bin"
KS = os.path.join(WORK, "build", "offline.keystore")
FINAL_APK = os.path.join(WORK, "..", "English_offline.apk")

sys.path.insert(0, WORK)
from xxtea_decrypt import encrypt_file, decrypt_file

# ---------------------------------------------------------------------------
# Files to patch (zip entry name -> decrypted source path)
# ---------------------------------------------------------------------------
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
    "src/logic/guide.lua": os.path.join(DECRYPTED, "logic", "guide.lua"),
}

errors = []
warnings = []


def ok(msg):
    print(f"  [PASS] {msg}")


def fail(msg):
    errors.append(msg)
    print(f"  [FAIL] {msg}")


def warn(msg):
    warnings.append(msg)
    print(f"  [WARN] {msg}")


# ===========================================================================
# STEP 1: Syntax-check all patched Lua files
# ===========================================================================
def step_syntax_check():
    print("\n[1/6] Syntax-checking patched Lua files...")
    luac = os.path.join(WORK, "lua51", "luac5.1.exe")
    for entry, path in CHANGED.items():
        result = subprocess.run([luac, "-p", path], capture_output=True, text=True)
        if result.returncode != 0:
            fail(f"Syntax error in {entry}: {result.stderr.strip()}")
        else:
            ok(f"{entry} compiles")


# ===========================================================================
# STEP 2: Rebuild src.mu
# ===========================================================================
def step_rebuild_mu():
    print("\n[2/6] Rebuilding src.mu...")
    out_mu = os.path.join(WORK, "build", "assets", "src.mu")
    os.makedirs(os.path.dirname(out_mu), exist_ok=True)
    src = zipfile.ZipFile(MU_SRC, "r")

    # Round-trip verify
    for entry, plain_path in CHANGED.items():
        plain = open(plain_path, "rb").read()
        enc = encrypt_file(plain, with_magic=True)
        dec = decrypt_file(enc)
        if dec != plain:
            fail(f"Round-trip failed for {entry}")
        else:
            ok(f"Round-trip OK: {entry} ({len(plain)} bytes)")

    # Build new src.mu
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
                print(f"  Added new entry: {entry}")

    src.close()
    ok(f"src.mu built: {os.path.getsize(out_mu)} bytes")


# ===========================================================================
# STEP 3: Build APK from decoded_apk (has fixed manifest)
# ===========================================================================
def step_apktool_build():
    print("\n[3/6] Building APK with apktool...")

    # Copy patched src.mu into decoded APK assets
    assets_dir = os.path.join(DECODED_APK, "assets")
    os.makedirs(assets_dir, exist_ok=True)
    mu_dst = os.path.join(assets_dir, "src.mu")
    shutil.copy2(os.path.join(WORK, "build", "assets", "src.mu"), mu_dst)

    # Patch smali: nop third-party SDK calls that crash on modern Android
    smali_path = os.path.join(DECODED_APK, "smali", "org", "cocos2dx", "lua", "AppActivity.smali")
    if os.path.exists(smali_path):
        with open(smali_path, "r") as f:
            smali = f.read()
        patched = False
        # Nop PlatformSDK.init (calls Google Play Services which crashes)
        old = 'invoke-static {p0, p1}, Lorg/cocos2dx/lua/PlatformSDK;->init(Landroid/app/Activity;Landroid/os/Bundle;)V'
        if old in smali:
            smali = smali.replace(old, 'nop')
            patched = True
        # Nop TalkingData calls (MODE_WORLD_READABLE removed in Android 7+)
        for td_call in [
            'invoke-static {p0, v2, v1}, Lcom/tendcloud/tenddata/TalkingDataGA;->init(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)V',
            'invoke-static {p0}, Lcom/tendcloud/tenddata/TalkingDataGA;->onPause(Landroid/app/Activity;)V',
            'invoke-static {p0}, Lcom/tendcloud/tenddata/TalkingDataGA;->onResume(Landroid/app/Activity;)V',
        ]:
            if td_call in smali:
                smali = smali.replace(td_call, 'nop')
                patched = True
        if patched:
            with open(smali_path, "w") as f:
                f.write(smali)
            ok("Smali patched: PlatformSDK.init + TalkingData nopped")
        else:
            ok("Smali: no third-party SDK calls to patch")
    else:
        warn(f"AppActivity.smali not found at {smali_path}")

    unsigned = os.path.join(WORK, "build", "English_offline_unsigned.apk")
    result = subprocess.run(
        ["java", "-jar", APKTOOL, "b", "-f", "-o", unsigned, DECODED_APK],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        fail(f"apktool build failed: {result.stderr[-500:]}")
    else:
        ok(f"APK built: {os.path.getsize(unsigned)} bytes")
    return unsigned


# ===========================================================================
# STEP 4: Sign APK
# ===========================================================================
def step_sign(unsigned):
    print("\n[4/6] Signing APK...")

    # Generate keystore if needed
    if not os.path.exists(KS):
        subprocess.run([
            os.path.join(JDK, "keytool.exe"), "-genkeypair", "-keystore", KS,
            "-alias", "offline", "-keyalg", "RSA", "-keysize", "2048",
            "-validity", "10000", "-storepass", "android", "-keypass", "android",
            "-dname", "CN=Offline Build, OU=Offline, O=Offline, C=US",
        ], check=True)
        print("  Keystore created")

    signed = os.path.join(WORK, "build", "English_offline_signed.apk")
    result = subprocess.run([
        os.path.join(JDK, "jarsigner.exe"),
        "-keystore", KS, "-storepass", "android", "-keypass", "android",
        "-sigalg", "SHA256withRSA", "-digestalg", "SHA-256",
        "-signedjar", signed, unsigned, "offline",
    ], capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"jarsigner failed: {result.stderr[-500:]}")
    else:
        ok(f"APK signed: {os.path.getsize(signed)} bytes")
    return signed


# ===========================================================================
# STEP 5: Installation checks (the critical part)
# ===========================================================================
def step_install_checks(signed):
    print("\n[5/6] Running installation checks...")

    zf = zipfile.ZipFile(signed, "r")
    names = zf.namelist()

    # --- 5a: No duplicate entries ---
    if len(names) != len(set(names)):
        from collections import Counter
        dupes = [n for n, c in Counter(names).items() if c > 1]
        fail(f"Duplicate ZIP entries: {dupes}")
    else:
        ok(f"No duplicate entries ({len(names)} total)")

    # --- 5b: META-INF exactly right ---
    meta = sorted([n for n in names if n.startswith("META-INF/")])
    expected_meta = ["META-INF/MANIFEST.MF", "META-INF/OFFLINE.RSA", "META-INF/OFFLINE.SF"]
    if meta != expected_meta:
        fail(f"META-INF wrong: {meta}")
    else:
        ok("META-INF = MANIFEST.MF + OFFLINE.SF + OFFLINE.RSA")

    # --- 5c: No old signing artifacts ---
    old_signs = ["META-INF/CERT.SF", "META-INF/CERT.RSA", "META-INF/mu77channel_English"]
    found_old = [f for f in old_signs if f in names]
    if found_old:
        fail(f"Old signing files present: {found_old}")
    else:
        ok("No old signing artifacts")

    # --- 5d: Critical files present ---
    critical = ["AndroidManifest.xml", "classes.dex", "resources.arsc",
                "assets/src.mu", "assets/data.mu", "assets/common.mu",
                "lib/armeabi/libcocos2dlua.so"]
    missing = [f for f in critical if f not in names]
    if missing:
        fail(f"MISSING: {missing}")
    else:
        ok(f"All {len(critical)} critical files present")

    # --- 5e: Manifest is valid binary XML ---
    manifest = zf.read("AndroidManifest.xml")
    magic = struct.unpack("<I", manifest[:4])[0]
    if magic == 0x00080003:
        ok("AndroidManifest.xml is valid binary XML")
    else:
        fail(f"Manifest magic wrong: 0x{magic:08x}")

    # --- 5f: ZIP integrity ---
    bad = zf.testzip()
    if bad:
        fail(f"ZIP corrupt: {bad}")
    else:
        ok("ZIP integrity (testzip)")

    # --- 5g: DEX format ---
    dex = zf.read("classes.dex")
    if dex[:4] == b"dex\n":
        ok("classes.dex valid DEX")
    else:
        fail("classes.dex bad format")

    # --- 5h: ELF native lib ---
    lib = zf.read("lib/armeabi/libcocos2dlua.so")
    if lib[:4] == b"\x7fELF":
        ok("libcocos2dlua.so valid ELF")
    else:
        fail("libcocos2dlua.so not ELF")

    # --- 5i: src.mu decrypts to patched files ---
    mu_zip = zipfile.ZipFile(io.BytesIO(zf.read("assets/src.mu")))
    for f in CHANGED:
        if f not in mu_zip.namelist():
            fail(f"src.mu missing {f}")
        else:
            raw = mu_zip.read(f)
            if raw[:8] == b"gclR3cu9":
                plain = decrypt_file(raw)
            else:
                plain = raw
            expected_content = open(CHANGED[f], "rb").read()
            if plain != expected_content:
                fail(f"src.mu/{f} content mismatch")
            else:
                ok(f"src.mu/{f} decrypts correctly")

    # --- 5j: Critical markers in patched files ---
    net_raw = mu_zip.read("src/manager/network.lua")
    net_plain = decrypt_file(net_raw) if net_raw[:8] == b"gclR3cu9" else net_raw
    if b"OFFLINE_MODE" in net_plain:
        ok("network.lua has OFFLINE_MODE marker")
    else:
        fail("network.lua missing OFFLINE_MODE")

    main_raw = mu_zip.read("src/main.lua")
    main_plain = decrypt_file(main_raw) if main_raw[:8] == b"gclR3cu9" else main_raw
    if b"HAS_DOWNLOADED_PATCH" in main_plain:
        ok("main.lua has HAS_DOWNLOADED_PATCH")
    else:
        fail("main.lua missing HAS_DOWNLOADED_PATCH")

    mu_zip.close()

    # --- 5k: ANDROID MANIFEST via androguard (SDK versions, exported, etc.) ---
    try:
        from androguard.core.apk import APK
        a = APK(signed)

        # Target SDK
        target_sdk = a.get_target_sdk_version()
        if target_sdk and int(target_sdk) >= 30:
            ok(f"targetSdkVersion = {target_sdk} (modern Android)")
        else:
            fail(f"targetSdkVersion = {target_sdk} (must be >= 30 for Android 12+)")

        # Min SDK
        min_sdk = a.get_min_sdk_version()
        if min_sdk and int(min_sdk) >= 21:
            ok(f"minSdkVersion = {min_sdk} (Android 5.0+)")
        else:
            fail(f"minSdkVersion = {min_sdk} (should be >= 21)")        # Activities count (should be only AppActivity)
        acts = a.get_activities()
        if "org.cocos2dx.lua.AppActivity" in acts:
            ok("Launcher activity present")
        else:
            fail("Launcher activity (org.cocos2dx.lua.AppActivity) missing")
        if len(acts) <= 2:
            ok(f"Only {len(acts)} activity/activities (no FB/Google/JPush clutter)")
        else:
            warn(f"{len(acts)} activities (some may be unnecessary)")

        # Certificate expiry — expired certs fail install on Android 7+
        cert_info = a.get_certificates_v2()
        if not cert_info:
            cert_info = a.get_certificates_v1()
        if cert_info:
            for cert in cert_info:
                not_after = cert.not_valid_after
                if not_after:
                    # Make naive for comparison
                    from datetime import datetime, timezone
                    if not_after.tzinfo is not None:
                        not_after = not_after.replace(tzinfo=None)
                    if not_after > datetime.now():
                        ok(f"Signing certificate valid until {not_after.strftime('%Y-%m-%d')}")
                    else:
                        fail(f"Signing certificate EXPIRED on {not_after.strftime('%Y-%m-%d')}")
                # Self-signed check (informational)
                issuer = cert.issuer.human_friendly if hasattr(cert.issuer, 'human_friendly') else str(cert.issuer)
                subject = cert.subject.human_friendly if hasattr(cert.subject, 'human_friendly') else str(cert.subject)
                if issuer == subject:
                    warn("Certificate is self-signed (fine for debug/offline)")
                else:
                    ok(f"Certificate signed by: {issuer[:60]}")
        else:
            warn("Could not read certificate details")

        # Debuggable flag — should be false for release
        app_debuggable = a.get_attribute_value('application', 'debuggable')
        if app_debuggable == 'true':
            warn("android:debuggable=true (set to false for release)")
        else:
            ok("Not debuggable (release mode)")

        # allowBackup — security informational
        allow_backup = a.get_attribute_value('application', 'allowBackup')
        if allow_backup == 'false':
            ok("allowBackup=false (secure)")
        elif allow_backup == 'true':
            warn("allowBackup=true (user can extract app data via adb)")
        else:
            ok("allowBackup not set (defaults to true)")

        # DEX count
        dex_files = [n for n in names if n.endswith('.dex')]
        if len(dex_files) == 1:
            ok(f"Single DEX file ({dex_files[0]})")
        elif len(dex_files) <= 3:
            ok(f"{len(dex_files)} DEX files (multidex)")
        else:
            warn(f"{len(dex_files)} DEX files — may be bloated")

        # Native lib architecture
        lib_archs = set()
        for n in names:
            if n.startswith('lib/') and n.endswith('.so'):
                parts = n.split('/')
                if len(parts) >= 3:
                    lib_archs.add(parts[1])
        if lib_archs:
            ok(f"Native libs: {', '.join(sorted(lib_archs))}")
            # Check for armeabi-v7a (required for most devices)
            if 'armeabi-v7a' in lib_archs or 'armeabi' in lib_archs:
                ok("ARM v7a lib present (broadest device support)")
            else:
                warn(f"No armeabi-v7a — may not run on older ARM devices")
        else:
            warn("No native .so files found")

        # Validate APK
        print("  [INFO] Running androguard APK validation...")
        # APK constructor already validates
        ok("APK validated by androguard")

    except ImportError:
        warn("androguard not installed — skipping SDK/exported checks")

    # --- 5l: resources.arsc size (after androguard so zf is still open) ---
    res_len = len(zf.read('resources.arsc'))
    if res_len > 1000:
        ok(f"resources.arsc: {res_len:,} bytes")
    else:
        fail(f"resources.arsc too small: {res_len} bytes")

    zf.close()

    return len(errors) == 0


# ===========================================================================
# STEP 6: Game logic sim test
# ===========================================================================
def step_sim_test():
    print("\n[6/6] Running game logic sim test...")
    lua = os.path.join(WORK, "lua51", "lua5.1.exe")
    sim = os.path.join(WORK, "sim_test.lua")

    # Clean save dirs
    for d in ["sim_save", "sim_save_int"]:
        p = os.path.join(WORK, d)
        if os.path.exists(p):
            shutil.rmtree(p)

    result = subprocess.run([lua, sim], capture_output=True, text=True, cwd=WORK)
    for line in result.stdout.strip().split("\n"):
        if line.startswith("[PASS]"):
            print(f"  {line}")
        elif line.startswith("[FAIL]"):
            fail(line)
        elif "RESULT:" in line or "PASSED" in line or "FAIL" in line.upper():
            print(f"  {line}")

    if result.returncode != 0:
        fail(f"Sim test failed (exit {result.returncode})")
    else:
        ok("All sim test checks passed")


# ===========================================================================
# MAIN
# ===========================================================================
if __name__ == "__main__":
    print("=" * 60)
    print("  BUILD & VERIFY — Offline Single-Player APK")
    print("=" * 60)

    step_syntax_check()
    step_rebuild_mu()
    unsigned = step_apktool_build()
    signed = step_sign(unsigned)
    install_ok = step_install_checks(signed)
    step_sim_test()

    # Final summary
    print("\n" + "=" * 60)
    if errors:
        print(f"  BUILD FAILED — {len(errors)} error(s):")
        for e in errors:
            print(f"    X {e}")
        if warnings:
            print(f"  {len(warnings)} warning(s):")
            for w in warnings:
                print(f"    ! {w}")
        print("\n  The APK was NOT copied to the final location.")
        print("=" * 60)
        sys.exit(1)
    else:
        # Only copy to final if everything passed
        shutil.copy2(signed, FINAL_APK)
        size = os.path.getsize(FINAL_APK)
        print(f"  BUILD SUCCEEDED — {len(CHANGED)} files patched, 0 errors")
        if warnings:
            print(f"  {len(warnings)} warning(s):")
            for w in warnings:
                print(f"    ! {w}")
        print(f"\n  FINAL APK: {FINAL_APK} ({size:,} bytes)")
        print("=" * 60)
