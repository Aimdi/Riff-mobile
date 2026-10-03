# Podcast roadmap

Scope: the **Podcasts section only**. Nothing here goes into the global
Settings screen, the music Library, the main Home feed or music-only screens,
and music playback behaves exactly as before. Ideas are inspired by other
podcast apps; the UI, names, icons and wording are Riff's own.

Status: **Phase 1 shipped in 1.7.122, Phase 2 in 1.7.123, Phase 3 in
1.7.124, Phase 4 in 1.7.125, Phase 5 implemented (1.7.126).** All planned
phases are done; each starts after the previous one is reviewed.

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

## Phase 3: Transcripts ✅ (1.7.124)

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

### What was built and where

| Item | Files / classes | Entry point |
|---|---|---|
| Sources and priority | **new** `lib/services/podcast_transcripts.dart`: `transcriptSourceFor(MediaItem)` returns the feed `<podcast:transcript>` first, then YouTube captions for episodes whose id is a video id, else null | n/a |
| Formats | `PodcastService.parseTranscriptDocument` already read VTT, SRT (any type containing `srt`/`subrip`, so `application/srt` too), Podcasting 2.0 JSON and HTML/plain text (untimed). Tiny cues were already merged into sentence-length lines (`_coalesceCues`) | n/a |
| Cue model | `PodcastTranscriptCue {startSec, endSec?, speaker?, text}`, now with `toJson`/`fromJson` and `timed` | n/a |
| YouTube captions | `youtube_explode_dart`'s `closedCaptions` (already a dependency), VTT format. `pickCaptionTrack`: a human track in the app language, then an automatic one, then any human track. Automatic captions repeat the previous line in every cue; `PodcastService.dedupeRollingCaptions` keeps only the new words (`rolling: true`) | n/a |
| Cache | box `PodcastTranscripts`, keyed by feed URL or `yt:<videoId>`. Only non-empty results are stored, so an offline failure retries next time. It keeps the 40 most recent | n/a |
| Hide when none | `PodcastTranscriptService.available(item)`: synchronous for feed transcripts. For YouTube episodes, `probe()` checks for caption tracks when the episode starts (`PlayerController`, podcast items only) and the button appears when there are some | podcast player tool row › Transcript |
| Transcript view | `podcast_transcript_sheet.dart`, rewritten: active line plus auto-scroll; a hand scroll shows the **Resync** pill; tap seeks; long-press bookmarks (`HapticFeedback.mediumImpact` and a "Bookmarked at 12:34" snackbar with **Add note**, inside the sheet's own `ScaffoldMessenger`); search (`transcriptMatches`, `matchRanges`, `stepMatch`, `firstMatchFrom`) with "3 of 12" and up/down; spoiler blur (`ImageFiltered`, remembered in AppPrefs `podcastTranscriptSpoiler`); Phase 2 segments as shaded spans with a coloured edge and a category label. Lines you've bookmarked get a small mark | podcast player tool row › Transcript |
| Bookmarks | **new** `lib/services/podcast_bookmarks.dart`: `PodcastBookmark {id, episodeId, positionMs, createdAt, quote, note?, episodeTitle, showTitle, episode}` in box `PodcastBookmarks`. `episodeSnapshot` keeps a playable copy of the episode (remote URL instead of a downloaded file path). `formatBookmarkShare` gives "“quote” — Show, Episode @ 12:34" | n/a |
| Per-episode list | `showEpisodeBookmarksSheet` (`podcast_bookmarks_ui.dart`): "Bookmark this moment", then the list in playback order (tap seeks; ⋮ Share, Add/Edit note, Remove with Undo) | podcast player › ⋮ › Bookmarks in this episode; the bookmarks icon in the transcript header |
| Bookmark without a transcript | `bookmarkCurrentMoment` | podcast player › ⋮ › Bookmark this moment |
| Global list | `PodcastBookmarksScreen(embedded: true)`, newest first. Tap plays the episode from that moment (`PlayerController.playPodcastAt`, which starts there instead of the saved position) | Podcasts tab › **Bookmarks** pill (after Downloads) |

**Tests:** `test/podcasts/podcast_transcripts_test.dart` covers `application/srt`,
sentence merge, rolling-caption dedupe, cue JSON, source priority, caption track
choice, search helpers, cache rules and loading from the box.
`test/podcasts/podcast_bookmarks_test.dart` covers share text, the episode
snapshot, tolerant JSON, sorting and the Hive store. The live suite
(`yt_e2e_diagnose_test.dart`) checks that a real YouTube video's captions turn
into a timed transcript, because YouTube is blocked from the build sandbox.

---

## Phase 4: Queue and library hygiene ✅ (1.7.125)

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

### What was built and where

| Item | Files / classes | Entry point |
|---|---|---|
| Keep latest N | **new** `lib/services/podcast_library.dart`: pure `episodesToArchive` (newest N unplayed stay; played ones don't count; started ones are never archived). `PodcastLibrary.applyKeepLatest` groups the merged Inbox by show key, archives into box `PodcastArchived` (`{at, show}`) and takes archived episodes out of the Queue. Per-show values live in the new box `PodcastShowLibrary` (not `PodcastShowPrefs`, which holds playback profiles); the default is AppPrefs `podcastKeepLatest` (0 = all). Changing a limit clears that show's archive so the new one applies cleanly. Archived episodes stay on the show page | show page ⋮ › Episodes and downloads; Podcast settings › Episodes and downloads |
| Mark all as listened | `PodcastLibrary.markAllListened` returns a `ListenedSnapshot` (ids, saved positions, Queue entries with their index); `undoMarkAll` restores all three. `markShowListened` shows the snackbar with Undo | show page ⋮ › Mark all as listened |
| Auto-delete downloads | `AutoDeletePolicy {never, immediately, after24h}`, pure `downloadDueForDeletion` (never the episode playing). `PodcastLibrary.sweepDownloads` runs when a new item starts playing, when the Podcasts tab opens, after Mark as played and after changing the setting. It uses the `PodcastPlayed` timestamp. Default AppPrefs `podcastAutoDelete`; per show in `PodcastShowLibrary`. Bookmarks keep a remote copy of the episode, so they're unaffected | same two places as Keep latest |
| Filter chips | `EpisodeFilter` + pure `matchesEpisodeFilter` / `EpisodeFacts`. With a chip on, the Inbox lists every episode Riff knows (Inbox, in progress, Queue, downloads, bookmarks; `uniqueEpisodes`) that matches. Small outlined chips under the section tabs; tap again to clear | Podcasts tab › Inbox |
| Folders | Feed shows can be filed (`rss:<feedUrl>` ids via `podcastFolderIdForFeed`; YouTube playlistIds unchanged, so no migration is needed). Long-press a feed show for its folder sheet (with Unsubscribe, which also removes it from folders). Folder screen lists feed shows. Drag to reorder: `PodcastFolderController.move` / pure `reorderList`, in a sheet | Podcasts tab › Subscriptions (⇅ icon when there are 2+ folders) |
| OPML | **new** `lib/services/opml.dart`: `parseOpml` (nested outlines, any-case `xmlUrl`, http(s) only, duplicates dropped) and `buildOpml` (OPML 2.0, RFC 822 date). Import uses `file_picker` and skips shows already followed; export shares `riff-podcasts.opml` with `share_plus`. YouTube-followed shows have no feed and aren't exported | Podcast settings › Import and export |
| Queue | Swipe to remove (`Dismissible`) with Undo (`PodcastQueueController.insertAt`). Episode sheet: **Play last** (`enqueueSong`) next to Play next; it only adds the chosen episode | Podcasts tab › Queue; episode long-press |

**Tests:** `test/podcasts/podcast_library_test.dart` covers keep-latest
selection and ordering, auto-delete rules, every filter, the mark-all plan,
OPML parse/build round trip, folder ids and reordering, and the Hive store
(defaults, overrides, archive per show and clearing, mark all plus undo).

---

## Phase 5: Smart touches (Podcasts tab) ✅ (1.7.126)

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

### What was built and where

| Item | Files / classes | Entry point |
|---|---|---|
| Expected today | **new** `lib/services/podcast_release_predictor.dart`: pure `predictToday(pubDates, now)` (newest 10 in local time, at least 4, ≥60% on today's weekday or a daily cadence of mostly 18–30 h gaps; no guess if today's is already out, if the show has gone quiet (15 days, or 3 for daily) or for a weekdays-only show at the weekend; time = median time of day, rounded to 15 min). `expectedShows(merged, now)` groups the cached Inbox by show. Episodes without `pubDateMs` (most YouTube shelves) can't count | Podcasts tab › Inbox, top row |
| Tinted player | **new** `lib/ui/player/components/podcast_player_tint.dart`: `PodcastPlayerTint` runs `PaletteGenerator` on the episode art (64×64) and `podcastPlayerTint` keeps it dark (HSL lightness 0.06–0.16, saturation ≤0.55). `LongFormPlayer` uses it for podcasts only. With the dynamic theme on, the theme already follows the art, so it stays out of the way. The app theme is never changed, so music screens are untouched. Switch: AppPrefs `podcastTintPlayer` (default on) | Podcast settings › Player |
| Cache-first Inbox | **new** `lib/services/podcast_inbox_cache.dart` (box `PodcastInboxCache`, keyed by the subscription set, ≤250 episodes, notes trimmed to 1500 chars). The Inbox opens on the memory or saved copy whatever its age and refreshes behind it with a 2 px progress bar. Pull-to-refresh and the header refresh no longer blank the list, and a refresh that fails everywhere (offline) keeps what's shown. The shimmer only appears on the very first load | Podcasts tab › Inbox |
| Listening stats | **new** `lib/services/podcast_stats.dart`: `PodcastStatsService.tick` is fed from `PlayerController._handlePodcastProgress` (podcast items only). Pure `listenDelta` ignores pauses, seeks and sleeps; wall time vs episode time gives "saved by speed". Totals, per-day and per-show values go in box `PodcastStats`, flushed every 30 s and on pause. Pure `listeningStreak` and `topShows`. **New** `PodcastStatsScreen`: time listened, saved by speed, saved by skipping (Phase 2 counter), streak, top 5 shows; share as PNG via `RepaintBoundary` + `share_plus` | Podcasts tab header › chart icon |

**Tests:** `test/podcasts/podcast_smart_test.dart` covers the predictor
(weekly, threshold, minimum points, already out, daily, weekdays-only,
quiet shows, history window), grouping by show, the stats tick rules,
streaks, top shows, the stats store, the Inbox cache round trip and the
tint range.

---

## Later (not planned for implementation)
- Android Auto browse tree for podcasts
- Podcast home-screen widget
- Import podcast subscriptions from a screenshot (OCR + iTunes Search match)
- AI-generated chapters and summaries
