<div align="center">

# Riff Mobile 🎵

**Stream YouTube Music on Android — no ads, no account, no tracking.**

The mobile counterpart of [Riff](https://github.com/Aimdi/Riff) (the native
Linux player): a true-black OLED look, a private on-device discovery
engine, and a playback stack built to survive YouTube's changes.

[![Build Android APK](https://github.com/Aimdi/Riff-mobile/actions/workflows/build.yml/badge.svg)](https://github.com/Aimdi/Riff-mobile/actions/workflows/build.yml)
[![Latest release](https://img.shields.io/github/v/release/Aimdi/Riff-mobile)](https://github.com/Aimdi/Riff-mobile/releases/latest)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-green)](LICENSE)

[**⬇️ Download the latest APK**](https://github.com/Aimdi/Riff-mobile/releases/latest)

</div>

---

## Features

- 🔍 **Search** songs, albums, artists and playlists on YouTube Music
- 🏠 **Home feed** with charts, moods and recommendations
- 🧭 **Local discovery engine** — a private, on-device taste model builds
  Daily Mixes, Fresh Finds, Release Radar and Rediscover sections from
  what *you* play. No YouTube login exists or is needed: like Riff on the
  desktop, personalization never leaves your phone. Sections appear on
  Home after a handful of listens (tune it in Settings → Riff → Discovery)
- 📻 **Radio / autoplay** — related songs keep playing when your queue ends
- 🗒️ **Full queue control** — play next, enqueue, reorder, shuffle, repeat
- ❤️ **Favorites, history and local playlists**
- ⬇️ **Offline downloads**; downloaded songs play from disk
- 🎤 **Synced lyrics** (LRCLIB) with live highlighting
- 📊 **Stats page** — plays, hours listened, daily activity, top songs and
  artists, exploration insights — all computed on-device (Settings → Riff)
- 🚷 **"Never Play This"** — ban a song from the song menu; banned songs
  stay out of radio and suggestions
- 📻 **ListenBrainz scrobbling** (optional, token in Settings → Riff)
- 🖤 **Pitch Black theme** — true-black OLED default with Riff's green
  accent, plus Blue / Violet / Crimson / Amber variants
- 🎚️ Equalizer, sleep timer, skip silence, streaming quality control
- 🚗 **Android Auto** support
- 🌍 Available in many languages
- 🚫 No ads, no tracking, no Google account — by design

## Why playback keeps working

Most YouTube Music clients break every time YouTube rotates its player
clients or cipher scheme (that's what killed the original Harmony Music
v1.12.2 this app was forked from). Riff Mobile layers the approaches of
the most resilient open-source players:

1. **[NewPipeExtractor](https://github.com/TeamNewPipe/NewPipeExtractor)**
   (the engine behind NewPipe and RiPlay) resolves streams first — it
   tracks YouTube's JS player, signature deciphering, throttling and SABR
   enforcement, and is updated continuously
2. If that fails, a **fallback chain of current, PO-token-free player
   clients** takes over — `ANDROID_VR` and `VISIONOS` payloads
   transplanted from [Metrolist](https://github.com/mostafaalagamy/Metrolist)'s
   client fleet, then sdk-less Android and iOS via
   [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) 3.x
3. Every resolved URL is **validated before it reaches the player**, so a
   dead link falls through to the next resolver instead of failing silently
4. Browse/search requests send a **consent cookie (`SOCS`) and a current
   browser fingerprint**, so the app works on networks where YouTube
   enforces consent walls (e.g. the EU)

The whole YouTube-facing stack is exercised on CI against the real
YouTube Music API (home, charts, search, radio, stream resolution) via
the *YT API diagnostics* workflow.

## Install

Grab an APK from the [releases page](https://github.com/Aimdi/Riff-mobile/releases/latest):

| APK | For |
|---|---|
| `app-arm64-v8a-release.apk` | Most phones (2017+) — **pick this one** |
| `app-armeabi-v7a-release.apk` | Older 32-bit devices |
| `app-release.apk` | Universal (any device, larger) |
| `app-x86_64-release.apk` | Emulators |

Updates install over the existing app (`com.aimdi.riff`). The app checks
this repository's releases and offers new versions in Settings.

## Build from source

```bash
flutter pub get
flutter build apk --release
```

Built with Flutter 3.24.x; APKs land in `build/app/outputs/flutter-apk/`.
Every push builds APKs on CI, and a release can be cut from the *Build
Android APK* workflow with a `release_tag` input.

## Credits

Riff Mobile stands on the shoulders of:

- **[Harmony Music](https://github.com/anandnet/Harmony-Music)** by
  [anandnet](https://github.com/anandnet) — the app this project is
  forked from (no longer maintained upstream)
- **[Riff](https://github.com/Aimdi/Riff)** — design and feature blueprint
- **[NewPipeExtractor](https://github.com/TeamNewPipe/NewPipeExtractor)** —
  stream resolution engine
- **[RiPlay](https://github.com/fast4x/RiPlay)** and
  **[Metrolist](https://github.com/mostafaalagamy/Metrolist)** — the
  playback-resilience playbooks this app borrows from
- [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart),
  [LRCLIB](https://lrclib.net), [ListenBrainz](https://listenbrainz.org)

## License

**GPL-3.0** (see [LICENSE](LICENSE)), as required by the Harmony Music base.

Riff Mobile talks to YouTube Music's public endpoints and is not
affiliated with or endorsed by YouTube. Use at your own discretion.
