#!/usr/bin/env bash
# Install debug APK on a connected Android device/emulator and capture a screenshot.
set -euo pipefail

export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export PATH="$PATH:$ANDROID_HOME/platform-tools"

PKG=com.aimdi.riff
ACTIVITY=com.anandnet.harmonymusic.MainActivity
OUT_DIR="${OUT_DIR:-/opt/cursor/artifacts/screenshots}"
APK="${APK:-build/app/outputs/flutter-apk/app-debug.apk}"

mkdir -p "$OUT_DIR"

if ! adb devices | grep -E 'device$'; then
  echo "No Android device/emulator online. Run tooling/android_emu.sh start" >&2
  exit 1
fi

if [[ ! -f "$APK" ]]; then
  echo "Building debug APK…"
  flutter build apk --debug
fi

adb install -r "$APK"
adb shell am force-stop "$PKG" || true
adb shell am start -n "$PKG/$ACTIVITY"
sleep "${SMOKE_WAIT_SECS:-20}"

SHOT="$OUT_DIR/riff-smoke-$(date +%Y%m%d-%H%M%S).png"
adb exec-out screencap -p > "$SHOT"
echo "Screenshot: $SHOT"
adb shell dumpsys window | grep -E 'mCurrentFocus|mFocusedApp' | head -5 || true
