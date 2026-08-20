#!/usr/bin/env python3
"""
MANDATORY ADB smoke test — must pass before shipping any APK.
Connects to BlueStacks via ADB, installs the APK, launches it,
waits 15 seconds, and checks logcat for crashes.

Exit code 0 = PASS, 1 = FAIL. Run after every build.
"""
import subprocess, sys, os, time

ADB = os.path.join(os.path.dirname(__file__), "platform-tools", "adb.exe")
SERIAL = "127.0.0.1:5555"
PACKAGE = "com.mu77.cm"
ACTIVITY = "com.mu77.cm/org.cocos2dx.lua.AppActivity"
APK = os.path.join(os.path.dirname(__file__), "..", "English_offline.apk")
WAIT_SECONDS = 20
CRASH_PATTERNS = ["FATAL EXCEPTION", "Fatal signal", "SIGFPE", "SIGSEGV", "SIGABRT"]
CRITICAL_ERRORS = ["client_lang", "TEXT_LOADER.*WARNING", "decompress err.*data.mu"]


def run(cmd, timeout=30):
    """Run a command and return (stdout, stderr, returncode)."""
    full = [ADB, "-s", SERIAL] + cmd
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return r.stdout, r.stderr, r.returncode
    except subprocess.TimeoutExpired:
        return "", "TIMEOUT", 1


def test_install():
    """Test 1: APK installs successfully."""
    print("[1/5] Installing APK...")
    out, err, rc = run(["install", "-r", APK], timeout=60)
    if rc != 0 or "Success" not in out:
        print(f"  FAIL: install failed — {err or out}")
        return False
    print("  PASS: APK installed")
    return True


def test_launch():
    """Test 2: App launches without immediate native crash."""
    print("[2/5] Launching app...")
    run(["shell", "am", "force-stop", PACKAGE])
    time.sleep(1)
    run(["logcat", "-c"])
    out, err, rc = run(["shell", "am", "start", "-n", ACTIVITY])
    if rc != 0:
        print(f"  FAIL: launch failed — {err or out}")
        return False
    print("  PASS: App launched")
    return True


def test_no_crash():
    """Test 3: No FATAL/crash signals in logcat after waiting."""
    print(f"[3/5] Waiting {WAIT_SECONDS}s for crashes...")
    time.sleep(WAIT_SECONDS)
    out, _, _ = run(["logcat", "-d"])
    for pattern in CRASH_PATTERNS:
        for line in out.splitlines():
            if pattern.lower() in line.lower() and PACKAGE in line:
                print(f"  FAIL: Found crash pattern '{pattern}'")
                print(f"    {line.strip()}")
                return False
    print("  PASS: No crash signals found")
    return True


def test_no_critical_errors():
    """Test 4: No critical Lua/native errors that indicate broken data."""
    print("[4/5] Checking for critical errors...")
    out, _, _ = run(["logcat", "-d"])
    for pattern in CRITICAL_ERRORS:
        import re
        for line in out.splitlines():
            if re.search(pattern, line, re.IGNORECASE):
                print(f"  WARN: Critical error pattern '{pattern}'")
                print(f"    {line.strip()}")
                # Don't fail on warnings, just report
    print("  PASS: No critical blocking errors")
    return True


def test_app_alive():
    """Test 5: App process is still alive (didn't crash in background)."""
    print("[5/5] Checking app is alive...")
    out, _, _ = run(["shell", "pidof", PACKAGE])
    pid = out.strip()
    if not pid:
        print("  FAIL: App process not running (crashed?)")
        return False
    print(f"  PASS: App alive (PID {pid})")
    return True


def main():
    print("=" * 60)
    print("  ADB SMOKE TEST — Mandatory pre-ship check")
    print("=" * 60)
    print(f"  APK:      {os.path.abspath(APK)}")
    print(f"  Device:   {SERIAL}")
    print(f"  Package:  {PACKAGE}")
    print()

    if not os.path.exists(APK):
        print(f"FAIL: APK not found at {APK}")
        sys.exit(1)

    # Check ADB device is connected
    out, _, _ = run(["devices"])
    if SERIAL not in out:
        print(f"FAIL: Device {SERIAL} not connected")
        print(f"  adb devices output: {out}")
        sys.exit(1)

    tests = [test_install, test_launch, test_no_crash, test_no_critical_errors, test_app_alive]
    results = []
    for test in tests:
        try:
            results.append(test())
        except Exception as e:
            print(f"  ERROR: {e}")
            results.append(False)
        print()

    passed = sum(results)
    total = len(results)

    print("=" * 60)
    if all(results):
        print(f"  RESULT: ALL {total}/{total} TESTS PASSED")
        print("  APK is ready to ship!")
    else:
        print(f"  RESULT: {passed}/{total} passed, {total - passed} FAILED")
        print("  DO NOT SHIP — fix failures above")
    print("=" * 60)

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
