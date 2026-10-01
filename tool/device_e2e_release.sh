#!/usr/bin/env bash
# Drives the RELEASE apk (R8-shrunk, AOT) the way a user does, with adb only:
# open a YouTube Music podcast show by link, tap "Latest episode", let it
# play, send the app to the background and bring it back. Records logcat,
# exit records, dropbox crashes, tombstones and screenshots to e2e-out/.
set -u
PKG=com.aimdi.riff
APK=build/app/outputs/flutter-apk/app-release.apk
SHOW="${E2E_SHOW:-MPSPPLm1CBZ_iYYaqR4QSDSPq8ChTWbSrNm4Sl}"
OUT=e2e-out
mkdir -p "$OUT/shots"
n=0
shot() {
  n=$((n + 1))
  adb exec-out screencap -p > "$OUT/shots/$(printf '%02d' $n)-$1.png" 2>/dev/null || true
}
alive() { adb shell pidof $PKG >/dev/null 2>&1 && echo yes || echo NO; }
# Taps the centre of the first on-screen node whose text or description
# matches $1 (Flutter publishes its semantics to the accessibility tree).
tap_text() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml "$OUT/ui-$1.xml" >/dev/null 2>&1
  local b
  b=$(python3 - "$OUT/ui-$1.xml" "$1" <<'PY'
import re, sys, xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    sys.exit(0)
want = sys.argv[2].lower()
for node in root.iter('node'):
    label = (node.get('text', '') + ' ' + node.get('content-desc', '')).lower()
    if want in label:
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds', '')))
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
PY
)
  if [ -n "$b" ]; then
    echo "E2E: tap '$1' at $b"
    adb shell input tap $b
  else
    echo "E2E: '$1' not found on screen"
  fi
}

adb wait-for-device
adb root >/dev/null 2>&1 || true
adb wait-for-device
adb install -r "$APK"
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
adb logcat -c || true
adb logcat -b all -v threadtime > "$OUT/logcat.txt" 2>&1 &
LOGCAT=$!

adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 20; shot home; echo "E2E: after launch alive=$(alive)"

adb shell am start -a android.intent.action.VIEW \
  -d "https://music.youtube.com/playlist?list=$SHOW" $PKG >/dev/null
sleep 25; shot show; echo "E2E: show page alive=$(alive)"

tap_text "latest episode"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  sleep 5; shot "play$i"; echo "E2E: playing +$((i * 5))s alive=$(alive)"
done

tap_text "+30"
sleep 10; shot after-skip; echo "E2E: after skip alive=$(alive)"

adb shell input keyevent KEYCODE_HOME
sleep 20; echo "E2E: background alive=$(alive)"
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 10; shot resumed; echo "E2E: resumed alive=$(alive)"

tap_text "next"
sleep 30; shot next; echo "E2E: next episode alive=$(alive)"

kill $LOGCAT 2>/dev/null || true
adb shell dumpsys activity exit-info $PKG > "$OUT/exit_info.txt" 2>&1 || true
adb shell dumpsys dropbox --print data_app_crash > "$OUT/dropbox_crash.txt" 2>&1 || true
adb shell dumpsys dropbox --print data_app_native_crash > "$OUT/dropbox_native_crash.txt" 2>&1 || true
adb shell dumpsys dropbox --print data_app_anr > "$OUT/dropbox_anr.txt" 2>&1 || true
mkdir -p "$OUT/tombstones"
adb pull /data/tombstones "$OUT/tombstones" >/dev/null 2>&1 || true
adb shell cat /data/data/$PKG/files/last_crash.txt > "$OUT/last_crash.txt" 2>/dev/null || true
adb shell cat /data/data/$PKG/files/riff_log.txt > "$OUT/riff_log.txt" 2>/dev/null || true

echo "================ crashes in logcat ================"
grep -a -n -A60 "FATAL EXCEPTION\|Fatal signal\|\*\*\* \*\*\* \*\*\*\|ANR in $PKG\|Process $PKG .* has died\|Force finishing activity" \
  "$OUT/logcat.txt" | head -500 || true
echo "================ exit info ================"
head -80 "$OUT/exit_info.txt" || true
echo "================ dropbox ================"
grep -v "^Drop box\|^Max entries\|^Low priority" "$OUT/dropbox_crash.txt" "$OUT/dropbox_native_crash.txt" "$OUT/dropbox_anr.txt" | head -200 || true
echo "================ recorded crash ================"
cat "$OUT/last_crash.txt" || true
echo "================ app diagnostics log ================"
tail -150 "$OUT/riff_log.txt" || true
exit 0
