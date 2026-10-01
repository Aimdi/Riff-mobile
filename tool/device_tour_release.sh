#!/usr/bin/env bash
# Tours the RELEASE apk with adb only (R8 + resource shrinking apply): every
# bottom-bar tab, an artist, album and playlist opened by link, a song
# played by link, and the app backgrounded and resumed. Records logcat,
# crash records, the app's own diagnostic log and screenshots to e2e-out/.
set -u
PKG=com.aimdi.riff
APK=build/app/outputs/flutter-apk/app-release.apk
OUT=e2e-out
mkdir -p "$OUT/shots"
n=0
shot() { n=$((n + 1)); adb exec-out screencap -p > "$OUT/shots/$(printf '%02d' $n)-$1.png" 2>/dev/null || true; }
alive() { adb shell pidof $PKG >/dev/null 2>&1 && echo yes || echo NO; }
step() { echo "TOUR: $1 alive=$(alive)"; shot "$2"; }
tap_text() {
  local b="" try
  for try in 1 2 3 4; do
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb pull /sdcard/ui.xml "$OUT/ui.xml" >/dev/null 2>&1
    b=$(python3 - "$OUT/ui.xml" "$1" <<'PY'
import re, sys, xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    sys.exit(0)
want = sys.argv[2].lower()
for node in root.iter('node'):
    label = (node.get('text', '') + ' ' + node.get('content-desc', '')).strip().lower()
    if label == want or label.startswith(want + '\n') or label.startswith(want + ' '):
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds', '')))
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
PY
)
    [ -n "$b" ] && break
    sleep 3
  done
  if [ -n "$b" ]; then echo "TOUR: tap '$1'"; adb shell input tap $b; else echo "TOUR: '$1' not on screen"; fi
}
open_link() { adb shell am start -a android.intent.action.VIEW -d "$1" $PKG >/dev/null 2>&1; }
relaunch_if_dead() { [ "$(alive)" = "NO" ] && echo "TOUR: !!! app died, relaunching" && adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 && sleep 12; }

adb wait-for-device
adb root >/dev/null 2>&1 || true
adb wait-for-device
adb install -r "$APK"
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
adb logcat -c || true
adb logcat -b all -v threadtime > "$OUT/logcat.txt" 2>&1 &
LOGCAT=$!

adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 20; step "home" home
adb shell input swipe 540 1800 540 600 300; sleep 2; adb shell input swipe 540 600 540 1800 300

for tab in Songs Podcasts Audiobooks Playlists Albums Artists Settings Home; do
  tap_text "$tab"; sleep 5; step "tab $tab" "tab-$tab"
  adb shell input swipe 540 1800 540 600 300; sleep 2
  relaunch_if_dead
done

open_link "https://music.youtube.com/channel/UCDPM_n1atn2ijUwHd0NNRQw"   # Coldplay
sleep 15; step "artist page" artist; relaunch_if_dead
adb shell input swipe 540 1800 540 600 300; sleep 2
adb shell input keyevent KEYCODE_BACK; sleep 2

open_link "https://music.youtube.com/playlist?list=MPSPPLm1CBZ_iYYaqR4QSDSPq8ChTWbSrNm4Sl"  # a podcast show
sleep 20; step "podcast show" podcast; relaunch_if_dead
tap_text "latest episode"; sleep 15; step "podcast episode" episode; relaunch_if_dead
adb shell input keyevent KEYCODE_BACK; sleep 2

open_link "https://music.youtube.com/watch?v=dvgZkm1xWPE"  # Viva la Vida
sleep 20; step "song playing" song; relaunch_if_dead
tap_text "next"; sleep 8; step "next song" next; relaunch_if_dead

adb shell input keyevent KEYCODE_HOME; sleep 15; echo "TOUR: background alive=$(alive)"
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 10; step "resumed" resumed

kill $LOGCAT 2>/dev/null || true
adb shell dumpsys dropbox --print data_app_crash > "$OUT/dropbox_crash.txt" 2>&1 || true
adb shell dumpsys dropbox --print data_app_native_crash > "$OUT/dropbox_native_crash.txt" 2>&1 || true
adb shell cat /data/data/$PKG/files/riff_log.txt > "$OUT/riff_log.txt" 2>/dev/null || true

echo "================ crashes in logcat ================"
grep -a -n -A50 "FATAL EXCEPTION\|Fatal signal\|ANR in $PKG" "$OUT/logcat.txt" | head -400 || true
echo "================ app errors (diagnostic log) ================"
grep -a " E \| W " "$OUT/riff_log.txt" | sort | uniq -c | sort -rn | head -80 || true
exit 0
