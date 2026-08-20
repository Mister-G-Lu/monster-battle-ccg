#!/usr/bin/env bash
# Collect the useful crash evidence after reproducing a startup failure.
# Usage: ./scripts/collect_android_logs.sh [package.name]
set -euo pipefail

PACKAGE="${1:-com.mu77.english}"
OUT_DIR="build/android-diagnostics/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT_DIR"

if ! command -v adb >/dev/null; then
  echo "adb was not found. Install Android Platform Tools, connect BlueStacks, then rerun." >&2
  exit 2
fi

adb get-state >/dev/null
echo "Writing diagnostics to $OUT_DIR"
adb devices -l > "$OUT_DIR/devices.txt"
adb shell getprop > "$OUT_DIR/device-properties.txt"
adb shell dumpsys package "$PACKAGE" > "$OUT_DIR/package.txt" || true
adb logcat -d -v threadtime > "$OUT_DIR/logcat-full.txt"
# Cocos normally exposes its writable path under Android/data. This may be
# blocked by newer Android storage policy; failure is non-fatal.
adb shell "cat /sdcard/Android/data/$PACKAGE/files/offline_debug.log" \
  > "$OUT_DIR/offline_debug.log" 2>/dev/null || true
grep -Ei 'FATAL EXCEPTION|Fatal signal|AndroidRuntime|libcocos|LUA ERROR|\[OFFLINE\]|\[GLOBAL\]|\[LOGIN_SCENE\]|\[NETWORK\]|mu77' \
  "$OUT_DIR/logcat-full.txt" > "$OUT_DIR/logcat-startup-focus.txt" || true

echo "Saved full logcat and filtered startup log. Attach $OUT_DIR/logcat-startup-focus.txt when reporting a crash."
