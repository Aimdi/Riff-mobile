# AGENTS.md

## Cursor Cloud specific instructions

Riff Mobile is a Flutter **Android** app (YouTube Music streaming). Package
name `harmonymusic`, app id `com.aimdi.riff`. See `README.md` and
`ARCHITECTURE_NOTES.md` for product/architecture; standard build commands
live in `README.md` and CI in `.github/workflows/`.

### Toolchain (already installed in the VM snapshot)

- Flutter **3.24.2** stable at `/opt/flutter` (matches CI).
- Android SDK at `~/android-sdk` (platform 34, build-tools 34.0.0, NDK
  `26.1.10909125` required by `android/app/build.gradle`).
- `JAVA_HOME`, `ANDROID_SDK_ROOT`/`ANDROID_HOME`, and the tool `bin` dirs are
  exported in `~/.bashrc`. A login/interactive shell picks these up; if you
  run from a non-interactive shell, use absolute paths or `source ~/.bashrc`.

### JDK gotcha

The VM has **both JDK 17 and JDK 21**. This project must build with **JDK 17**
(`android/app/build.gradle` pins Java/Kotlin to 17). `JAVA_HOME` is set to
`/usr/lib/jvm/java-17-openjdk-amd64` in `~/.bashrc` — keep it there; building
with JDK 21 will fail the Gradle/AGP step.

### Lint / test / build

- Lint: `flutter analyze` (clean on this repo).
- Tests: `flutter test --exclude-tags live` runs the offline suite — this is
  what CI runs on every push, and it must stay green.
- `flutter test test/yt_e2e_diagnose_test.dart -r expanded` runs the suite
  tagged `live`, which hits the **real** YouTube Music / Apple / KuGou APIs;
  it needs network egress (works in this VM). Running it by path ignores the
  tag filter. The *YT API diagnostics* workflow runs it nightly, so a YouTube
  change surfaces there rather than in user reports.
- Tags are declared in `dart_test.yaml`. Any new suite that reaches a
  third-party API over the network belongs under the `live` tag.
- Dev build: `flutter build apk --debug` → `build/app/outputs/flutter-apk/`.
  First build downloads Gradle + auto-installs extra SDK platforms (31/33).
  Release build (`flutter build apk --release`) uses
  `android/key.properties` + `android/riff-release.keystore`. CI needs these
  present for in-place APK updates; they are currently tracked for that reason
  (also listed in `android/.gitignore` for local overrides). Prefer moving them
  to GitHub Actions secrets when available. If missing, Gradle falls back to
  debug signing — do **not** ship that to users who already have a release build.

### Running the app / GUI testing

There is **no `/dev/kvm`** in this VM, so a hardware-accelerated Android
emulator is not available and a software emulator is impractically slow.
Validate core functionality (search, home feed, stream resolution) via
`test/yt_e2e_diagnose_test.dart` instead of a GUI run.

### Linux desktop build

The app also ships for Linux x86_64 (`linux/`, binary `riff-mobile`, GTK
application id `com.aimdi.RiffMobile`). `flutter build linux --release` needs
`clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev libsecret-1-dev
libayatana-appindicator3-dev`, a JDK (package:jni) and Rust (audiotags). CI
builds the tarball on ubuntu-24.04 (libmpv.so.2, as on Arch), then builds, installs and launches the Arch
package (`packaging/arch/PKGBUILD`) in an `archlinux` container. Desktop
branches use `GetPlatform.isDesktop`/`isLinux`; Android-only plugins
(WebView, permission_handler, the `riff/*` method channels, jni) must stay
behind Android checks.
