#!/usr/bin/env bash
# Runs integration_test/app_tour_test.dart on the booted emulator and records
# logcat and screenshots to e2e-out/. Prints the tour log and any crash.
set -u
PKG=com.aimdi.riff
OUT=e2e-out
mkdir -p "$OUT/shots"
adb wait-for-device
adb logcat -c || true
adb logcat -b all -v threadtime > "$OUT/logcat.txt" 2>&1 &
LOGCAT=$!
( i=0; while true; do sleep 8; i=$((i + 1));
  adb exec-out screencap -p > "$OUT/shots/$(printf '%03d' $i).png" 2>/dev/null || true; done ) &
SHOTS=$!

flutter test integration_test/app_tour_test.dart -d emulator-5554 -r expanded \
  --dart-define=RIFF_E2E_STREAM_URL=https://archive.org/download/art_of_war_librivox/art_of_war_09-10_sun_tzu_64kb.mp3 \
  2>&1 | tee "$OUT/flutter_test.txt"
STATUS=${PIPESTATUS[0]}
sleep 2
kill $SHOTS $LOGCAT 2>/dev/null || true

echo "================ tour ================"
grep -a "TOUR:" "$OUT/flutter_test.txt" || true
echo "================ uncaught test errors ================"
grep -a -B2 -A14 "EXCEPTION CAUGHT\|\[E\]" "$OUT/flutter_test.txt" | head -300 || true
echo "================ crashes in logcat ================"
grep -a -n -A50 "FATAL EXCEPTION\|Fatal signal\|ANR in $PKG" "$OUT/logcat.txt" | head -300 || true
exit 0
