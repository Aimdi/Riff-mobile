# Riff Mobile — Architecture Notes (Discovery)

Living notes for the on-device discovery / stats stack. Prefer this over
Phase-0 recon comments in older branches.

## Stack

| Layer | Technology |
|-------|------------|
| UI / state | Flutter + GetX (`GetxController`, `GetxService`, `.obs`) |
| Playback | `just_audio` + `audio_service` (`MyAudioHandler` in `lib/services/audio_handler.dart`) |
| Network music | In-house InnerTube client `MusicServices` (`lib/services/music_service.dart`) |
| Persistence | Hive boxes under app documents (opened in `main.dart` / on demand) |
| Models | No custom `Song` class — tracks are `audio_service.MediaItem` via `MediaItemBuilder` |
| Localization | JSON under `localization/`, generated into `lib/utils/get_localization.dart` via `localization/generator.dart` |

Package name remains `harmonymusic` (pubspec). App id: `com.aimdi.riff`.

## Discovery source (`extras['discoverySource']`)

Allowed wire values (see `DiscoverySource` in
`lib/services/discovery/discovery_types.dart`):

`user_click`, `home`, `search`, `playlist`, `album`, `artist`, `radio`,
`daily_mix`, `fresh_finds`, `discover`, `related`, `similar`, `queue`,
`shuffle`, `smart_shuffle`, `android_auto`, `cloud`, `podcast`,
`audiobook`, `downloads`, `soulseek`, `torrent`, `unknown`.

Helpers in `lib/services/discovery/discovery_tag.dart`:

- `ensureDiscoverySource` — stamp only if missing
- `withDiscoverySource` / `DiscoveryService.withSource` — overwrite
- `sourceFromPlaylingFrom` / `sourceFromPlaylistId`

`PlayerController.playPlayListSong` tags untagged items from the optional
`source` argument or the `PlaylingFrom` type. `enqueueSong` / play-next
default to `queue`. Radio / similar / mixes keep the engine tag.

`MediaItemBuilder` round-trips `discoverySource`. Android Auto library
songs keep extras and force `android_auto`.

## Listen fraction + stats

- `DiscoveryService.onMediaChanged` / `onPositionTick` close the previous
  track and call `TasteModel.logPlayEnded` (affinity + `riff_events`).
- The same close path calls `StatsService.recordListenEnd`.
- `StatsService.recordPlay` increments play count + `lastSource` only.
  Seconds, skips, and partials are written on end:
  - skip: &lt; 30% (or &lt; 10s when duration unknown)
  - partial: 30–85%
  - complete: ≥ 85%
- Hive: `SongStats` / `DailyStats` (legacy) plus `riff_*` boxes via
  `DiscoveryRepository`.

## Smart radio + similar songs

- `PlayerController.pushSongToQueue` / `_addRadioContinuation` /
  `startRiffWave` use `DiscoveryService.smartRadioBatch` with YTM radio
  fallback.
- `SongInfoBottomSheet` + `SimilarSongsSheet` + `PlayerSimilarRow` use
  `DiscoveryEngine.similarSongs`.
- Ban filter: `BanService.filterTracks` in `getWatchPlaylist` and
  `BanServiceSafe` inside the engine / mix generator. Artist and
  collection bans live in `BannedArtists` / `BannedCollections`.

## Mixes + Android Auto

- `Playlist.kind`: `daily_mix`, `fresh_finds`, `release_radar`,
  `rediscover` (null = user).
- `DiscoveryService.materializeMixPlaylists` writes `RIFF_{mix.id}` into
  `LibraryPlaylists`.
- Auto root: Songs, Favorites, Albums, Playlists, Daily Mixes, Fresh Finds.

## Battery optimization

Settings tile + one-time prompt after the first play
(`shouldPromptBatteryOptimization` / `maybePromptBatteryOptimization`).
Manifest: `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.

## Remaining follow-ups

- GetX controller sprawl (queue / favorites / library duplication)
- Stronger typing around `MediaItem.extras` maps
- Adopt `SongListShimmer` on remaining list screens
- Gapless / crossfade and cache/image expiry
