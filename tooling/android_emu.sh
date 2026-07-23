#!/usr/bin/env bash
# Start / stop the Riff smoke AVD (API 34).
# Prefer KVM: without /dev/kvm the emulator is software-TCG only and often ANRs.
set -euo pipefail

export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"

AVD_NAME="${AVD_NAME:-riff_api34}"
CMD="${1:-start}"

have_kvm() { [[ -e /dev/kvm ]]; }

start_emu() {
  if ! command -v emulator >/dev/null; then
    echo "Android SDK emulator missing under $ANDROID_HOME" >&2
    exit 1
  fi
  if ! avdmanager list avd 2>/dev/null | grep -q "$AVD_NAME"; then
    echo "Creating AVD $AVD_NAME…"
    echo no | avdmanager create avd -n "$AVD_NAME" \
      -k "system-images;android-34;google_apis;x86_64" -d pixel_6 --force
  fi

  local accel_args=()
  if have_kvm; then
    echo "KVM available — hardware accel on"
    accel_args=(-accel on -gpu host)
  else
    echo "WARNING: no /dev/kvm — software emu (slow, may ANR). Prefer a KVM-enabled snapshot." >&2
    accel_args=(-accel off -gpu swiftshader_indirect)
  fi

  emulator -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim \
    "${accel_args[@]}" -no-snapshot -memory 3072 \
    > /tmp/emulator.log 2>&1 &
  echo $! > /tmp/emulator.pid
  echo "Waiting for boot…"
  adb wait-for-device
  for _ in $(seq 1 120); do
    if [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
      echo "Emulator ready: $(adb devices | grep emulator)"
      flutter devices
      return 0
    fi
    sleep 5
  done
  echo "Boot timed out — see /tmp/emulator.log" >&2
  exit 1
}

stop_emu() {
  adb emu kill 2>/dev/null || true
  if [[ -f /tmp/emulator.pid ]]; then
    kill "$(cat /tmp/emulator.pid)" 2>/dev/null || true
    rm -f /tmp/emulator.pid
  fi
  pkill -f "emulator.*$AVD_NAME" 2>/dev/null || true
  echo "Emulator stopped"
}

case "$CMD" in
  start) start_emu ;;
  stop) stop_emu ;;
  status)
    adb devices
    have_kvm && echo "kvm: yes" || echo "kvm: no"
    ;;
  *)
    echo "Usage: $0 {start|stop|status}" >&2
    exit 2
    ;;
esac
