# Riff Mobile 🎵

**Riff for Android** — stream YouTube Music with no ads, no account, no
tracking. The mobile counterpart of [Riff](https://github.com/Aimdi/Riff)
(the native Linux player), built on the excellent
[Harmony Music](https://github.com/anandnet/Harmony-Music) by
[anandnet](https://github.com/anandnet), which is no longer maintained.

## Why this exists

Harmony Music v1.12.2 (the last release) stopped playing songs: it pinned a
fork of `youtube_explode_dart` from early 2024, and YouTube has since retired
the player clients and signature-cipher scheme that version relied on, so
every stream request failed. Riff Mobile fixes playback and continues
development with features ported from Riff desktop.

## What's fixed / new compared to Harmony Music v1.12.2

- ✅ **Playback works again** — upgraded to upstream `youtube_explode_dart`
  3.x with current, PO-token-free player clients (`androidVr` first, with
  `androidSdkless` + `ios` fallback)
- 🖤 **Pitch Black theme by default** — Riff's true-black OLED look with the
  signature green accent, plus Blue / Violet / Crimson / Amber accent
  variants (theme dialog)
- 📊 **Stats page** — plays, hours listened, last-7-days activity, top songs
  and top artists, all computed locally (Settings → Riff → Stats)
- 🚷 **"Never Play This"** — ban a song from the song menu; banned songs stay
  out of radio and up-next suggestions (manage in Settings → Riff)
- 📻 **ListenBrainz scrobbling** — optional; add your user token in
  Settings → Riff
- 📦 **Android-only focus** — desktop/iOS targets removed; CI builds APKs on
  every push and attaches them to releases on tags

Everything Harmony Music already did well is still here: search, radio,
queue control, playlists/favorites/history, downloads, synced lyrics
(LRCLIB), equalizer, Android Auto, sleep timer, skip silence, dynamic
themes, many languages.

## Install

Grab the latest APK from the
[releases page](https://github.com/Aimdi/Riff-mobile/releases) (universal or
per-ABI). It installs alongside the original Harmony Music app
(`com.aimdi.riff` application id).

## Build

```bash
flutter pub get
flutter build apk --release
```

Built with Flutter 3.24.x. APKs land in `build/app/outputs/flutter-apk/`.

## Credits & license

- [Harmony Music](https://github.com/anandnet/Harmony-Music) — the base of
  this app (GPL-3.0)
- [Riff](https://github.com/Aimdi/Riff) — design and feature inspiration
- [RiPlay](https://github.com/fast4x/RiPlay) — inspiration
- [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart),
  [ytmusicapi](https://github.com/sigma67/ytmusicapi) (protocol reference),
  [LRCLIB](https://lrclib.net)

Licensed under **GPL-3.0** (see [LICENSE](LICENSE)), as required by the
Harmony Music base.

Streaming uses YouTube Music's public endpoints; this project is not
affiliated with or endorsed by YouTube. Use at your own discretion.
