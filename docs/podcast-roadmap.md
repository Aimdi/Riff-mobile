# Podcast roadmap

Scope: the **Podcasts section only**. Nothing here goes into the global
Settings screen, the music Library, the main Home feed or music-only screens,
and music playback behaves exactly as before. Ideas are inspired by other
podcast apps; the UI, names, icons and wording are Riff's own.

Status: **Phase 1 shipped in 1.7.122, Phase 2 implemented (1.7.123).**
Phases 3–5 are planned; each starts after the previous one is reviewed.

---

## 0. How the app works today (exploration, Oct 2026)

**Stack**
- State: GetX (`GetxController`, `.obs`, `Obx`). Services are registered in
  `lib/main.dart`.
- Storage: Hive. Boxes are opened in `lib/main.dart` by `initHiveCritical()`
  (needed before first paint) and `initHiveDeferred()` (the podcast boxes),
  both through `safeOpenBox` (`lib/utils/hive_safe_open.dart`), which deletes
  and recreates a corrupt box. Settings live in the `AppPrefs` box. Code that
  can run before the deferred open checks `Hive.isBoxOpen` first.
- Audio: just_audio + audio_service. `MyAudioHandler`
  (`lib/services/audio_handler.dart`) owns one `AudioPlayer` with no
  `AudioPipeline`. Audio effects (bass boost, loudness enhancer, reverb,
  virtualizer) are native and bound to the session id over the
  `riff/newpipe` channel (`AudioFx` in
  `android/app/src/main/kotlin/com/anandnet/harmonymusic/NewPipeChannel.kt`).
- Music and podcasts share **one playback queue** (the handler's `queue`,
  mirrored to `PlayerController.currentQueue`). The podcast "Up Next"
  (`PodcastQueueController`, box `PodcastQueue`) is a separate list. Only
  `_triggerNext` in the handler reads it, appending the rest when an
  episode ends.

**Podcast data**
- RSS shows: `PodcastService` (`lib/services/podcast_service.dart`) parses
  feeds on an isolate into plain maps. Episode ids are
  `podcast_<guid hash>`. Fields include `pubDateMs`, `durationSec`,
  `chaptersUrl`, `transcriptUrl` and `transcriptType`. Subscriptions are in
  box `PodcastSubs`, keyed by feed URL.
- YouTube shows: `youtube_podcast_service.dart`, plus YouTube Music
  podcasts via `MusicServices.getPodcast`. The `MediaItem.id` is the video
  id. Extras carry `podcastSource` (`yt_podcast`, `yt_channel` or
  `yt_music_podcast`) and sometimes `podcastPlaylistId`. They are stored in
  the `LibraryPodcasts` box as `Playlist`.
- Episode to `MediaItem`: `podcastEpisodeToMediaItem`
  (`lib/ui/widgets/podcast_play.dart`). It sets `isPodcast`, `feedUrl`,
  `url`, `chaptersUrl`, `transcriptUrl` and `transcriptType`, with the show
  title in `artist`. The check used everywhere is
  `MediaItem.isPodcastEpisode` (`lib/models/media_item_extras.dart`).
- Progress: `PodcastProgressService` (boxes `PodcastProgress` and
  `PodcastPlayed`). Downloads: `PodcastDownloadService` (box
  `PodcastDownloads`).

**Podcast UI**
- Podcasts tab: `lib/ui/screens/Podcasts/podcasts_library.dart`. Its header
  has the title, a refresh button on Inbox, the autoplay toggle and the
  gear. The pill tabs are Inbox, Queue, Subscriptions, Discover and
  Downloads.
- Show page: `PodcastShowView` (`podcast_show_view.dart`) is shared by RSS
  shows (`PodcastEpisodesScreen` in `podcasts_screen.dart`) and YouTube
  shows (`_PodcastShow` in `lib/ui/screens/Playlist/playlist_screen.dart`).
- Player: `lib/ui/player/player.dart` routes podcast and audiobook items to
  `LongFormPlayer` (`components/long_form_player.dart`). Music uses
  `StandardPlayer` or `GesturePlayer`. `PlayerControlWidget` also has a
  rarely used podcast branch (`_podcastControls`).
- Sleep timer: app-wide. `PlayerController.startSleepTimer`,
  `sleepEndOfSong` and the sheet in
  `lib/ui/widgets/sleep_timer_bottom_sheet.dart`.

**Existing work to build on**
- Chapter ad skip (v1.7.25, commit `ba3a959`):
  `PodcastService.chapters()` parses Podcasting 2.0 JSON chapters.
  `PodcastChapter.isAd` matches sponsor, advert and promo titles. The
  skipping is `PlayerController._maybeSkipAdChapter`, and the "Skip ad" pill
  is in `long_form_player.dart` and `player_control.dart`. The toggle is
  `podcastAutoSkipAds` in AppPrefs, currently also shown in global Settings
  › Podcasts.
- SponsorBlock: `lib/services/sponsorblock_service.dart` calls
  `skipSegments?videoID=` (not hash-prefix) and caches in memory only.
  It runs for every YouTube video, music included. The skip logic is
  `PlayerController._maybeSkipSponsorBlock`.
- Transcripts already exist: `PodcastService.transcript()` parses
  Podcasting 2.0 JSON, SRT, VTT, plain text and HTML, and
  `PodcastTranscriptSheet` has live highlight and tap-to-seek.
- Podcast folders exist (`PodcastFolderController`, box `PodcastFolders`),
  but they only hold YouTube library shows, not RSS subscriptions.

**Theming, l10n, tests**
- Artwork theming: `ThemeController.setTheme(imageProvider, songId)`
  (`lib/ui/utils/theme_controller.dart`).
- Strings: add the key to `localization/en.json` **and** the `en` map in
  `lib/utils/get_localization.dart`. Other languages fall back to English.
- Tests: `flutter test --exclude-tags live`. Hive tests use a temp dir with
  `Hive.init` (see `test/hive_safe_open_test.dart`). Podcast tests live in
  `test/podcasts/`.

---

## Placement rules (all phases)

- Every new feature, screen, setting and list lives inside the Podcasts
  section.
- **Podcast settings** is a new page (`PodcastSettingsScreen`) opened from
  the **gear in the Podcasts tab header**. All global podcast options go
  there.
- Per-show options go on the **show page** (`PodcastShowView`, the tune icon
  top right).
- In the shared player, new controls show only when the current item is a
  podcast episode (`PlayerController.isCurrentSongPodcast`).
- Speed profile, trim silence, voice boost, smart resume and segment
  skipping apply only while a podcast episode plays and reset when music
  plays.
- Android-only APIs are guarded with `GetPlatform.isAndroid`.
- New dependencies are proposed first, with a justification. Phase 1 adds
  none.

---

## Phase 1: Per-show playback profiles and playback polish ✅ (1.7.122)

### Spec
- Global podcast playback defaults live in Podcast settings. Per-show
  overrides live on the show page: a "Playback settings" sheet with a "Use
  global defaults" reset. The settings are:
  - **Speed** from 0.5 to 3.0 in 0.1 steps, with quick chips for 1.0, 1.1,
    1.25, 1.5 and 2.0.
  - **Skip back / forward** of 5, 10, 15, 30, 45 or 60 s. This applies to
    the in-app podcast player buttons, and to the notification controls
    during podcast playback.
  - **Trim silence** using just_audio `setSkipSilenceEnabled`. Android only.
  - **Voice boost** Off, Low or High.
  - **Segment skipping** on or off for this show.
- The show's profile is applied whenever one of its episodes starts,
  including queue auto-advance. Switching to music restores music's normal
  settings.
- **Smart resume** is for podcasts only, with a toggle in Podcast settings
  that defaults to on. When playback starts after a pause, it rewinds by an
  amount based on the pause length:
  - under 5 s: no rewind
  - 5 s to 1 min: 3 s
  - 1 to 10 min: 5 s
  - over 10 min: 10 s

  It never rewinds below 0.
- Podcast sleep timer:
  - Options: 5, 10, 15, 30, 45 or 60 min, end of episode, end of chapter.
  - The volume fades out over 10 s before pausing.
  - The app-wide sleep timer is reused, and only the episode, chapter and
    fade behaviour is podcast-specific.

### What was built and where

| Item | Files / classes | Entry point |
|---|---|---|
| Profile model, persistence, migration | **new** `lib/services/podcast_playback_profile.dart`: `PodcastPlaybackProfile`, `PodcastVoiceBoost`, `seedPodcastDefaults`, `PodcastPlaybackPrefs`, `podcastShowKey*`, `withPodcastShowId`, `smartResumeRewind`, `sleepFadeFactor`; new Hive box `PodcastShowPrefs` (`lib/main.dart` `initHiveDeferred`) | n/a |
| Podcast settings page | **new** `lib/ui/screens/Podcasts/podcast_settings_screen.dart`; route `ScreenNavigationSetup.podcastSettingsScreen` (`lib/ui/navigator.dart`) | Podcasts tab header › gear icon (`podcasts_library.dart` `_header`) |
| Per-show Playback settings sheet | **new** `podcast_playback_controls.dart`: `showPodcastShowPlaybackSheet` and `PodcastPlaybackEditor`; `PodcastShowView.playbackKey`, passed from `PodcastEpisodesScreen` (RSS: feed URL) and `_PodcastShow` (YouTube: `yt:<playlist id>`) | Show page › tune icon top right. It is tinted in the accent colour when the show has its own settings |
| Apply profile on episode start / auto-advance; restore music settings | `MyAudioHandler._applyPlaybackProfile`, called from `playByIndex` and `setSourceNPlay` | automatic |
| Speed control in the podcast player | `PodcastSpeedButton` and `showPodcastSpeedSheet` (`podcast_playback_controls.dart`), used by `long_form_player.dart` `_ToolRow` and `player_control.dart` `_podcastControls`; music and audiobooks keep `PlayerSpeedButton` | Podcast player › speed pill. Changes save to the show if it has its own settings, else to the podcast defaults |
| Skip buttons with the show's lengths | `LongFormSkipButton` and `SkipSecondsIcon` (`podcast_playback_controls.dart`); audiobooks keep −10 / +30 | Podcast player transport row |
| Notification skip back / forward | `MyAudioHandler` controls (`rewind` and `fastForward` for podcast items only) and `fastForward()` / `rewind()` overrides | Media notification during podcast playback |
| Trim silence / voice boost | `_applyPlaybackProfile`. Voice boost raises the existing native `LoudnessEnhancer` (`_effectiveLoudnessMb`): Low +5 dB, High +10 dB, never below the user's own volume boost | Podcast settings / show sheet. Android only |
| Segment skipping per show | `PlayerController._segmentSkipOn` gates `_maybeSkipAdChapter` and, for podcast items, `_maybeSkipSponsorBlock`. The global default **is** the existing `podcastAutoSkipAds` key (same switch as global Settings › Podcasts until Phase 2 moves it) | Podcast settings / show sheet |
| Smart resume | `MyAudioHandler._listenForPodcastPauses` (`playingStream`) and `_maybeSmartResume` in `play()` | Podcast settings › Resuming |
| Sleep timer: end of chapter, 10 s fade | `PlayerController.sleepEndOfChapter`, `_maybeStartSleepFade`, `_startSleepFade`; handler custom actions `sleepFadePause` / `cancelSleepFade`; sheet tile in `sleep_timer_bottom_sheet.dart` (podcast with chapters only) | Podcast player › sleep timer |
| Video mode speed for YouTube podcasts | `VideoModeController` uses the show's speed for podcast items | automatic |

**Migration:** when no podcast defaults are stored, the first read seeds them
from what podcasts played with before:
- speed from the app-wide `playbackSpeed`
- trim silence from `skipSilenceEnabled`
- −10 / +30 s skip lengths
- segment skipping from `podcastAutoSkipAds`

Nothing changes until the user edits a setting. Corrupt or out-of-range
stored values fall back or are clamped (`PodcastPlaybackProfile.fromMap`).

**Deviation from the spec:** voice boost does not add an `AudioPipeline`.
The player already has a native `LoudnessEnhancer` bound to its session (the
volume-boost setting), and a second enhancer on the same session would stack
with it. Voice boost raises that one instead. `AndroidEqualizer` was not
added. The system equalizer already binds to the session, and fighting it
needs care. Revisit if Low/High isn't enough.

**Tests:** `test/podcasts/podcast_playback_profile_test.dart` (snapping,
tolerant parsing, migration seed, show keys, YouTube tagging, smart-resume
steps, fade curve, Hive-backed prefs) and
`test/podcasts/podcast_settings_localization_test.dart`.

---

## Phase 2: Segment skipping v2 ✅ (1.7.123)

### Spec
- Unified model: `Segment {id, start, end, category, action, source:
  chapters | sponsorblock | manual}`. Refactor the v1.7.25 chapter ad skip
  to produce Segments.
- Move the v1.7.25 ad-skip toggle into Podcast settings › "Segment skipping"
  and migrate its stored value.
- SponsorBlock for YouTube-sourced episodes:
  - Use the hash-prefix lookup `GET
    https://sponsor.ajay.app/api/skipSegments/{first 4 hex of
    sha256(videoId)}?categories=[...]`, then filter the response to the
    episode's videoID. A 404 means no segments.
  - Cache per episode with a 24 h TTL. Never block playback on the request.
  - Check the current API docs (wiki.sponsor.ajay.app) before implementing.
- Categories: sponsor, selfpromo, interaction, intro, outro, preview, filler,
  music_offtopic.
  - Each category gets one action in Podcast settings › Segment skipping:
    Auto-skip, Show "Skip" pill, Mute or Ignore.
  - Defaults: sponsor is auto-skip; selfpromo and interaction show the pill;
    the rest are ignored.
- Playback logic:
  - Auto-skip only when playback enters a segment from before its start.
  - Seeking into a segment does not auto-skip it.
  - Never skip the same segment twice per session.
  - Merge overlapping segments.
- After an auto-skip, show a snackbar "Skipped sponsor · 0:42 · Undo". Undo
  seeks back to the segment start and disables that segment for the session.
- The podcast seek bar shows coloured markers per category, with a legend in
  Podcast settings.
- Manual segments for RSS episodes: player overflow › "Mark segment
  start/end". They are stored locally and treated like any other segment.
- Track the total time saved by skipped segments (used in Phase 5 stats).

### What was built and where

**SponsorBlock API, checked against its server source** (the wiki is blocked
from the build sandbox, so this was read from `ajayyy/SponsorBlockServer`):
- Route: `GET /api/skipSegments/:prefix` (`getSkipSegmentsByHash.ts`). The
  prefix is 3–32 hex characters. `categories` and `actionTypes` are JSON
  arrays, defaulting to `["sponsor"]` and `["skip"]`.
- Answer: `[{videoID, segments: [{segment: [start, end], UUID, category,
  actionType, videoDuration, locked, votes, description}]}]`, with 404 when
  no video matches.

| Item | Files / classes | Entry point |
|---|---|---|
| Unified model | **new** `lib/services/podcast_segments.dart`: `PodcastSegment`, `SegmentCategory` (8 categories, marker colours), `SegmentAction`, `SegmentSource`; pure `resolveSegments`, `mergeSegments`, `segmentAt`, `enteredFromBefore`, `segmentsFromChapters`, `parseSponsorBlockHashResponse`, `sponsorBlockHashPrefix`, `segmentCacheFresh` | n/a |
| Chapter ad skip refactor | `segmentsFromChapters`. Ad chapters become `sponsor`; intro, outro, preview and self-promo chapters get their category. `PlayerController._maybeSkipAdChapter` is removed and `_handlePodcastSegments` replaces it | automatic |
| Toggle moved and migrated | The global Settings › Podcasts "Skip podcast ads" tile is removed. The per-category actions live in AppPrefs `podcastSegmentActions`. Before any are saved, the old `podcastAutoSkipAds` decides sponsor (on means auto-skip, off means Skip button, which is what the switch did). The Phase 1 profile switch is now "Skip segments automatically" (off means everything is only pointed out), per show and global | Podcast settings › Segment skipping |
| SponsorBlock for YouTube episodes | `SponsorBlockService.podcastSegments(videoId)`: hash-prefix lookup for all 8 categories with skip and mute actions, filtered to the video. It is cached in box `PodcastSegmentCache` with a 24 h TTL (404 is cached as empty, other errors retry next play) and loaded after playback starts. The music SponsorBlock path is unchanged and no longer runs for podcast items | automatic |
| Per-category actions | `PodcastSegmentStore.actions` / `setAction`; `PodcastSegmentSettings` (`podcast_segment_ui.dart`) | Podcast settings › Segment skipping |
| Playback logic | `PlayerController._handlePodcastSegments`. It auto-skips only on `enteredFromBefore` (a tick advance of 3 s or less), never twice per session (`_segmentsSkipped`), and never after Undo (`_segmentsDisabled`). Overlaps are merged with the stronger action winning. Mute uses handler custom action `setSegmentMute` | automatic |
| Undo snackbar | `_showSegmentSkippedSnack` ("Skipped Sponsor · 0:42", Undo) and `undoSegmentSkip` | after each auto-skip |
| Skip button | `podcastSkipPillLabel` gives "Skip Sponsor", "Skip Intro" and so on in `long_form_player.dart` and `player_control.dart`; `skipAd()` skips the active segment | podcast player, above the seek bar |
| Seek-bar markers | `_SectionTrackPainter.spans` (`player_control.dart`), filled from `PlayerController.podcastSegments` (podcasts only) | podcast seek bar |
| Legend | colour dot per category in `PodcastSegmentSettings` | Podcast settings › Segment skipping |
| Manual segments (RSS) | `markSegmentStart` / `markSegmentEnd(category)`, stored in box `PodcastManualSegments`; `showPodcastSegmentsSheet` lists the episode's segments (tap to seek) and removes your own | podcast player top bar › ⋮ (music keeps the empty slot) |
| Time saved | `PodcastSegmentStore.addTimeSaved` (box `PodcastStats`, key `segmentSavedMs`). Undo takes the time back | shown in Podcast settings; Phase 5 stats |

**Tests:** `test/podcasts/podcast_segments_test.dart` covers defaults and
migration, resolve and merge, the entry rule, chapter mapping, the hash
prefix (pinned against Python's `hashlib`), response filtering, cache TTL,
JSON round trip and the Hive store. The localization test covers the new
screens.

---

## Phase 3: Transcripts

### Spec
- Sources, in priority order:
  1. Podcasting 2.0 `<podcast:transcript>`: VTT, SRT (`application/x-subrip`
     and `application/srt`), Podcasting 2.0 JSON, and HTML or plain text as
     an untimed fallback.
  2. YouTube captions for YouTube-sourced episodes, via the existing YouTube
     client.
  3. With no source, the transcript entry point is hidden.
- Parse into `TranscriptCue {start, end, text, speaker?}`, merge tiny cues
  into sentence-length lines, and cache the parsed result.
- Transcript view in the player, for podcasts only:
  - Highlight the active line and auto-scroll to it.
  - Scrolling by hand pauses auto-scroll and shows a "Resync" pill.
  - Tap a line to seek there.
  - Long-press a line to bookmark it (episodeId, timestamp, quote,
    createdAt, note), with haptic feedback and a confirmation.
  - Search inside the transcript, with a match count and next/previous.
  - A spoiler mode blurs the lines after the current position.
  - Phase 2 segments show as shaded spans.
- Bookmarks:
  - A per-episode list in the player.
  - A global "Bookmarks" entry in the Podcasts tab.
  - Tapping a bookmark plays from its timestamp.
  - Share as text: "“quote” — Show, Episode @ mm:ss".

### Plan
- **Parsing:** much of this exists. Extend `PodcastService.transcript()` and
  `parseTranscriptDocument`:
  - map `application/srt` to SRT
  - add a sentence-merge pass on top of `_coalesceCues`
  - persist the parsed result in a Hive box `PodcastTranscriptCache`
- **YouTube captions:** `youtube_explode_dart`'s `closedCaptions` client,
  already a dependency, behind a `transcriptFor(MediaItem)` facade.
- **Transcript view:** rework `podcast_transcript_sheet.dart`:
  - Resync pill, search bar, spoiler blur (`ImageFiltered` per line) and
    segment spans.
  - Long-press bookmarking with `HapticFeedback.mediumImpact`.
- **Bookmarks:**
  - A new `PodcastBookmarkService` (Hive box `PodcastBookmarks`) with pure
    helpers for the share text and sorting.
  - Screens: a per-episode sheet from the player tool row, and a global
    `PodcastBookmarksScreen` reached from a new Podcasts tab pill, after
    Downloads.
- **Entry points:**
  - Podcast player tool row › Transcript, and › Bookmarks.
  - Podcasts tab › Bookmarks.

---

## Phase 4: Queue and library hygiene

Podcast library and subscription views only.

### Spec
- Per-show "Keep latest N" (1, 3, 5, 10 or All) on the show page, with a
  default in Podcast settings. Older unplayed episodes leave Up Next and New
  when a new one arrives. They are archived, not deleted from history.
- "Mark all as listened" on the show page, with Undo.
- Auto-delete downloads after finishing: Never, Immediately or After 24 h.
  The default is in Podcast settings with a per-show override. Bookmarks
  are kept.
- Filter chips in the podcast library: New, In progress, Queued, Downloaded,
  Bookmarked and Short (under 20 min).
- User folders for podcast subscriptions: create, rename, delete, reorder,
  and add or remove shows.
- OPML import and export in Podcast settings. This is missing today.
- Up Next:
  - Drag to reorder, swipe to remove, and "Play next" vs "Play last".
  - The playback queue is shared with music, so these only touch podcast
    items.

### Plan
- **Keep latest N:**
  - Stored in the Phase 1 per-show box `PodcastShowPrefs`, which gains a
    `keepLatest` field.
  - Pure `applyKeepLatest(episodes, n, played)` gets unit tests.
  - Archive in box `PodcastArchived` and apply it in the Inbox merge
    (`podcast_inbox_screen.dart`) and `PodcastQueueController`.
- **Mark all as listened:** a show page overflow action that calls
  `PodcastProgressService.markPlayed` for all episodes, with a snapshot for
  Undo.
- **Auto-delete:** a hook in `PodcastProgressService.save` when an episode
  turns played, plus a sweep on start for the 24 h option.
  `PodcastDownloadService.delete` already keeps the other data.
- **Filter chips:** Inbox and Subscriptions in `podcasts_library.dart`, with
  pure filter predicates.
- **Folders:**
  - Extend `PodcastFolder.podcastIds` to RSS feed URLs (prefix `rss:`) with
    a migration that keeps the old ids.
  - Add a reorder (`ReorderableListView`) in `podcast_subs_screen.dart`.
- **OPML:** `lib/services/opml.dart`. A pure `parseOpml` / `buildOpml` with
  tests, using the `xml` package already in pubspec, `file_picker` and
  `share_plus`. Lives in Podcast settings › Import / Export.
- **Up Next:** already reorderable (`PodcastQueueScreen`). Add a
  `Dismissible` for swipe to remove, and "Play last" next to "Play next" in
  `showAddToQueueSheet`. Shared-queue edits go through the handler's
  `addPlayNextItem` and append, filtered to podcast items.
- **Entry points:**
  - Show page ⋮: Keep latest, Mark all as listened, Auto-delete.
  - Podcast settings: defaults, OPML.
  - Podcasts tab: chips, folders.

---

## Phase 5: Smart touches (Podcasts tab)

### Spec
- **"Expected today"**, built as a pure function with unit tests:
  - Use each followed show's last 10 or fewer pubDates, in local time.
  - Predict a release today only with at least 4 data points and either
    ≥60% on today's weekday or a daily cadence.
  - The predicted time is the median release hour.
  - Show an "Expected today" row with the approximate time. The item moves
    to New when the episode arrives.
- An artwork-tinted podcast player, reusing the existing artwork theming.
- A cache-first Podcasts tab: render the cached state instantly, refresh in
  the background, and never show a full-screen spinner.
- A listening stats page counting podcasts only:
  - total time listened
  - time saved (speed and skipped segments)
  - top shows
  - listening streak
  - optional share as an image

### Plan
- **Expected today:** `lib/services/podcast_release_predictor.dart` with a
  pure `predictToday(List<DateTime> pubDates, DateTime now)` and tests. The
  row goes at the top of the Inbox (`podcast_inbox_screen.dart`) and reads
  `pubDateMs` from cached feed results.
- **Tinted player:** `LongFormPlayer` reads `ThemeController.setTheme`
  output (`primaryColor`) for its background gradient, for podcasts only.
- **Cache-first:** the Inbox already has a 15 min cache (`freshInbox`). Make
  it show stale data instantly with a thin top progress bar while
  refreshing. The same applies to Subscriptions.
- **Stats:** a `PodcastStatsService` (Hive box `PodcastStats`) fed by
  `PlayerController._handlePodcastProgress`, including time saved from
  speed and from Phase 2 skips. It gets a `PodcastStatsScreen` reached from
  the Podcasts tab header (chart icon), with share via `RepaintBoundary`
  and `share_plus`.
- **Entry points:**
  - Podcasts tab › Inbox top row (Expected today).
  - Header › stats icon.

---

## Later (not planned for implementation)
- Android Auto browse tree for podcasts
- Podcast home-screen widget
- Import podcast subscriptions from a screenshot (OCR + iTunes Search match)
- AI-generated chapters and summaries
