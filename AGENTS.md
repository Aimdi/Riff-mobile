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
- Tests: prefer running suites explicitly —
  `flutter test test/discovery test/podcast_episode_parse_test.dart`
  (pure unit) and `flutter test test/yt_e2e_diagnose_test.dart -r expanded`
  (hits the **live** YouTube Music / Apple / KuGou APIs; needs network
  egress, which works in this VM).
- `test/widget_test.dart` is the **stale default Flutter counter test** and
  fails on purpose against this app's `MyApp` — do not treat its failure as an
  environment problem, and note that a bare `flutter test` will report it.
- Dev build: `flutter build apk --debug` → `build/app/outputs/flutter-apk/`.
  First build downloads Gradle + auto-installs extra SDK platforms (31/33).
  Release build (`flutter build apk --release`) uses `android/key.properties`
  + `android/riff-release.keystore` (both committed).

### Running the app / GUI testing

There is **no `/dev/kvm`** in this VM, so a hardware-accelerated Android
emulator is not available and a software emulator is impractically slow.
Validate core functionality (search, home feed, stream resolution) via
`test/yt_e2e_diagnose_test.dart` instead of a GUI run. The app targets Android
only (no web/Linux desktop entry point).
