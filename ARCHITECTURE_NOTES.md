# Riff Mobile — Architecture Notes (Discovery)

Phase 0 recon for the discovery redesign. All later phases reference these names and hook points.

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

## Services (GetX)

Registered in `startApplicationServices()` (`lib/main.dart`):

- `MusicServices` — InnerTube browse/search/next
- `PlayerController` — queue, radio, favorites, lyrics
- `HomeScreenController` — home feed
- `LibrarySongsController` / `LibraryPlaylistsController` / `LibraryAlbumsController` / `LibraryArtistsController`
- `SettingsScreenController`, `Downloader`, `PipedServices`
- `AudioHandler` put permanently as `Get.put<AudioHandler>(await initAudioService())`

Riff-only static helpers (not GetX services):

- `StatsService` — `SongStats`, `DailyStats` boxes
- `BanService` — `BannedSongs` box
- `ListenBrainzService` — scrobble only (write)

## Music service API surface

File: `lib/services/music_service.dart`

| Method | Purpose |
|--------|---------|
| `getHome({limit})` | Anonymous YTM home sections |
| `getCharts(category)` / `getChartItems` | Charts / moods |
| `getWatchPlaylist({videoId, playlistId, limit, radio, shuffle, additionalParamsNext, onlyRelated})` | Queue + radio via `next`; returns `tracks`, `lyrics`, **`related`** (browseId), `additionalParamsForNext` |
| `getContentRelatedToSong(videoId, hlCode)` | Related sections via `related` browseId from `next` |
| `getPlaylistOrAlbumSongs` | Playlist / album tracks |
| `search` / `getSearchSuggestion` / `getSearchContinuation` | Search |
| `getArtist(channelId)` | Artist page (top songs, albums, related artists under parsed contents) |
| `getArtistRealtedContent` | Continuation for artist songs/videos/etc. |
| `getSongWithId` / `getSongYear` | Single song helpers |

**Related songs already available:** `getWatchPlaylist(..., onlyRelated: true)` → `related` browseId; `getContentRelatedToSong` browses it. Radio continuation is `getWatchPlaylist` with `radio: true` + `additionalParamsNext`.

Ban filtering is applied inside `getWatchPlaylist` via `BanService.filterTracks`.

## Player & skip hooks

### Play start

`PlayerController._listenForChangesInDuration` → on `mediaItem` change:

- sets `currentSong`
- `_addToRP` (recently played → Hive `LIBRP`)
- **`StatsService.recordPlay`** (only start, full duration assumed)
- `ListenBrainzService.submitListen`
- radio auto-continuation when last queue item

### Skip / next

- UI: `PlayerController.next()` → `_audioHandler.skipToNext()`
- Notification / Android Auto / headset: `MyAudioHandler.skipToNext()` → `customAction("playByIndex")` (same path as UI)
- **No listen-fraction tracking today** — only play-start is recorded

### Queue source

`MediaItem.extras` currently holds `url`, `length`, `album`, `artists`, `date`, etc.  
**No discovery source field** — add `extras['discoverySource']` (and preserve through `MediaItemBuilder`).

### Radio

- `PlayerController.startRadio` / `pushSongToQueue(..., radio: true)`
- Continuation: `_addRadioContinuation` → raw `getWatchPlaylist` tracks enqueued with **no post-processing** beyond ban filter in music service

## Hive box inventory

Opened at startup (`initHive`):

| Box | Role |
|-----|------|
| `SongsCache` | Cached songs |
| `SongDownloads` | Downloads |
| `SongsUrlCache` | Stream URL cache |
| `AppPrefs` | Settings (incl. `discoverContentType`, `visitorId`, ListenBrainz token) |
| `BannedSongs` | Never Play This |
| `SongStats` | Per-videoId `{title, artist, plays, seconds, lastPlayed}` |
| `DailyStats` | Per-day `{plays, seconds}` |

Opened on demand:

| Box | Role |
|-----|------|
| `LIBFAV` | Favorites |
| `LIBRP` | Recently played |
| `LibraryPlaylists` / per-playlistId | User playlists |
| `LibraryAlbums` / `LibraryArtists` | Bookmarked albums/artists (**follow ≈ LibraryArtists**) |
| `homeScreenData` | Cached home feed |
| `prevSessionData` | Session restore |
| `searchQuery`, `lyrics`, `blacklistedPlaylist` | Misc |

## Navigation shell

- Nested navigator: `lib/ui/navigator.dart` (`ScreenNavigationSetup`)
- Bottom nav (optional): Home · Search · Library · Settings — **4 tabs, full**
- Side nav when bottom nav disabled: more library destinations
- **Decision: no new Discover tab** — restructure Home (§3.1); Settings → Riff → Discovery for prefs

## Home today

`HomeScreenController.loadContentFromNetwork`:

- `discoverContentType`: `QP` (quick picks) / `TR` / `TMV` / `BOLI` (based on last interaction)
- Sections from `MusicServices.getHome` → `quickPicks`, `middleContent`, `fixedContent`
- Cached 8h in `homeScreenData`

## Stats & ban

- Stats: play-count only, no skips, no source
- Ban: song-level hard drop from radio/up-next suggestions
- Artist library bookmark = local follow candidate for Release Radar

## Android Auto

`MediaLibrary` in `audio_handler.dart`: root nodes Songs, Favorites, Albums, Playlists.  
Mix folders can be added next to these once mixes are materialized playlists.

## Playlist model

`Playlist` (`lib/models/playlist.dart`): `playlistId`, `title`, `description`, `thumbnailUrl`, `isPipedPlaylist`, `isCloudPlaylist`.  
System playlists use fixed ids (`LIBFAV`, `LIBRP`, `SongsCache`, `SongDownloads`).  
**Extend with optional `kind`** for system mixes (`daily_mix`, `fresh_finds`, etc.) via JSON field (default null = user).

## Localization

Add English keys to `localization/en.json`, run `dart run localization/generator.dart` (or regenerate `get_localization.dart`).  
User-facing discovery strings must use `.tr`.

## Discovery integration points (for implementers)

1. **Event log on play start/end** — `PlayerController._listenForChangesInDuration` + position fraction before advance
2. **Source on queue items** — set `extras['discoverySource']` in `pushSongToQueue`, `enqueueSong*`, radio, mixes
3. **Smart radio** — wrap `_addRadioContinuation` / radio track list through `DiscoveryEngine.smartRadioBatch`
4. **Similar songs** — `SongInfoBottomSheet` + player UI → `DiscoveryEngine.similarSongs`
5. **Explicit signals** — fav (`toggleFavourite` / `SongInfoController.toggleFav`), ban (`BanService.ban`), download (`Downloader`), follow (`ArtistScreenController.addNremoveFromLibrary`)
6. **Home** — prepend personal sections from `DiscoveryEngine.homeSections` before YTM content
7. **Resume scheduler** — `LifecycleHandler.didChangeAppLifecycleState(resumed)` + app start after first frame
8. **Settings → Riff** — Discovery subsection + temporary taste debug page
9. **New Hive boxes** — behind repositories only (`riff_*` names per §5)

## Related endpoint note

`getWatchPlaylist` already returns `related` browseId. No service change required for seed→related unless a thinner convenience method is desired:

```dart
// optional convenience
Future<List<MediaItem>> getRelatedTracks(String videoId) async { ... }
```
