#!/usr/bin/env bash
# Runs integration_test/podcast_play_test.dart on the booted emulator while
# recording everything a crash leaves behind: logcat, Android's exit records,
# dropbox crash entries, tombstones and periodic screenshots. Output goes to
# e2e-out/ (uploaded as a workflow artifact); the key lines are printed too.
set -u
PKG=com.aimdi.riff
OUT=e2e-out
mkdir -p "$OUT/shots"

adb wait-for-device
adb root >/dev/null 2>&1 || true
adb wait-for-device
adb logcat -c || true
adb logcat -b all -v threadtime > "$OUT/logcat.txt" 2>&1 &
LOGCAT=$!

(
  i=0
  while true; do
    sleep 6
    i=$((i + 1))
    adb exec-out screencap -p > "$OUT/shots/$(printf '%03d' $i).png" 2>/dev/null || true
  done
) &
SHOTS=$!

flutter test integration_test/podcast_play_test.dart -d emulator-5554 \
  --dart-define=E2E_PODCAST="${E2E_PODCAST:-Handelsblatt Economic Challenges}" \
  -r expanded 2>&1 | tee "$OUT/flutter_test.txt"
STATUS=${PIPESTATUS[0]}

sleep 3
kill $SHOTS $LOGCAT 2>/dev/null || true

adb shell dumpsys activity exit-info $PKG > "$OUT/exit_info.txt" 2>&1 || true
adb shell dumpsys dropbox --print data_app_crash > "$OUT/dropbox_crash.txt" 2>&1 || true
adb shell dumpsys dropbox --print data_app_native_crash > "$OUT/dropbox_native_crash.txt" 2>&1 || true
adb shell dumpsys dropbox --print data_app_anr > "$OUT/dropbox_anr.txt" 2>&1 || true
mkdir -p "$OUT/tombstones"
adb pull /data/tombstones "$OUT/tombstones" >/dev/null 2>&1 || true
adb shell run-as $PKG cat files/last_crash.txt > "$OUT/last_crash.txt" 2>/dev/null || true

echo "================ E2E lines ================"
grep -a "E2E:" "$OUT/flutter_test.txt" || true
echo "================ crashes in logcat ================"
grep -a -n -A40 "FATAL EXCEPTION\|Fatal signal\|\*\*\* \*\*\* \*\*\*\|ANR in $PKG\|Process $PKG .* has died\|Force finishing activity" \
  "$OUT/logcat.txt" | head -400 || true
echo "================ exit info ================"
head -60 "$OUT/exit_info.txt" || true
echo "================ dropbox ================"
head -120 "$OUT/dropbox_crash.txt" "$OUT/dropbox_native_crash.txt" "$OUT/dropbox_anr.txt" || true
echo "================ app log lines ================"
grep -a "flutter\|Harmony Music\|riff\|ExoPlayer\|AudioService\|MediaSession" "$OUT/logcat.txt" | tail -300 || true

exit $STATUS
