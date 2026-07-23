# Riff agent UI test tooling

## What this environment can do

| Path | Status | Notes |
|------|--------|-------|
| **Android emulator + APK smoke** | Scripted (`android_emu.sh`, `smoke_ui.sh`) | Needs **`/dev/kvm`**. Without KVM, TCG software emu often ANRs and is not useful for layout QA. |
| **Flutter widget / unit tests** | Always | Fast; use for insets, sync policy, Wave seeds, etc. |
| **Linux desktop (`flutter run -d linux`)** | Available when GTK/ninja installed | Good for chrome/layout iteration; not a phone form factor. |

## One-time SDK install (already done on this VM)

```bash
# ANDROID_HOME=/opt/android-sdk with platform-tools, emulator, API 34 google_apis x86_64
export ANDROID_HOME=/opt/android-sdk
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
```

Bake `/opt/android-sdk` + `~/.android/avd/riff_api34*` into the **Cursor environment snapshot** so agents don’t re-download ~1GB each run.

## Daily smoke

```bash
tooling/android_emu.sh start   # prefers KVM
tooling/smoke_ui.sh            # install debug APK + screencap → /opt/cursor/artifacts/screenshots
tooling/android_emu.sh stop
```

## Enabling real phone-like QA

Ask for a cloud environment / VM with **nested virtualization / `/dev/kvm`**. Then the same scripts become a usable Android 14 Pixel-class smoke harness for long-press sheets, mini player overlap, podcast controls, etc.
