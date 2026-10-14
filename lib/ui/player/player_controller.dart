import 'dart:async';
import 'package:flutter_lyric/lyric_ui/ui_netease.dart';
import 'package:hive/hive.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';

import '../../models/playling_from.dart';
import '../../models/media_item_extras.dart';
import '../../utils/hive_boxes.dart';
import 'abs_session.dart';
import 'long_form_queue.dart';
import '/services/id3_chapters.dart';
import '/services/show_notes_chapters.dart';
import 'play_queue_order.dart';
import 'video_handoff.dart';
import '../../services/play_by_index_skip.dart';
import '../../services/play_runtime_error.dart';
import '../../services/downloader.dart';
import '../../services/discovery/discovery_service.dart';
import '../../services/discovery/discovery_tag.dart';
import '../../services/discovery/discovery_types.dart';
import '../../services/smart_queue_service.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '../widgets/snackbar.dart';
import '../widgets/sleep_timer_bottom_sheet.dart' show formatSleepMinutes;
import '/services/listenbrainz_service.dart';
import '/services/audiobook_progress_service.dart';
import '/services/scrobble_rules.dart';
import '/services/stats_service.dart';
import '/services/collection_recents.dart';
import '/services/private_session.dart';
import '/services/taste_exclusions.dart';
import '/services/synced_lyrics_service.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../services/windows_audio_service.dart';
import '../../utils/helper.dart';
import '../../utils/media_item_video.dart';
import '/models/media_Item_builder.dart';
import '../screens/Home/home_screen_controller.dart';
import '../widgets/sliding_up_panel.dart';
import '/models/durationstate.dart';
import '/services/music_service.dart';
import '/services/music_autoplay.dart';
import '/services/explicit_content.dart';
import '/services/offline_playback.dart';
import '/services/recently_played_days.dart';
import '/services/riff_equalizer.dart';
import '/services/sponsorblock_service.dart';
import '/services/podcast_service.dart';
import '/services/podcast_progress_service.dart';
import '/services/podcast_history.dart';
import '/services/sleep_shake.dart';
import '/services/auto_sleep_timer.dart';
import '/services/long_track_resume.dart';
import '/services/chapter_now_playing.dart';
import '/services/podcast_bookmarks.dart';
import '/services/podcast_starred.dart';
import '/ui/screens/Podcasts/podcast_bookmarks_ui.dart'
    show showBookmarkSavedSnack;
import '/services/audiobookshelf_service.dart';
import '/ui/player/riff_wave.dart';
import '/ui/player/play_log_gate.dart';
import '/ui/player/progress_ui_throttle.dart';
import '/ui/player/radio_continuation.dart';
import 'upcoming_queue.dart';
import 'video_mode_controller.dart';
import '/services/playlist_mix_service.dart';
import '/services/audiobook_playback.dart';
import '/services/podcast_playback_profile.dart';
import '/services/podcast_library.dart';
import '/services/audio_handler.dart' show MyAudioHandler, MediaLibrary;
import '/services/spotify_like_sync.dart';
import '/services/yt_like_sync.dart';
import '/services/playback_hardening.dart';
import '/services/podcast_segments.dart';
import '/services/podcast_stats.dart';
import '/services/podcast_transcripts.dart';

class PlayerController extends GetxController
    with GetSingleTickerProviderStateMixin {
  /// Resolved lazily so [runApp] can paint before AudioService finishes init.
  AudioHandler? _audioHandlerOrNull;
  AudioHandler get _audioHandler {
    _audioHandlerOrNull ??= Get.find<AudioHandler>();
    return _audioHandlerOrNull!;
  }

  /// The real handler (tests use fakes): transport goes through its
  /// source-tagged entry points.
  MyAudioHandler? get _tagged {
    final h = _audioHandler;
    return h is MyAudioHandler ? h : null;
  }

  bool get _audioReady =>
      _audioHandlerOrNull != null || Get.isRegistered<AudioHandler>();

  Future<void> _waitForAudioHandler() async {
    if (_audioReady) {
      _audioHandlerOrNull ??= Get.find<AudioHandler>();
      return;
    }
    for (var i = 0; i < 100; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (Get.isRegistered<AudioHandler>()) {
        _audioHandlerOrNull = Get.find<AudioHandler>();
        return;
      }
    }
  }

  final _musicServices = Get.find<MusicServices>();
  final currentQueue = <MediaItem>[].obs;

  final playerPaneOpacity = (1.0).obs;
  final isPlayerpanelTopVisible = true.obs;

  /// True when the main player panel is nearly fully open. Muted in-player
  /// video pauses while this is false so decoding stops behind the mini player.
  final isPlayerPanelOpen = false.obs;

  /// The player panel's exact position every frame (0 collapsed, 1 open),
  /// for the cover's minimise / expand morph. A plain notifier so only the
  /// morph layer repaints while the panel moves.
  final playerPanelPosition = ValueNotifier<double>(0.0);
  final playerPanelMinHeight = 0.0.obs;
  bool initFlagForPlayer = true;
  PanelController playerPanelController = PanelController();
  PanelController queuePanelController = PanelController();
  AnimationController? gesturePlayerStateAnimationController;
  Animation<double>? gesturePlayerStateAnimation;
  bool isRadioModeOn = false;
  Future<void> _discoveryChain = Future.value();
  int _lastAudiobookSaveMs = 0;
  String? radioContinuationParam;
  dynamic radioInitiatorItem;
  bool _radioContinuationInFlight = false;

  /// Home "Continue listening" chip — saved queue exists and player is idle.
  final showContinueListening = false.obs;
  final continueListeningTitle = ''.obs;

  /// Saved-queue track behind the chip, so Home can show its cover art.
  final continueListeningItem = Rxn<MediaItem>();
  Timer? sleepTimer;
  int timerDuration = 0;
  final timerDurationLeft = 0.obs;
  final isSleepTimerActive = false.obs;
  final isSleepEndOfSongActive = false.obs;

  /// Podcast sleep timer set to the end of the current chapter.
  final isSleepEndOfChapterActive = false.obs;
  Duration? _sleepChapterEnd;

  /// A podcast sleep timer is fading out (the handler pauses at the end).
  bool _sleepFadeStarted = false;

  /// Podcast sleep timers fade the volume out over this before pausing.
  static const sleepFadeLength = Duration(seconds: 10);
  final volume = 100.obs;

  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero, current: Duration.zero, total: Duration.zero)
      .obs;

  final currentSongIndex = (0).obs;

  /// Songs after the currently playing index — Spotify-style "Up next".
  List<MediaItem> get upcomingQueue =>
      upcomingAfterIndex(currentQueue, currentSongIndex.value);

  final isQueueLoopModeEnabled = false.obs;
  final isLoopModeEnabled = false.obs;
  final isShuffleModeEnabled = false.obs;
  final currentSong = Rxn<MediaItem>();
  final isCurrentSongFav = false.obs;
  final playinfrom = PlaylingFrom(type: PlaylingFromType.SELECTION).obs;
  final showLyricsflag = false.obs;
  final isLyricsLoading = false.obs;
  final lyricsMode = 0.obs;
  bool isDesktopLyricsDialogOpen = false;
  // 0 for play, 1 for pause, 2 for blank
  final gesturePlayerVisibleState = 2.obs;
  final lyricUi =
      UINetease(highlight: true, defaultSize: 20, defaultExtSize: 12);
  RxMap<String, dynamic> lyrics =
      <String, dynamic>{"synced": "", "plainLyrics": ""}.obs;
  ScrollController scrollController = ScrollController();
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();

  final buttonState = PlayButtonState.paused.obs;

  /// Localized reason the current song failed to start/play (null when OK).
  final playbackError = RxnString();

  // track whether wakelock is currently enabled to avoid repeated calls
  bool _wakelockActive = false;

  var _newSongFlag = true;

  /// SponsorBlock segments for the current video id.
  List<SponsorBlockSegment> _sponsorSegments = const [];
  String? _sponsorVideoId;
  String? _lastSkippedSegmentUuid;
  bool _sponsorSeekInFlight = false;

  /// Podcasting 2.0 chapters for the current podcast episode (ad auto-skip).
  final chapters = <PodcastChapter>[].obs;
  String? _chaptersForSongId;

  /// The podcast episode playing as it was announced, before a chapter
  /// showed on it outside the app ([_showChapterOutside]).
  MediaItem? _chapterBase;

  // True while playback is inside an ad chapter (drives the "Skip ad" chip).
  final inAdChapter = false.obs;

  Box get _prefs => HiveBoxes.prefs();

  /// Playback profile of the current podcast episode's show.
  PodcastPlaybackProfile get currentPodcastProfile {
    final s = currentSong.value;
    return s == null
        ? PodcastPlaybackPrefs.globalDefaults
        : PodcastPlaybackPrefs.forItem(s);
  }

  /// Edits the current episode's profile where it lives (the show's
  /// overrides, else the podcast defaults) and applies it right away.
  Future<void> updateCurrentPodcastProfile(
      PodcastPlaybackProfile Function(PodcastPlaybackProfile) edit) async {
    final s = currentSong.value;
    if (s == null || !s.isPodcastEpisode) return;
    final key = podcastShowKey(s);
    await PodcastPlaybackPrefs.saveForShow(
        key, edit(PodcastPlaybackPrefs.forShow(key)));
    await refreshPlaybackProfile();
  }

  /// Re-applies podcast speed / trim silence / voice boost to what is
  /// playing (after a podcast settings change).
  Future<void> refreshPlaybackProfile() async {
    await _audioHandler.customAction('refreshPlaybackProfile');
    if (_videoModeActive && isCurrentSongPodcast) {
      Get.find<VideoModeController>()
          .setVideoSpeed(currentPodcastProfile.speed);
    }
  }

  bool get podcastAutoSkipAds =>
      _prefs.get('podcastAutoSkipAds', defaultValue: true);
  set podcastAutoSkipAds(bool v) => _prefs.put('podcastAutoSkipAds', v);

  // Podcast / audiobook resume: persist position periodically and auto-seek
  // to the saved position when a partially-played item starts.
  int _lastProgressSaveMs = 0;
  int _lastAbsSyncMs = 0;

  /// Wall-clock ms of the last ABS position tick (for timeListened delta).
  int _absLastTickMs = 0;

  /// Seconds listened since last ABS sync/close (accumulated while playing).
  double _absTimeListenedSec = 0;
  String? _pendingResumeId;
  int _pendingResumeMs = 0;

  /// The long track whose kept place is being resumed (said once it is).
  String? _longTrackResumeId;

  /// When the playing long track's place was last kept ([LongTrackResume]).
  int _lastLongTrackSaveMs = 0;

  /// Audio handler / keyboard subscriptions and workers, released in
  /// [onClose] (two workers watch app-wide observables and would otherwise
  /// keep a closed controller alive and running).
  final _subscriptions = <StreamSubscription>[];
  final _workers = <Worker>[];

  @override
  onInit() {
    _init();
    // Podcast segments follow chapters, settings and manual marks.
    _workers.addAll([
      ever(chapters, (_) => _rebuildPodcastSegments()),
      ever(PodcastSegmentStore.rev, (_) => _rebuildPodcastSegments()),
      ever(PodcastPlaybackPrefs.rev, (_) => _rebuildPodcastSegments()),
      // Full player open: fetch lyrics for the line under the title.
      ever(currentSong, (_) => _scheduleLyricsPrefetch()),
      ever(isPlayerPanelOpen, (_) => _scheduleLyricsPrefetch()),
      // Lyrics missing for want of a connection: looked up again once
      // it's back.
      ever(OfflinePlayback.offline, (bool offline) {
        if (!offline && lyrics['offline'] == true) _loadLyrics();
      }),
      // Shake to restart a timed sleep timer (Android).
      everAll([
        isSleepTimerActive,
        isSleepEndOfSongActive,
        isSleepEndOfChapterActive,
        SleepShake.enabled,
      ], (_) => _followShakes()),
      // Playback starting at night: the automatic sleep timer.
      ever(buttonState, (PlayButtonState state) {
        if (state == PlayButtonState.playing) autoSleep();
      }),
    ]);
    super.onInit();
  }

  void _followShakes() => SleepShake.follow(
      wanted: isSleepTimerActive.isTrue &&
          isSleepEndOfSongActive.isFalse &&
          isSleepEndOfChapterActive.isFalse,
      onShake: restartSleepTimer);

  Timer? _lyricsPrefetchTimer;

  /// Music in the standard player only, once the player has stayed open a
  /// moment (not on every skip while it's closed).
  void _scheduleLyricsPrefetch() {
    _lyricsPrefetchTimer?.cancel();
    if (!isPlayerPanelOpen.value) return;
    _lyricsPrefetchTimer = Timer(const Duration(milliseconds: 800), () {
      if (isClosed || !isPlayerPanelOpen.value || usesLongFormTransport) {
        return;
      }
      if (Get.isRegistered<SettingsScreenController>() &&
          Get.find<SettingsScreenController>().playerUi.value != 0) {
        return;
      }
      prefetchLyrics();
    });
  }

  @override
  void onReady() {
    if (GetPlatform.isWindows) {
      Get.put(WindowsAudioService());
    }
    () async {
      await _waitForAudioHandler();
      // Closed meanwhile: don't load the saved queue into the handler.
      if (isClosed) return;
      if (_audioReady) await _restorePrevSession();
      await _refreshContinueListeningChip();
    }();
    super.onReady();
  }

  void _init() async {
    // Prefs / UI can initialize before AudioService; wait so listeners attach.
    await _waitForAudioHandler();
    // Closed while waiting: listeners attached now would never be released.
    if (isClosed) return;
    if (!_audioReady) {
      printERROR('AudioHandler not ready; player listeners skipped');
      return;
    }
    _listenForChangesInPlayerState();
    _listenForChangesInPosition();
    _listenForChangesInBufferedPosition();
    _listenForChangesInDuration();
    _listenForPlaylistChange();
    _listenForKeyboardActivity();
    _setInitLyricsMode();
    if (Get.isRegistered<SmartQueueService>()) {
      Get.find<SmartQueueService>().attach(this);
    }
    final appPrefs = _prefs;
    isLoopModeEnabled.value = appPrefs.get("isLoopModeEnabled") ?? false;
    isShuffleModeEnabled.value = appPrefs.get("isShuffleModeEnabled") ?? false;
    isQueueLoopModeEnabled.value =
        appPrefs.get("queueLoopModeEnabled") ?? false;

    if (GetPlatform.isDesktop) {
      setVolume(appPrefs.get("volume") ?? 100);
    }

    if ((appPrefs.get("playerUi") ?? 0) == 1) {
      initGesturePlayerStateAnimationController();
    }

    // only for android auto
    if (GetPlatform.isAndroid) {
      _listenForCustomEvents();
    }
  }

  void initGesturePlayerStateAnimationController() {
    gesturePlayerStateAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    gesturePlayerStateAnimation = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(
            parent: gesturePlayerStateAnimationController!,
            curve: Curves.easeIn));
  }

  void _setInitLyricsMode() {
    lyricsMode.value = _prefs.get("lyricsMode") ?? 0;
  }

  void panellistener(double x) {
    // The notifier is disposed with the controller; a panel still bound to
    // a closed one must not write to it.
    if (isClosed) return;
    playerPanelPosition.value = x;
    // Only publish when values actually change — panel drag used to rewrite
    // opacity/visibility every frame and rebuild the mini player continuously.
    if (x >= 0 && x <= 0.2) {
      final opacity = 1 - (x * 5);
      if ((playerPaneOpacity.value - opacity).abs() > 0.03) {
        playerPaneOpacity.value = opacity;
      }
      if (!isPlayerpanelTopVisible.value) {
        isPlayerpanelTopVisible.value = true;
      }
    } else if (x > 0.2) {
      if (isPlayerpanelTopVisible.value) {
        isPlayerpanelTopVisible.value = false;
      }
    }

    // Hysteresis near fully-open so the last bit of the gesture doesn't thrash.
    final open = isPlayerPanelOpen.value ? x >= 0.85 : x >= 0.95;
    if (isPlayerPanelOpen.value != open) {
      isPlayerPanelOpen.value = open;
    }
  }

  void _listenForKeyboardActivity() {
    var keyboardVisibilityController = KeyboardVisibilityController();
    _subscriptions
        .add(keyboardVisibilityController.onChange.listen((bool visible) {
      visible ? playerPanelController.hide() : playerPanelController.show();
    }));
  }

  void _listenForChangesInPlayerState() {
    _subscriptions.add(_audioHandler.playbackState.listen((playerState) {
      // Video mode drives buttonState from the mpv engine's state.
      if (_videoModeActive) return;
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;
      if (processingState == AudioProcessingState.loading ||
          processingState == AudioProcessingState.buffering) {
        // Keep play/pause — YouTube videos rebuffer for seconds and the
        // old spinner made the button look stuck until the song started.
        if (isPlaying) {
          buttonState.value = PlayButtonState.playing;
        }
      } else if (!isPlaying || processingState == AudioProcessingState.error) {
        buttonState.value = PlayButtonState.paused;
      } else if (processingState != AudioProcessingState.completed) {
        buttonState.value = PlayButtonState.playing;
        if (playbackError.value != null) clearPlaybackError();
      } else {
        // Handler already advances via _triggerNext. Do not seek+pause
        // the next source or the play icon will lie.
        buttonState.value = PlayButtonState.paused;
      }

      final settings = Get.find<SettingsScreenController>();
      // Keep the screen awake whenever playback is active and the setting is enabled.
      final shouldEnable = settings.keepScreenAwake.isTrue && isPlaying;
      _setWakelock(shouldEnable);
    }));
  }

  void _setWakelock(bool enable) {
    if (_wakelockActive == enable) return; // no-op if already in desired state

    try {
      if (enable) {
        printINFO("Enabling wakelock");
        WakelockPlus.enable();
        _wakelockActive = true;
      } else {
        printINFO("Disabling wakelock");
        WakelockPlus.disable();
        _wakelockActive = false;
      }
    } catch (e) {
      printERROR(e);
    }
  }

  final _progressUiThrottle = ProgressUiThrottle();
  final _playLogGate = PlayLogGate();

  /// Whether the song playing started in a private session, or from a
  /// playlist left out of your taste profile (not scrobbled).
  bool _playIsPrivate = false;

  void _listenForChangesInPosition() {
    _subscriptions.add(AudioService.position.listen((position) {
      // While video mode's engine owns playback it feeds [onPlaybackPosition]
      // itself; the (paused) audio pipeline's stale ticks must not fight it.
      if (_videoModeActive) return;
      onPlaybackPosition(position);
    }));
  }

  /// One position tick from whichever engine is playing (audio pipeline or
  /// video mode): sleep-at-end, SponsorBlock, ad chapters, podcast and
  /// audiobook progress, taste signals, then the throttled progress UI.
  void onPlaybackPosition(Duration position) {
    final oldState = progressBarStatus.value;
    if (isSleepEndOfSongActive.isTrue) {
      final end = _playingItemEnd(oldState.total);
      timerDurationLeft.value = end.inSeconds - position.inSeconds;
      if (_maybeStartSleepFade(end - position)) {
        // The fade pauses when it is done.
      } else if (timerDurationLeft.value <= 1) {
        pause(source: PlaybackCommandSource.sleepTimer);
        cancelSleepTimer();
      }
    } else if (isSleepEndOfChapterActive.isTrue) {
      // The chapter's end, but never past where the episode ends (its
      // skipped outro) once its length is known.
      final episodeEnd = _playingItemEnd(oldState.total);
      var end = _sleepChapterEnd ?? episodeEnd;
      if (episodeEnd > Duration.zero && end > episodeEnd) end = episodeEnd;
      final remaining = end - position;
      timerDurationLeft.value = remaining.inSeconds.clamp(0, 1 << 30);
      if (_maybeStartSleepFade(remaining)) {
        // The fade pauses when it is done.
      } else if (remaining <= const Duration(seconds: 1)) {
        pause(source: PlaybackCommandSource.sleepTimer);
        cancelSleepTimer();
      }
    }
    // Full-rate side effects — never throttle skip / podcast / taste logic.
    if (Get.isRegistered<DiscoveryService>()) {
      Get.find<DiscoveryService>().onPositionTick(position.inMilliseconds);
    }
    _maybeSkipSponsorBlock(position);
    _handlePodcastSegments(position);
    _handlePodcastProgress(position);
    _showChapterOutside(position);
    _handleAbsProgress(position);
    _handleSongStart(position);
    _handleLongTrackProgress(position);

    // Progress widgets (mini player, lyrics, seek bar) only need ~10 Hz.
    if (!_progressUiThrottle.shouldUpdate(
      position: position,
      previousUiPosition: oldState.current,
    )) {
      return;
    }
    progressBarStatus.update((val) {
      val!.current = position;
      val.buffered = oldState.buffered;
      val.total = oldState.total;
    });
  }

  /// Where the playing item ends: its length, or where the outro its show
  /// skips begins (the handler ends the episode there).
  Duration _playingItemEnd(Duration total) {
    final song = currentSong.value;
    if (song == null || !song.isPodcastEpisode) return total;
    final cut = podcastOutroCutMs(
        totalMs: total.inMilliseconds,
        trim: PodcastPlaybackPrefs.trimForItem(song));
    return cut == null ? total : Duration(milliseconds: cut);
  }

  void _handlePodcastProgress(Duration position) {
    final song = currentSong.value;
    if (song == null || !PodcastProgressService.isPodcastItem(song)) return;
    final total = progressBarStatus.value.total;
    // Podcast listening stats (podcasts only; music never reaches here).
    PodcastStatsService.tick(song, position,
        playing: buttonState.value == PlayButtonState.playing);

    // Auto-resume once: a partially-played episode that just started near 0.
    _maybeApplyPendingResume(song, position, total);

    // Persist position at most every 5s.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastProgressSaveMs >= 5000) {
      _lastProgressSaveMs = nowMs;
      PodcastProgressService.save(song, position, total, nowMs: nowMs);
    }
  }

  /// The lock screen, notification, Android Auto and the home screen
  /// widget show the podcast chapter playing ([chapterNowPlaying]); again
  /// when the handler announces the episode afresh (a queue edit, its
  /// length found). Its art only online: it is fetched. Not over a
  /// playback error (announcing the episode would clear it).
  void _showChapterOutside(Duration position) {
    final episode = currentSong.value;
    if (episode == null ||
        !episode.isPodcastEpisode ||
        playbackError.value != null ||
        !_audioReady) {
      return;
    }
    final shown = _audioHandler.mediaItem.value;
    if (shown == null || shown.id != episode.id) return;
    if (_chapterBase?.id != episode.id) _chapterBase = episode;
    final want = chapterNowPlaying(
        _chapterBase!, chapters, position.inMilliseconds / 1000.0,
        art: !OfflinePlayback.offline.value);
    if (want.artist == shown.artist && want.artUri == shown.artUri) return;
    unawaited(_audioHandler.customAction('showChapter', {
      'id': episode.id,
      'artist': want.artist,
      'artUri': want.artUri?.toString(),
    }));
  }

  /// Headphone buttons' chapters ([HeadphoneControls]): to the next
  /// chapter's start, or back as the previous chapter button goes; false
  /// when the episode playing has none to go to.
  bool skipChapter({required bool forward}) {
    final song = currentSong.value;
    if (song == null || !song.isPodcastEpisode || chapters.isEmpty) {
      return false;
    }
    final to = chapterSkipTarget(
        chapters, progressBarStatus.value.current.inMilliseconds / 1000,
        forward: forward);
    if (to == null) return false;
    seek(Duration(milliseconds: (to * 1000).round()));
    return true;
  }

  /// Headphone buttons' bookmark ([HeadphoneControls]): the episode
  /// playing, where it is, said as the player's Bookmark this moment says
  /// it (when Riff is open).
  Future<PodcastBookmark?> bookmarkHere() async {
    final song = currentSong.value;
    if (song == null || !song.isPodcastEpisode) return null;
    final bookmark =
        await PodcastBookmarkStore.add(song, progressBarStatus.value.current);
    final context = Get.context;
    if (bookmark != null && context != null && context.mounted) {
      showBookmarkSavedSnack(context, bookmark);
    }
    return bookmark;
  }

  /// The star on the notification, the lock screen and Android Auto:
  /// stars the episode playing (the player's own: the one announced may
  /// show its chapter), or unstars it.
  Future<void> toggleStarPlaying() async {
    final song = currentSong.value;
    if (song == null || !song.isPodcastEpisode) return;
    if (StarredEpisodes.isStarred(song.id)) {
      await StarredEpisodes.unstar(song.id);
    } else {
      await StarredEpisodes.star(song);
    }
  }

  /// Seeks to the pending resume once [song] has just started; whether it
  /// did.
  bool _maybeApplyPendingResume(
      MediaItem song, Duration position, Duration total) {
    if (_pendingResumeId == song.id &&
        _pendingResumeMs > 1500 &&
        position.inMilliseconds < 4000) {
      final target = Duration(milliseconds: _pendingResumeMs);
      _pendingResumeId = null;
      if (total <= Duration.zero ||
          target < total - const Duration(seconds: 10)) {
        seek(target);
        return true;
      }
    }
    return false;
  }

  bool _isAbsItem(MediaItem? s) => s != null && s.isAudiobookshelf;

  /// A song started at a moment ([playFromLink]) or a long track's kept
  /// place: there once it plays (podcasts and audiobooks resume through
  /// their own progress).
  void _handleSongStart(Duration position) {
    final song = currentSong.value;
    if (song == null ||
        _pendingResumeId != song.id ||
        PodcastProgressService.isPodcastItem(song) ||
        _isAbsItem(song) ||
        song.isFreeAudiobook) {
      return;
    }
    final place = Duration(milliseconds: _pendingResumeMs);
    if (!_maybeApplyPendingResume(
        song, position, progressBarStatus.value.total)) {
      return;
    }
    // Its place is kept again once it has played a moment from there.
    _lastLongTrackSaveMs = DateTime.now().millisecondsSinceEpoch;
    if (_longTrackResumeId == song.id) {
      _longTrackResumeId = null;
      _sayLongTrackResumed(song.id, place);
    }
  }

  /// A song (not a podcast episode or an audiobook) [total] long that
  /// keeps its place ([LongTrackResume]).
  bool _isLongTrack(MediaItem song, Duration total) =>
      !song.isPodcastEpisode &&
      !song.isAudiobook &&
      LongTrackResume.keepsPlace(total);

  /// A long track's place, kept every 5 s as it plays.
  void _handleLongTrackProgress(Duration position) {
    final song = currentSong.value;
    final total = progressBarStatus.value.total;
    if (song == null || !_isLongTrack(song, total)) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastLongTrackSaveMs < 5000) return;
    if (_pendingResumeId == song.id) {
      // Its place is yet to be resumed; playing on from elsewhere (a
      // restored session), it won't be.
      if (position < const Duration(seconds: 4)) return;
      _pendingResumeId = null;
    }
    _lastLongTrackSaveMs = nowMs;
    _keepLongTrackPlace(song, position, total, nowMs);
  }

  /// Keeps [song]'s place, [position] into it, when it's a long track;
  /// not in a private session, nor while its kept place is yet to be
  /// resumed.
  void _keepLongTrackPlace(
      MediaItem? song, Duration position, Duration total, int nowMs) {
    if (song == null ||
        !_isLongTrack(song, total) ||
        _pendingResumeId == song.id ||
        PrivateSession.isActive) {
      return;
    }
    unawaited(LongTrackResume.save(song.id, position, total, nowMs: nowMs));
  }

  /// Says the long track [id] picked up at [place], with Start over.
  void _sayLongTrackResumed(String id, Duration place) {
    final target = undoSnackbarTarget(null);
    if (target == null || !target.messenger.mounted) return;
    target.messenger.hideCurrentSnackBar();
    target.messenger.showSnackBar(themedSnackbar(target.theme,
        'longTrackResumed'.trParams({'time': longTrackPlaceLabel(place)}),
        actionLabel: 'startOver'.tr, onAction: () => startLongTrackOver(id)));
  }

  /// The long track [id], resumed, starts over: back to its start while
  /// it's the one playing, its kept place forgotten.
  void startLongTrackOver(String id) {
    if (currentSong.value?.id == id) {
      _lastLongTrackSaveMs = DateTime.now().millisecondsSinceEpoch;
      seek(Duration.zero);
    }
    unawaited(LongTrackResume.forget(id));
  }

  /// Plays [songs] from the first, from [start] into it (a shared link's
  /// moment, YouTube's ?t=).
  Future<bool> playFromLink(List<MediaItem> songs,
      {Duration start = Duration.zero}) async {
    // The song playing now: there.
    if (songs.isNotEmpty &&
        start > Duration.zero &&
        currentSong.value?.id == songs.first.id) {
      seek(start);
      if (buttonState.value == PlayButtonState.paused) play();
      return true;
    }
    if (songs.isNotEmpty && start > Duration.zero) {
      _explicitStartId = songs.first.id;
      _explicitStartMs = start.inMilliseconds;
    }
    return playPlayListSong(songs, 0,
        playfrom: PlaylingFrom(type: PlaylingFromType.SELECTION));
  }

  String? _explicitStartId;
  int _explicitStartMs = 0;

  /// Play a podcast episode from [position] (a bookmark), or seek there if
  /// it's already the current episode.
  Future<bool> playPodcastAt(MediaItem item, Duration position,
      {String? from}) async {
    if (currentSong.value?.id == item.id) {
      seek(position);
      if (buttonState.value == PlayButtonState.paused) play();
      return true;
    }
    _explicitStartId = item.id;
    _explicitStartMs = position.inMilliseconds;
    return playPlayListSong(
      [item],
      0,
      playfrom: PlaylingFrom(
          type: PlaylingFromType.SELECTION, name: from ?? item.artist ?? ''),
      source: DiscoverySource.podcast,
    );
  }

  /// Play the queue's track at [index] from [position] (an audiobook
  /// bookmark), or seek there if it's the track playing.
  void playQueueItemAt(int index, Duration position) {
    if (index < 0 || index >= currentQueue.length) return;
    final item = currentQueue[index];
    if (currentSong.value?.id == item.id) {
      seek(position);
      if (buttonState.value == PlayButtonState.paused) play();
      return;
    }
    _explicitStartId = item.id;
    _explicitStartMs = position.inMilliseconds;
    seekByIndex(index);
  }

  /// The player's Mark as played: the playing podcast episode ends now, as
  /// if it had played out (the next episode, or a pause when continuous
  /// playback is off), and is marked played. Returns its Undo: unplayed
  /// again, back in its place in the queue and playing from where it was.
  /// Null when no episode is playing.
  VoidCallback? markCurrentEpisodePlayed() {
    final song = currentSong.value;
    if (song == null || !song.isPodcastEpisode || !_audioReady) return null;
    final at = progressBarStatus.value.current;
    final snapshot = PodcastLibrary.listenedSnapshot([song]);
    final finished = _finishEpisode();
    return () async {
      await finished;
      await PodcastLibrary.undoMarkAll(snapshot);
      final index = currentQueue.indexWhere((m) => m.id == song.id);
      if (index >= 0) {
        playQueueItemAt(index, at);
      } else {
        await playPodcastAt(song, at);
      }
    };
  }

  /// Ends the playing episode as if it had played out (the handler's
  /// finishEpisode): marked played, then the next one or a pause.
  Future<void> _finishEpisode() async {
    // A position save meanwhile would read as listening on and unmark it.
    _lastProgressSaveMs = DateTime.now().millisecondsSinceEpoch;
    try {
      // Video mode owns a paused audio pipeline: hand off first, as ⏭ does.
      await _handoffVideoThen(() async {
        await _audioHandler.customAction('finishEpisode');
        return true;
      });
    } catch (e) {
      printERROR('finishEpisode failed: $e');
    }
    PodcastLibrary.rev.value++;
  }

  /// Arms where [item], just started, plays from once it plays: a
  /// bookmark's or a link's moment ([playPodcastAt], [playFromLink]), a
  /// podcast episode's saved place (or past the intro its show skips), an
  /// audiobook's ([armResume]), a long track's kept place.
  @visibleForTesting
  void armStart(MediaItem item) {
    _longTrackResumeId = null;
    // A new song's place is kept once it has played a moment.
    _lastLongTrackSaveMs = DateTime.now().millisecondsSinceEpoch;
    if (_explicitStartId == item.id) {
      // Opened from a bookmark: start there, not at the saved position.
      _pendingResumeId = item.id;
      _pendingResumeMs = _explicitStartMs;
      _explicitStartId = null;
    } else if (PodcastProgressService.isPodcastItem(item)) {
      _pendingResumeId = item.id;
      // The saved position, or past the intro its show skips.
      _pendingResumeMs = podcastStartMs(
        savedMs: PodcastProgressService.positionMs(item.id) ?? 0,
        trim: PodcastPlaybackPrefs.trimForItem(item),
        totalMs: item.duration?.inMilliseconds ?? 0,
      );
    } else if (item.isAudiobook) {
      // Keep armResume() from the book's page if it targets this chapter
      // (a server's or a free one).
      if (_pendingResumeId != item.id) {
        _pendingResumeId = null;
        _pendingResumeMs = 0;
      }
    } else {
      // A long track plays on from the place it kept.
      final place = LongTrackResume.placeOf(item.id, item.duration);
      final resumes = place > Duration.zero;
      _pendingResumeId = resumes ? item.id : null;
      _pendingResumeMs = place.inMilliseconds;
      if (resumes) _longTrackResumeId = item.id;
    }
  }

  /// Arm a one-shot seek after playback starts (ABS resume / explicit offset).
  void armResume(String id, int offsetMs) {
    _pendingResumeId = id;
    _pendingResumeMs = offsetMs;
  }

  void _handleAbsProgress(Duration position) {
    final song = currentSong.value;
    if (song != null && song.isFreeAudiobook) {
      // Free (LibriVox) chapters: local resume only, no server session.
      _absLastTickMs = 0;
      final total = progressBarStatus.value.total;
      _maybeApplyPendingResume(song, position, total);
      final saveMs = DateTime.now().millisecondsSinceEpoch;
      if (saveMs - _lastAudiobookSaveMs >= 5000) {
        _lastAudiobookSaveMs = saveMs;
        AudiobookProgressService.save(song, position, total, nowMs: saveMs);
      }
      return;
    }
    if (!_isAbsItem(song)) {
      _absLastTickMs = 0;
      return;
    }
    final total = progressBarStatus.value.total;
    _maybeApplyPendingResume(song!, position, total);

    // Local resume point (works offline / without a server session); was
    // never written, so the local fallback in audiobook_play never found one.
    final saveMs = DateTime.now().millisecondsSinceEpoch;
    if (saveMs - _lastAudiobookSaveMs >= 5000) {
      _lastAudiobookSaveMs = saveMs;
      AudiobookProgressService.save(song, position, total, nowMs: saveMs);
    }

    final sessionId = song.absSessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    if (!Get.isRegistered<AudiobookshelfService>()) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Accumulate listened delta only while actively playing.
    if (buttonState.value == PlayButtonState.playing) {
      if (_absLastTickMs > 0) {
        final deltaSec = (nowMs - _absLastTickMs) / 1000.0;
        // Cap to avoid huge jumps after seek/pause/background gaps.
        if (deltaSec > 0 && deltaSec < 30) {
          _absTimeListenedSec += deltaSec;
        }
      }
      _absLastTickMs = nowMs;
    } else {
      _absLastTickMs = 0;
    }

    if (nowMs - _lastAbsSyncMs < 10000) return;
    _lastAbsSyncMs = nowMs;

    final startOff = song.absStartOffsetSec;
    final bookAbsolute = startOff + position.inMilliseconds / 1000.0;
    final bookDuration = absQueuedBookSec(currentQueue);
    if (bookDuration > 0) {
      _absSyncedSessionId = sessionId;
      _absSyncedBookSec = bookDuration;
    }
    final listened = _absTimeListenedSec;
    _absTimeListenedSec = 0;

    unawaited(Get.find<AudiobookshelfService>().syncProgress(
      sessionId: sessionId,
      currentTime: bookAbsolute,
      duration:
          bookDuration > 0 ? bookDuration : (total.inMilliseconds / 1000.0),
      timeListened: listened,
      isPaused: buttonState.value != PlayButtonState.playing,
    ));
  }

  /// Book length seen by the last progress sync of session
  /// [_absSyncedSessionId], for closing it once the queue has moved on.
  String? _absSyncedSessionId;
  double _absSyncedBookSec = 0;

  /// Best-effort ABS session close when leaving an ABS item. [outgoing] is
  /// the item's own progress: by now the shared progress bar (and often the
  /// queue) already belong to the incoming item.
  void _maybeCloseAbsSession(
      MediaItem? previous, MediaItem? next, OutgoingProgress outgoing) {
    if (previous == null || !_isAbsItem(previous)) return;
    if (next != null && next.id == previous.id) return;
    final sessionId = previous.absSessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    if (!Get.isRegistered<AudiobookshelfService>()) return;

    final startOff = previous.absStartOffsetSec;
    final bookAbsolute = startOff + outgoing.position.inMilliseconds / 1000.0;
    final stillQueued = currentQueue.any((m) => m.id == previous.id);
    final bookDuration = absCloseBookSec(
      queuedBookSec: stillQueued ? absQueuedBookSec(currentQueue) : 0,
      syncedBookSec: _absSyncedSessionId == sessionId ? _absSyncedBookSec : 0,
      outgoingTotal: outgoing.total,
    );
    final listened = _absTimeListenedSec;
    _absTimeListenedSec = 0;
    _absLastTickMs = 0;
    _lastAbsSyncMs = 0;

    unawaited(Get.find<AudiobookshelfService>().closeSession(
      sessionId,
      currentTime: bookAbsolute,
      duration: bookDuration,
      timeListened: listened,
    ));
  }

  Future<void> _loadChaptersFor(MediaItem item) async {
    _chaptersForSongId = item.id;
    chapters.clear();
    inAdChapter.value = false;
    final url = episodeChaptersUrl(item);
    var chs = url != null && url.isNotEmpty
        ? await PodcastService.chapters(url)
        // None in the feed: the episode's MP3 may carry its own (ID3).
        : await Id3Chapters.forEpisode(item);
    // None in either: its show notes may list its parts by their start.
    if (chs.isEmpty && item.isPodcastEpisode) {
      chs = showNotesChapters(episodeNotes(item), length: item.duration);
    }
    if (_chaptersForSongId == item.id) chapters.assignAll(chs);
  }

  /// The chapter covering [sec], if any (chapters are start-only + sorted).
  PodcastChapter? _chapterAt(double sec) {
    PodcastChapter? current;
    for (final c in chapters) {
      if (c.startSec <= sec) {
        current = c;
      } else {
        break;
      }
    }
    return current;
  }

  /// Seek target just past the current chapter: its endSec, else the next
  /// chapter's start, else null (last chapter).
  Duration? _endOfChapter(PodcastChapter c) {
    if (c.endSec != null) {
      return Duration(milliseconds: (c.endSec! * 1000).round());
    }
    final idx = chapters.indexOf(c);
    if (idx >= 0 && idx + 1 < chapters.length) {
      return Duration(
          milliseconds: (chapters[idx + 1].startSec * 1000).round());
    }
    return null;
  }


  // ---- Podcast segments: chapters, SponsorBlock, manual marks ----

  /// The current episode's segments, resolved against the podcast segment
  /// settings: ignored ones dropped, overlapping ones merged.
  final podcastSegments = <PodcastSegment>[].obs;

  /// The segment playing now that the Skip pill offers to jump over.
  final activePodcastSegment = Rxn<PodcastSegment>();

  /// Start of a segment being marked by hand (seconds), until its end is.
  final manualSegmentStart = Rxn<double>();

  String? _segmentsForId;
  List<PodcastSegment> _sbPodcastSegments = const [];
  double? _prevSegmentSec;
  bool _segmentSeekInFlight = false;
  bool _segmentMuted = false;
  bool _segmentsDurationKnown = false;

  /// Per episode, for this app session: segments already auto-skipped
  /// (never twice) and segments the user undid (left alone from then on).
  final Map<String, Set<String>> _segmentsSkipped = {};
  final Map<String, Set<String>> _segmentsDisabled = {};

  void _clearPodcastSegments() {
    _segmentsForId = null;
    _sbPodcastSegments = const [];
    if (podcastSegments.isNotEmpty) podcastSegments.clear();
    activePodcastSegment.value = null;
    manualSegmentStart.value = null;
    _setSegmentMute(false);
  }

  Future<void> _loadPodcastSegmentsFor(MediaItem item) async {
    _clearPodcastSegments();
    _segmentsForId = item.id;
    _prevSegmentSec = null;
    _segmentsDurationKnown = false;
    _rebuildPodcastSegments();
    // YouTube-sourced episodes: SponsorBlock, in the background.
    if (looksLikeYoutubeVideoId(item.id) &&
        Get.isRegistered<SponsorBlockService>()) {
      final segs =
          await Get.find<SponsorBlockService>().podcastSegments(item.id);
      if (_segmentsForId != item.id) return;
      _sbPodcastSegments = segs;
      _rebuildPodcastSegments();
    }
  }

  void _rebuildPodcastSegments() {
    final item = currentSong.value;
    if (item == null || !item.isPodcastEpisode || item.id != _segmentsForId) {
      return;
    }
    final totalMs = progressBarStatus.value.total.inMilliseconds;
    final durSec = (totalMs > 0
            ? totalMs
            : (item.duration?.inMilliseconds ?? 0)) /
        1000.0;
    podcastSegments.assignAll(resolveSegments(
      [
        ...segmentsFromChapters(chapters, durSec),
        ..._sbPodcastSegments,
        ...PodcastSegmentStore.manual(item.id),
      ],
      PodcastSegmentStore.actions,
      skippingOn: currentPodcastProfile.segmentSkip,
    ));
  }

  /// One position tick of a podcast episode: mute, the Skip pill, and the
  /// auto-skip (only when playback runs into a segment from before it,
  /// never twice but for chapters ticked off, never a segment the user
  /// undid).
  void _handlePodcastSegments(Duration position) {
    final item = currentSong.value;
    if (item == null || !item.isPodcastEpisode) return;
    if (!_segmentsDurationKnown &&
        progressBarStatus.value.total > Duration.zero) {
      _segmentsDurationKnown = true;
      _rebuildPodcastSegments();
    }
    final sec = position.inMilliseconds / 1000.0;
    final prev = _prevSegmentSec ?? sec;
    _prevSegmentSec = sec;
    final disabled = _segmentsDisabled[item.id] ?? const <String>{};
    var active = podcastSegments.isEmpty
        ? null
        : segmentAt(podcastSegments, sec);
    if (active != null && disabled.contains(active.id)) active = null;

    _setSegmentMute(active?.action == SegmentAction.mute);
    final pill =
        active != null && active.action != SegmentAction.mute ? active : null;
    if (activePodcastSegment.value?.id != pill?.id) {
      activePodcastSegment.value = pill;
    }
    if (inAdChapter.value != (pill != null)) inAdChapter.value = pill != null;

    if (active == null ||
        active.action != SegmentAction.autoSkip ||
        _segmentSeekInFlight) {
      return;
    }
    final skipped = _segmentsSkipped.putIfAbsent(item.id, () => <String>{});
    final again = skipped.contains(active.id) &&
        active.category != SegmentCategory.chapter;
    if (again || !enteredFromBefore(active, prev, sec)) return;
    // A seek a person just made (app, notification, Android Auto) wins.
    if (!autoSkipAllowed(
        lastSeek: _tagged?.lastUserSeek,
        nowMs: DateTime.now().millisecondsSinceEpoch,
        segStartSec: active.start,
        segEndSec: active.end)) {
      return;
    }
    final exit = SegmentSkip.of(active,
        totalMs: progressBarStatus.value.total.inMilliseconds);
    if (exit == SegmentSkip.none) return;
    skipped.add(active.id);
    if (exit == SegmentSkip.endEpisode) {
      unawaited(_finishEpisode());
      return;
    }
    _skipSegment(active, fromSec: sec, auto: true);
  }

  Future<void> _skipSegment(PodcastSegment s,
      {required double fromSec, required bool auto}) async {
    _segmentSeekInFlight = true;
    _prevSegmentSec = s.end;
    activePodcastSegment.value = null;
    printINFO('Podcast segment skip ${s.category.apiName} '
        '${s.start.toStringAsFixed(1)}s → ${s.end.toStringAsFixed(1)}s');
    final target = Duration(milliseconds: (s.end * 1000).round());
    final h = _tagged;
    try {
      if (auto && h != null && !_videoModeActive) {
        // Short duck, seek, fade back in; dropped if someone seeks first.
        final done = await h.autoSkipTo(target,
            seekSerial: h.userSeekSerial, itemId: currentSong.value?.id);
        if (!done) {
          _prevSegmentSec = null;
          return;
        }
      } else {
        seek(target,
            source: auto
                ? PlaybackCommandSource.autoSkip
                : PlaybackCommandSource.user);
      }
      unawaited(PodcastSegmentStore.addTimeSaved(
          Duration(milliseconds: ((s.end - fromSec) * 1000).round())));
      if (auto) _showSegmentSkippedSnack(s, fromSec);
    } finally {
      Future.delayed(const Duration(milliseconds: 350),
          () => _segmentSeekInFlight = false);
    }
  }

  void _showSegmentSkippedSnack(PodcastSegment s, double fromSec) {
    final ctx = homeScaffoldkey.currentContext;
    if (ctx == null) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      content: Text('segmentSkipped'.trParams({
        'category': s.category.labelKey.tr,
        'length': formatSegmentLength(s.end - fromSec),
      })),
      action: SnackBarAction(
        label: 'undo'.tr,
        onPressed: () => undoSegmentSkip(s, fromSec),
      ),
    ));
  }

  /// Undo an auto-skip: back to the segment start, and leave this segment
  /// alone for the rest of the session.
  void undoSegmentSkip(PodcastSegment s, double fromSec) {
    final id = currentSong.value?.id;
    if (id == null) return;
    _segmentsDisabled.putIfAbsent(id, () => <String>{}).add(s.id);
    unawaited(PodcastSegmentStore.addTimeSaved(
        -Duration(milliseconds: ((s.end - fromSec) * 1000).round())));
    _prevSegmentSec = s.start;
    seek(Duration(milliseconds: (s.start * 1000).round()));
  }

  void _setSegmentMute(bool muted) {
    if (muted == _segmentMuted) return;
    _segmentMuted = muted;
    _audioHandler.customAction('setSegmentMute', {'muted': muted});
  }

  /// Manual segments (RSS episodes): first call marks the start, second
  /// stores the segment with [category].
  bool get canMarkSegments {
    final s = currentSong.value;
    return s != null && s.isPodcastEpisode && s.id.startsWith('podcast_');
  }

  void markSegmentStart() {
    manualSegmentStart.value =
        progressBarStatus.value.current.inMilliseconds / 1000.0;
  }

  Future<bool> markSegmentEnd(SegmentCategory category) async {
    final s = currentSong.value;
    final start = manualSegmentStart.value;
    if (s == null || start == null) return false;
    final end = progressBarStatus.value.current.inMilliseconds / 1000.0;
    manualSegmentStart.value = null;
    final a = end < start ? end : start, b = end < start ? start : end;
    if (b - a < 1) return false;
    await PodcastSegmentStore.addManual(
        s.id,
        PodcastSegment(
          id: 'm_${DateTime.now().millisecondsSinceEpoch}',
          start: a,
          end: b,
          category: category,
          source: SegmentSource.manual,
        ));
    // Marked while inside it: don't jump away from what was just marked.
    _segmentsSkipped.remove(s.id);
    return true;
  }

  /// Manual "Skip ad": jump past the current ad chapter if in one, else jump
  /// forward 30s (universal fallback for feeds without chapters).
  void skipAd() {
    final sec = progressBarStatus.value.current.inMilliseconds / 1000.0;
    final seg = activePodcastSegment.value;
    final id = currentSong.value?.id;
    if (seg != null && id != null) {
      _segmentsSkipped.putIfAbsent(id, () => <String>{}).add(seg.id);
      _skipSegment(seg, fromSec: sec, auto: false);
      return;
    }
    final current = _chapterAt(sec);
    if (current != null && current.isAd) {
      final target = _endOfChapter(current);
      if (target != null) {
        seek(target);
        return;
      }
    }
    seekBy(const Duration(seconds: 30));
  }

  Future<void> _loadSponsorBlockFor(String videoId) async {
    _sponsorVideoId = videoId;
    _sponsorSegments = const [];
    _lastSkippedSegmentUuid = null;
    // Podcast episodes use the podcast segment engine instead.
    if (isCurrentSongPodcast) return;
    if (!Get.isRegistered<SponsorBlockService>()) return;
    final sb = Get.find<SponsorBlockService>();
    if (!sb.enabled) return;
    final segs = await sb.getSegments(videoId);
    // Only apply if still the same song.
    if (_sponsorVideoId == videoId) {
      _sponsorSegments = segs;
    }
  }

  /// Public entry used when the user toggles SponsorBlock in settings.
  void reloadSponsorBlock() {
    final id = currentSong.value?.id;
    if (id != null) unawaited(_loadSponsorBlockFor(id));
  }

  void _maybeSkipSponsorBlock(Duration position) {
    if (_sponsorSegments.isEmpty || _sponsorSeekInFlight) return;
    if (!Get.isRegistered<SponsorBlockService>()) return;
    final sb = Get.find<SponsorBlockService>();
    if (!sb.enabled) return;

    final sec = position.inMilliseconds / 1000.0;
    final active = sb.activeSegment(_sponsorSegments, sec);
    if (active == null) return;
    if (active.uuid == _lastSkippedSegmentUuid) return;
    if (isCurrentSongPodcast) return;

    final target = sb.seekTargetIfInSegment(_sponsorSegments, sec);
    if (target == null) return;

    // A person just sought (or sought into this segment): leave it be for
    // this pass; it still shows, and the next play skips it as usual.
    final h = _tagged;
    if (!autoSkipAllowed(
        lastSeek: h?.lastUserSeek,
        nowMs: DateTime.now().millisecondsSinceEpoch,
        segStartSec: active.start,
        segEndSec: active.end)) {
      _lastSkippedSegmentUuid = active.uuid;
      return;
    }

    // Don't skip past the end of the track — just leave it to natural end.
    final total = progressBarStatus.value.total;
    if (total > Duration.zero &&
        target >= total - const Duration(milliseconds: 400)) {
      return;
    }

    _lastSkippedSegmentUuid = active.uuid;
    _sponsorSeekInFlight = true;
    printINFO(
        'SponsorBlock skip ${active.category} ${active.start.toStringAsFixed(1)}s → ${active.end.toStringAsFixed(1)}s');
    final Future<void> skip = h != null && !_videoModeActive
        ? h
            .autoSkipTo(target,
                seekSerial: h.userSeekSerial, itemId: currentSong.value?.id)
            .then((_) {})
        : Future.sync(
            () => seek(target, source: PlaybackCommandSource.autoSkip));
    skip.whenComplete(() => Future.delayed(
        const Duration(milliseconds: 350), () => _sponsorSeekInFlight = false));
  }

  final _bufferedUiThrottle = BufferedUiThrottle();

  void _listenForChangesInBufferedPosition() {
    _subscriptions.add(_audioHandler.playbackState.listen((playbackState) {
      if (_videoModeActive) return;
      final oldState = progressBarStatus.value;
      if (progressBarStatus.value.total.inSeconds != 0 &&
          playbackState.bufferedPosition.inSeconds /
                  progressBarStatus.value.total.inSeconds >=
              0.98) {
        if (_newSongFlag) {
          _audioHandler.customAction(
              "checkWithCacheDb", {'mediaItem': currentSong.value!});
          _newSongFlag = false;
        }
      }
      final buffered = playbackState.bufferedPosition;
      // Skip no-op / dense buffered updates — they rebuild progress widgets.
      if (!_bufferedUiThrottle.shouldUpdate(
          buffered: buffered, previousUiBuffered: oldState.buffered)) {
        return;
      }
      progressBarStatus.update((val) {
        val!.buffered = buffered;
        val.current = oldState.current;
        val.total = oldState.total;
      });
    }));
  }

  void _listenForChangesInDuration() {
    _subscriptions.add(_audioHandler.mediaItem.listen((mediaItem) async {
      // ProgressBarState is mutable and Rx.update mutates it in place, so
      // `oldState` aliased the very object being retargeted — the current/
      // buffered reassignments were no-ops, and reading `.total` afterwards
      // yielded the INCOMING item's duration. Saving the outgoing episode
      // against that denominator deleted it from the progress box (a 30-min
      // position in a 3-min "duration" reads as finished). Copy out by value
      // before retargeting.
      final outgoingProgress =
          retargetProgressBar(progressBarStatus.value, mediaItem?.duration);
      progressBarStatus.refresh();
      if (mediaItem != null) {
        printINFO(mediaItem.title);
        _newSongFlag = true;
        // Capture position before switching so DiscoveryService can score the skip.
        final posMs = outgoingProgress.position.inMilliseconds;
        // Persist the outgoing podcast episode against ITS OWN duration.
        PodcastProgressService.save(currentSong.value,
            Duration(milliseconds: posMs), outgoingProgress.total,
            nowMs: DateTime.now().millisecondsSinceEpoch);
        AudiobookProgressService.save(currentSong.value,
            Duration(milliseconds: posMs), outgoingProgress.total,
            nowMs: DateTime.now().millisecondsSinceEpoch);
        // Close ABS listening session when leaving an ABS item (best effort).
        _maybeCloseAbsSession(currentSong.value, mediaItem, outgoingProgress);
        final outgoing = currentSong.value;
        // The handler re-emits the playing item after queue edits, shuffle
        // and stream retries; only a different id is a song change.
        final songChanged = outgoing?.id != mediaItem.id;
        // The long track left keeps its place there.
        if (songChanged) {
          _keepLongTrackPlace(outgoing, Duration(milliseconds: posMs),
              outgoingProgress.total, DateTime.now().millisecondsSinceEpoch);
        }
        if (songChanged &&
            outgoing != null &&
            !_playIsPrivate &&
            shouldScrobble(
                item: outgoing,
                listened: Duration(milliseconds: posMs),
                total: outgoingProgress.total)) {
          ListenBrainzService.submitListen(outgoing);
        }
        currentSong.value = mediaItem;
        if (songChanged) {
          // Reset per-song UI now, before the awaits below, so lyrics the
          // user opens for the new song aren't wiped when they finish.
          lyrics.value = {"synced": "", "plainLyrics": "", "ttml": ""};
          showLyricsflag.value = false;
          if (isDesktopLyricsDialogOpen) {
            Navigator.pop(Get.context!);
          }
          // reset player visible state when player is in gesture mode
          if (Get.find<SettingsScreenController>().playerUi.value == 1) {
            gesturePlayerVisibleState.value = 2;
          }
        }
        if (showContinueListening.isTrue) {
          showContinueListening.value = false;
        }
        clearPlaybackError();
        // Where the new item plays from; the same one re-emitted keeps it.
        if (songChanged) armStart(mediaItem);
        currentSongIndex.value = currentQueue
            .indexWhere((element) => element.id == currentSong.value!.id);
        // The handler re-emits the *currently playing* item on non-play events
        // (duration discovery at queue index 0, queue reorder/shuffle, item
        // removal). Those must not be logged as a new play. Decided
        // synchronously, before the first await, so a second event arriving
        // while this callback is suspended is rejected.
        final isNewPlay = _playLogGate.accept(mediaItem.id);
        if (isNewPlay) {
          // Finished podcast downloads whose show auto-deletes them.
          unawaited(PodcastLibrary.sweepDownloads(currentId: mediaItem.id));
          // Fire-and-forget SponsorBlock load for this video id.
          unawaited(_loadSponsorBlockFor(mediaItem.id));
          // Podcast chapters and segments (SponsorBlock, manual marks).
          unawaited(_loadChaptersFor(mediaItem));
          if (mediaItem.isPodcastEpisode) {
            unawaited(_loadPodcastSegmentsFor(mediaItem));
            unawaited(PodcastTranscriptService.probe(mediaItem));
          } else {
            _clearPodcastSegments();
          }
        }
        await _checkFav();
        if (isNewPlay) {
          // A private session records nothing of what plays in it; a
          // playlist left out of your taste profile, only its history.
          final private = PrivateSession.isActive;
          final untasted =
              !private && TasteExclusions.excludesPlay(playinfrom.value);
          _playIsPrivate = private || untasted;
          // Use this callback's item: currentSong may already be the next
          // song after the awaits.
          if (!private) {
            await _addToRP(mediaItem);
            if (!untasted) StatsService.recordPlay(mediaItem);
            unawaited(PodcastHistory.add(mediaItem));
            // Songs only, as they're scrobbled.
            if (!untasted &&
                !mediaItem.isPodcastEpisode &&
                !mediaItem.isAudiobook) {
              unawaited(ListenBrainzService.playingNow(mediaItem));
            }
          }
          if (Get.isRegistered<SettingsScreenController>()) {
            unawaited(Get.find<SettingsScreenController>()
                .maybePromptBatteryOptimization());
          }
          if (Get.isRegistered<DiscoveryService>()) {
            // Taste bookkeeping doesn't gate playback, so don't hold up
            // radio continuation behind it; chain the calls so quick skips
            // are still recorded in order. A private play isn't started
            // (the song before it still ends as usual).
            final discovery = Get.find<DiscoveryService>();
            final logged = private || untasted ? null : mediaItem;
            _discoveryChain = _discoveryChain
                .then(
                    (_) => discovery.onMediaChanged(logged, positionMs: posMs))
                .catchError((Object e) {
              printERROR('Discovery onMediaChanged failed: $e');
            });
          }
        }
        if (_shouldFetchRadioContinuation()) {
          await _fetchRadioContinuation();
        }
      }
    }));
  }

  void _listenForPlaylistChange() {
    _subscriptions.add(_audioHandler.queue.listen((queue) {
      // The handler edits one list in place and re-emits it; GetX drops a
      // same-object assignment, so the queue UI (and SmartQueue's worker)
      // never heard about adds/removes/reorders. Copy to notify.
      currentQueue.value = List.of(queue);
    }));
  }

  Future<void> _restorePrevSession() async {
    final restrorePrevSessionEnabled =
        _prefs.get("restrorePlaybackSession") ?? false;
    if (restrorePrevSessionEnabled) {
      final prevSessionData = await Hive.openBox("prevSessionData");
      if (prevSessionData.keys.isNotEmpty) {
        final songList = (prevSessionData.get("queue") as List)
            .map((e) => MediaItemBuilder.fromJson(e))
            .toList();
        final int currentIndex = prevSessionData.get("index");
        final int position = prevSessionData.get("position");
        await _audioHandler.addQueueItems(songList);
        _playerPanelCheck(restoreSession: true);
        await _audioHandler.customAction("playByIndex", {
          "index": currentIndex,
          "position": position,
          "restoreSession": true
        });
      }
    }
  }

  /// Peek Hive for a saved queue so Home can show a resume chip when the
  /// player is idle (auto-restore off, or restore has not started playback).
  Future<void> _refreshContinueListeningChip() async {
    try {
      if (currentSong.value != null && !initFlagForPlayer) {
        showContinueListening.value = false;
        return;
      }
      final box = Hive.isBoxOpen("prevSessionData")
          ? Hive.box("prevSessionData")
          : await Hive.openBox("prevSessionData");
      final rawQueue = box.get("queue");
      if (rawQueue is! List || rawQueue.isEmpty) {
        showContinueListening.value = false;
        return;
      }
      final index = (box.get("index") as int?) ?? 0;
      final safe = index.clamp(0, rawQueue.length - 1);
      final item = MediaItemBuilder.fromJson(rawQueue[safe]);
      continueListeningTitle.value = item.title;
      continueListeningItem.value = item;
      showContinueListening.value = true;
    } catch (_) {
      showContinueListening.value = false;
    }
  }

  /// Hide the Home continue chip without starting playback.
  void dismissContinueListening() {
    showContinueListening.value = false;
  }

  /// Resume the Hive-saved queue from its stored index/position and play.
  Future<bool> resumeSavedSession() async {
    showContinueListening.value = false;
    await _waitForAudioHandler();
    try {
      final prevSessionData = Hive.isBoxOpen("prevSessionData")
          ? Hive.box("prevSessionData")
          : await Hive.openBox("prevSessionData");
      final rawQueue = prevSessionData.get("queue");
      if (rawQueue is! List ||
          !canResumeSavedSession(
            audioReady: _audioReady,
            savedQueueLength: rawQueue.length,
          )) {
        return false;
      }
      final songList =
          rawQueue.map((e) => MediaItemBuilder.fromJson(e)).toList();
      final int savedIndex = (prevSessionData.get("index") as int?) ?? 0;
      final int position = (prevSessionData.get("position") as int?) ?? 0;
      final index = savedIndex.clamp(0, songList.length - 1);
      // Always load the saved queue — a leftover failed session must not
      // play at the saved index of the wrong list.
      await _audioHandler.updateQueue(songList);
      _playerPanelCheck(restoreSession: true);
      final result = await _audioHandler.customAction("playByIndex", {
        "index": index,
        "position": position,
        "restoreSession": false,
      });
      return !playByIndexHardFailed(result);
    } catch (e) {
      printERROR("resumeSavedSession failed: $e");
      return false;
    }
  }

  /// Last track, or ≤3 songs left — fetch the next radio batch once.
  bool _shouldFetchRadioContinuation() {
    if (radioInitiatorItem == null || currentSong.value == null) {
      return false;
    }
    final isLast = currentQueue.isNotEmpty &&
        currentSong.value!.id == currentQueue.last.id;
    return radioShouldFetchContinuation(
      radioOn: isRadioModeOn,
      inFlight: _radioContinuationInFlight,
      queueLength: currentQueue.length,
      currentIndex: currentSongIndex.value,
      isLastTrack: isLast,
    );
  }

  void _listenForCustomEvents() {
    _subscriptions.add(_audioHandler.customEvent.listen((event) {
      if (event['eventType'] == 'playFromMediaId') {
        unawaited(playViaAndroidAuto(event['songId'], event['libraryId']));
      }
      if (event['eventType'] == 'playFromSearch') {
        unawaited(playFromVoiceSearch('${event['query'] ?? ''}'));
      }
    }));
  }

  ///pushSongToPlaylist method clear previous song queue, plays the tapped song and push related
  ///songs into Queue
  Future<bool> pushSongToQueue(MediaItem? mediaItem,
      {String? playlistid, bool radio = false}) async {
    await _waitForAudioHandler();
    if (!_audioReady) return false;
    try {
      /// update playing from value
      playinfrom.value = PlaylingFrom(
          type: PlaylingFromType.SELECTION,
          name: radio ? "randomRadio".tr : "randomSelection".tr);

      /// set global radio mode flag
      isRadioModeOn = radio;

      List<MediaItem> tracks;
      if (radio && mediaItem != null && Get.isRegistered<DiscoveryService>()) {
        try {
          tracks = await Get.find<DiscoveryService>().smartRadioBatch(
            mediaItem,
            sessionHistory: const [],
            limit: 25,
          );
          // Ensure seed is first if missing
          if (tracks.isEmpty || tracks.first.id != mediaItem.id) {
            tracks = [
              DiscoveryService.withSource(mediaItem, DiscoverySource.userClick),
              ...tracks
            ];
          }
        } catch (_) {
          final content = await _musicServices.getWatchPlaylist(
              videoId: mediaItem.id, radio: radio, playlistId: playlistid);
          radioContinuationParam = content['additionalParamsForNext'];
          tracks = DiscoveryService.tagAll(
              List<MediaItem>.from(content['tracks']), DiscoverySource.radio);
        }
      } else {
        final content = await _musicServices.getWatchPlaylist(
            videoId: mediaItem?.id ?? "", radio: radio, playlistId: playlistid);
        radioContinuationParam = content['additionalParamsForNext'];
        final src = radio ? DiscoverySource.radio : DiscoverySource.userClick;
        tracks = Get.isRegistered<DiscoveryService>()
            ? DiscoveryService.tagAll(
                List<MediaItem>.from(content['tracks']), src)
            : List<MediaItem>.from(content['tracks']);
      }
      if (tracks.isEmpty && mediaItem != null) {
        tracks = [
          Get.isRegistered<DiscoveryService>()
              ? DiscoveryService.withSource(mediaItem,
                  radio ? DiscoverySource.radio : DiscoverySource.userClick)
              : mediaItem
        ];
      }
      if (tracks.isEmpty) return false;

      // Await the queue swap before play — the old fire-and-forget
      // updateQueue raced setSourceNPlay and could drop the first track.
      await _audioHandler.updateQueue(tracks);
      if (isShuffleModeEnabled.isTrue) {
        await _audioHandler.customAction("shuffleCmd", {"index": 0});
      }

      final radioOnCurrent = radio && (currentSong.value?.id == mediaItem?.id);
      // Broadcast current mediaitem via Audio Service as list is updated
      // if radio is started on current playing song
      if (radioOnCurrent) {
        _audioHandler
            .customAction("upadateMediaItemInAudioService", {"index": 0});
      }

      if (playlistid != null) {
        _playerPanelCheck();
        final result =
            await _audioHandler.customAction("playByIndex", {"index": 0});
        return !playByIndexHardFailed(result);
      }
      if (radioOnCurrent) {
        return true;
      }

      if (_prefs.get("discoverContentType") == "BOLI") {
        Get.find<HomeScreenController>()
            .changeDiscoverContent("BOLI", songId: mediaItem!.id);
      }
      _playerPanelCheck();
      final result =
          await _audioHandler.customAction("playByIndex", {"index": 0});

      // disable queue loop mode when radio is started
      if (radio &&
          isQueueLoopModeEnabled.isTrue &&
          isShuffleModeEnabled.isFalse) {
        toggleQueueLoopMode();
      }
      return !playByIndexHardFailed(result);
    } catch (_) {
      return false;
    }
  }

  Future<bool> playPlayListSong(List<MediaItem> mediaItems, int index,
      {PlaylingFrom? playfrom, DiscoverySource? source}) async {
    await _waitForAudioHandler();
    if (!canStartPlayback(
      audioReady: _audioReady,
      itemCount: mediaItems.length,
    )) {
      return false;
    }
    if (index < 0 || index >= mediaItems.length) return false;
    // Podcast shows can have thousands of episodes with long notes: send a
    // window, with shortened notes, so the media session can't overflow.
    if (mediaItems[index].isPodcastEpisode) {
      final q = prepareLongFormQueue(mediaItems, index);
      printINFO('Long-form queue: ${q.items.length} of ${mediaItems.length} '
          'episodes, playing ${mediaItems[index].id}');
      mediaItems = q.items;
      index = q.index;
    }

    isRadioModeOn = false;
    //open player pane,set current song and push first song into playing list,

    /// update playing from value
    playinfrom.value =
        playfrom ?? PlaylingFrom(type: PlaylingFromType.SELECTION);
    // For the Library's "Recently played" sort (not in a private session).
    if (playfrom != null &&
        !PrivateSession.isActive &&
        (playfrom.type == PlaylingFromType.PLAYLIST ||
            playfrom.type == PlaylingFromType.ALBUM)) {
      unawaited(CollectionRecents.markPlayed(playfrom.id));
    }

    //for changing home content based on last interation
    Future.delayed(const Duration(seconds: 3), () {
      if (_prefs.get("discoverContentType") == "BOLI") {
        Get.find<HomeScreenController>()
            .changeDiscoverContent("BOLI", songId: mediaItems[index].id);
      }
    });

    _playerPanelCheck();
    final fallback = source ?? sourceFromPlaylingFrom(playfrom);
    final tagged = ensureDiscoverySources(mediaItems, fallback);
    await _audioHandler.updateQueue(tagged);
    if (isShuffleModeEnabled.value) {
      await _audioHandler.customAction("shuffleCmd", {"index": index});
    }
    final result =
        await _audioHandler.customAction("playByIndex", {"index": index});
    return !playByIndexHardFailed(result);
  }

  Future<bool> startRadio(MediaItem? mediaItem, {String? playlistid}) async {
    radioInitiatorItem = mediaItem ?? playlistid;
    return pushSongToQueue(mediaItem, playlistid: playlistid, radio: true);
  }

  /// Home "Riff Wave" — reliable personal radio.
  ///
  /// Builds a queue first, then [playByIndex], and keeps radio mode on so
  /// the stream continues past the first batch.
  Future<bool> startRiffWave() async {
    await _waitForAudioHandler();
    if (!_audioReady) {
      // Return false so UI can show a clear local message (not networkError).
      return false;
    }

    playinfrom.value = PlaylingFrom(
      type: PlaylingFromType.SELECTION,
      name: 'riffWave'.tr,
    );

    final seed = _resolveRiffWaveSeed();
    List<MediaItem> tracks = [];

    // Mood chips map to DiscoveryService.exploration — try that first.
    if (seed != null &&
        seed.id.isNotEmpty &&
        Get.isRegistered<DiscoveryService>()) {
      try {
        tracks = await Get.find<DiscoveryService>().smartRadioBatch(
          seed,
          sessionHistory: const [],
          limit: 25,
        );
      } catch (_) {}
    }

    // YTM radio works cold when discovery has no candidates yet.
    if (tracks.isEmpty && seed != null && seed.id.isNotEmpty) {
      try {
        final content = await _musicServices.getWatchPlaylist(
          videoId: seed.id,
          radio: true,
          limit: 30,
        );
        radioContinuationParam = content['additionalParamsForNext'];
        tracks = List<MediaItem>.from(content['tracks'] ?? const []);
      } catch (_) {
        tracks = [];
      }
    }

    // Cached Daily Mix as a offline-ish fallback queue.
    if (tracks.isEmpty && Get.isRegistered<DiscoveryService>()) {
      final mixes = Get.find<DiscoveryService>().dailyMixes;
      if (mixes.isNotEmpty && mixes.first.tracks.isNotEmpty) {
        try {
          tracks = mixes.first.tracks
              .map((m) => MediaItemBuilder.fromJson(m))
              .where((m) => m.id.isNotEmpty)
              .toList();
        } catch (_) {}
      }
    }

    if (tracks.isEmpty) {
      if (seed == null || seed.id.isEmpty) return false;
      tracks = [seed];
    } else {
      tracks = RiffWave.withSeedFirst(tracks, seed);
    }

    // Never route through playPlayListSong — it clears isRadioModeOn.
    isRadioModeOn = true;
    radioInitiatorItem = seed ?? tracks.first;
    _playerPanelCheck();

    final tagged = Get.isRegistered<DiscoveryService>()
        ? DiscoveryService.tagAll(tracks, DiscoverySource.radio)
        : tracks;

    await _audioHandler.updateQueue(tagged);
    if (isShuffleModeEnabled.isTrue) {
      await _audioHandler.customAction('shuffleCmd', {'index': 0});
    }
    final result =
        await _audioHandler.customAction('playByIndex', {'index': 0});

    if (isQueueLoopModeEnabled.isTrue && isShuffleModeEnabled.isFalse) {
      toggleQueueLoopMode();
    }
    return !playByIndexHardFailed(result);
  }

  MediaItem? _resolveRiffWaveSeed() {
    MediaItem? dailyMixSeed;
    if (Get.isRegistered<DiscoveryService>()) {
      final mixes = Get.find<DiscoveryService>().dailyMixes;
      if (mixes.isNotEmpty && mixes.first.tracks.isNotEmpty) {
        try {
          dailyMixSeed = MediaItemBuilder.fromJson(mixes.first.tracks.first);
        } catch (_) {}
      }
    }

    MediaItem? quickPick;
    if (Get.isRegistered<HomeScreenController>()) {
      final qp = Get.find<HomeScreenController>().quickPicks.value.songList;
      if (qp.isNotEmpty) quickPick = qp.first;
    }

    final recentId = _prefs.get('recentSongId');
    // Home Wave is taste-first; don't seed from whatever is already playing.
    return RiffWave.resolveSeed(
      currentSong: currentSong.value,
      dailyMixSeed: dailyMixSeed,
      quickPick: quickPick,
      mostRecent: StatsService.mostRecentSong(),
      recentSongId: recentId is String ? recentId : null,
      preferTasteSeed: true,
    );
  }

  /// Fetches the next radio batch, one request at a time. A failed fetch
  /// (offline, YouTube Music error) is logged rather than thrown, so the
  /// caller falls through to its "nothing more to play" handling instead
  /// of the error escaping a stream listener or a skip.
  Future<void> _fetchRadioContinuation() async {
    if (_radioContinuationInFlight) return;
    _radioContinuationInFlight = true;
    try {
      await _addRadioContinuation(radioInitiatorItem);
    } catch (e) {
      printERROR('Radio continuation failed: $e');
    } finally {
      _radioContinuationInFlight = false;
    }
  }

  Future<void> _addRadioContinuation(dynamic item) async {
    final isSong = item.runtimeType.toString() == "MediaItem";
    // Prefer smart radio pipeline when discovery is available.
    if (Get.isRegistered<DiscoveryService>() && isSong) {
      try {
        final disc = Get.find<DiscoveryService>();
        final batch = await disc.smartRadioBatch(
          item as MediaItem,
          sessionHistory: List<MediaItem>.from(currentQueue),
          limit: 24,
        );
        if (batch.isNotEmpty) {
          await enqueueSongList(batch);
          return;
        }
      } catch (_) {
        // Fall through to raw YTM radio.
      }
    }
    final content = await _musicServices.getWatchPlaylist(
        videoId: isSong ? item.id : "",
        radio: true,
        limit: 24,
        playlistId: isSong ? null : item,
        additionalParamsNext: radioContinuationParam);
    radioContinuationParam = content['additionalParamsForNext'];
    final tracks = List<MediaItem>.from(content['tracks']);
    final tagged = Get.isRegistered<DiscoveryService>()
        ? DiscoveryService.tagAll(tracks, DiscoverySource.radio)
        : tracks;
    await enqueueSongList(tagged);
  }

  ///enqueueSong   append a song to current queue
  ///if current queue is empty, push the song into Queue and play that song
  Future<bool> enqueueSong(MediaItem mediaItem) async {
    if (currentQueue.isEmpty) {
      return playPlayListSong([mediaItem], 0);
    }
    if (!canMutateQueue(_audioReady)) return false;
    if (isAlreadyQueued(
      songId: mediaItem.id,
      queueIds: currentQueue.map((e) => e.id),
    )) {
      return true;
    }
    _audioHandler
        .addQueueItem(ensureDiscoverySource(mediaItem, DiscoverySource.queue));
    return true;
  }

  ///enqueueSongList method add song List to current queue
  Future<bool> enqueueSongList(List<MediaItem> mediaItems) async {
    if (mediaItems.isEmpty) return false;
    if (currentQueue.isEmpty) {
      final keepRadio = shouldKeepRadioWhenEnqueueing(
        radioOn: isRadioModeOn,
        queueEmpty: true,
      );
      final initiator = radioInitiatorItem;
      final started = await playPlayListSong(mediaItems, 0);
      if (keepRadio) {
        isRadioModeOn = true;
        radioInitiatorItem = initiator;
      }
      return started;
    }
    if (!canMutateQueue(_audioReady)) return false;
    final queuedIds = currentQueue.map((e) => e.id).toSet();
    final listToEnqueue = <MediaItem>[];
    for (MediaItem item in mediaItems) {
      if (!queuedIds.contains(item.id)) {
        listToEnqueue.add(item);
        queuedIds.add(item.id);
      }
    }
    if (listToEnqueue.isEmpty) return true;
    _audioHandler.addQueueItems(
        ensureDiscoverySources(listToEnqueue, DiscoverySource.queue));
    return true;
  }

  /// Android Auto "play": [songId] with the list it was browsed in as the
  /// queue.
  @visibleForTesting
  Future<void> playViaAndroidAuto(String songId, String? libraryId) async {
    if (libraryId == null) {
      printERROR('Android Auto play: no list for $songId');
      return;
    }
    // Lists built for the car, not stored in a box named after them:
    // podcast lists (Continue listening, a followed show; from the browse
    // cache, the long-form queue window keeps them small) and discovery
    // mixes / Fresh finds (read from riff_mixes).
    if (MediaLibrary.isBuiltList(libraryId)) {
      final list = MediaLibrary.autoPodcastLists[libraryId] ??
          await MediaLibrary().getByRootId(libraryId);
      if (list.isEmpty) return;
      final i = list.indexWhere((e) => e.id == songId);
      await playPlayListSong(list, i < 0 ? 0 : i,
          source: DiscoverySource.androidAuto);
      return;
    }
    final box = await Hive.openBox(libraryId);
    List<MediaItem> songList = [];
    final songJson = box.values.toList();
    int songIndex = 0;
    for (int i = 0; i < box.length; i++) {
      final song = MediaItemBuilder.fromJson(songJson[i]);
      if (song.id == songId) {
        songIndex = i;
      }
      songList.add(song);
    }
    await playPlayListSong(
      songList,
      songIndex,
      source: DiscoverySource.androidAuto,
    );
    // Shared box (Hive hands every caller the same instance): never close
    // it here, or the player and other screens using it fail mid-write.
  }

  /// "Play … on Riff" (Android Auto, the Assistant): what
  /// [MediaLibrary.voiceSearchList] finds, from the top. With nothing asked
  /// for and something in the queue, that plays on instead.
  Future<void> playFromVoiceSearch(String query) async {
    if (query.trim().isEmpty && currentQueue.isNotEmpty) {
      play();
      return;
    }
    final list = await MediaLibrary().voiceSearchList(query);
    if (list.isEmpty) return;
    await playPlayListSong(list, 0,
        playfrom: PlaylingFrom(
            type: PlaylingFromType.SELECTION,
            name: query.trim().isEmpty ? 'favorites'.tr : query.trim()),
        source: DiscoverySource.androidAuto);
  }

  /// Insert [songs] after the current track, preserving list order.
  Future<bool> playNextList(List<MediaItem> songs) async {
    if (songs.isEmpty) return false;
    if (currentQueue.isEmpty) {
      return playPlayListSong(songs, 0);
    }
    var inserted = false;
    for (final song in playNextBatchOrder(songs)) {
      if (await playNext(song)) inserted = true;
    }
    return inserted;
  }

  /// Insert [song] after the current track. Returns false when it is already
  /// current or already next so callers can skip the "play next" snackbar.
  Future<bool> playNext(MediaItem song) async {
    if (currentQueue.isEmpty) {
      return enqueueSong(song);
    }
    if (!_audioReady) return false;
    if (isPlayNextNoOp(
      songId: song.id,
      queueIds: currentQueue.map((e) => e.id).toList(),
      currentIndex: currentSongIndex.value,
    )) {
      return false;
    }
    int index = -1;
    for (int i = 0; i < currentQueue.length; i++) {
      if (song.id == (currentQueue[i]).id) {
        index = i;
        break;
      }
    }
    final currentIndx = currentSongIndex.value;
    if (index != -1) {
      onReorder(index, currentSongIndex.value + 1);
    } else {
      if (currentIndx == currentQueue.length - 1) {
        return enqueueSong(song);
      }
      _audioHandler.customAction("addPlayNextItem", {
        "mediaItem": ensureDiscoverySource(song, DiscoverySource.queue),
      });
    }
    return true;
  }

  bool _extendingRadio = false;

  /// A song after the one playing that may play (an explicit one doesn't
  /// while explicit content is off, nor offline one that needs a
  /// connection).
  bool get _songAfterCurrent =>
      currentQueue.skip(currentSongIndex.value + 1).any((song) =>
          !ExplicitContent.blocks(song) && !OfflinePlayback.blocks(song));

  /// Last track ended while radio/Wave is on — fetch the next batch and play.
  /// [quiet]: nothing to play on isn't reported (Autoplay's first batch).
  Future<bool> extendRadioThenPlayNext({bool quiet = false}) async {
    if (_extendingRadio || !isRadioModeOn) return false;
    _extendingRadio = true;
    try {
      if (_songAfterCurrent) {
        return next();
      }
      if (radioInitiatorItem == null) {
        if (!quiet) notifyPlayError('radioContinuationFailed');
        return false;
      }
      await _fetchRadioContinuation();
      if (_songAfterCurrent) {
        return next();
      }
      if (!quiet) notifyPlayError('radioContinuationFailed');
      return false;
    } finally {
      _extendingRadio = false;
    }
  }

  /// Whether next goes on past the last song: radio is on, or Autoplay
  /// starts it from the song playing. Reads [MusicAutoplay.enabled], so an
  /// Obx using it follows the switch.
  bool get playsOnPastEnd =>
      isRadioModeOn || MusicAutoplay.after(currentSong.value);

  /// The queue ran out: with Autoplay on, radio from its last song plays on
  /// (Spotify, YouTube Music, Apple Music) and goes on as radio does. False
  /// when it's off or nothing came (offline): the queue ends as before.
  Future<bool> autoplayAfterQueue() async {
    final last = currentSong.value;
    if (isRadioModeOn || !MusicAutoplay.after(last)) return false;
    radioInitiatorItem = last;
    radioContinuationParam = null;
    isRadioModeOn = true;
    if (await extendRadioThenPlayNext(quiet: true)) {
      playinfrom.value = PlaylingFrom(
          type: PlaylingFromType.SELECTION, name: 'autoplayShort'.tr);
      // The songs it adds aren't a playlist Mix's: no Mix transitions.
      if (Get.isRegistered<PlaylistMixService>()) {
        Get.find<PlaylistMixService>().deactivatePlayback();
      }
      return true;
    }
    isRadioModeOn = false;
    radioInitiatorItem = null;
    return false;
  }

  void _playerPanelCheck({bool restoreSession = false}) {
    final isWideScreen = Get.size.width > 800;
    final autoOpenPlayer = _prefs.get("autoOpenPlayer") ?? true;
    if ((!isWideScreen && autoOpenPlayer && playerPanelController.isAttached) &&
        !restoreSession) {
      playerPanelController.open();
    }

    if (initFlagForPlayer) {
      final miniPlayerHeight = isWideScreen ? 105.0 : 75.0;
      playerPanelMinHeight.value =
          miniPlayerHeight + Get.mediaQuery.viewPadding.bottom;
      initFlagForPlayer = false;
    }
  }

  bool removeFromQueue(MediaItem song) {
    if (!canMutateQueue(_audioReady)) return false;
    _audioHandler.removeQueueItem(song);
    return true;
  }

  void clearQueue() {
    if (!_audioReady) return;
    _audioHandler.customAction("clearQueue");
  }

  /// Removes [song] from the queue and returns how to put it back in the
  /// same place (null when nothing was removed).
  Future<VoidCallback?> removeFromQueueUndoable(MediaItem song) async {
    if (!canMutateQueue(_audioReady)) return null;
    final where = await _audioHandler.customAction(
        'removeQueueItemUndoable', {'mediaItem': song});
    if (where is! Map) return null;
    return () {
      if (!_audioReady) return;
      _audioHandler.customAction('restoreQueueItem', {
        'mediaItem': song,
        'index': where['index'],
        'shuffleIndex': where['shuffleIndex'],
      });
    };
  }

  /// Clears the queue down to the playing song and returns how to bring
  /// the rest back (null when there was nothing else to clear). Undo only
  /// applies while the same song is still playing.
  Future<VoidCallback?> clearQueueUndoable() async {
    if (!_audioReady) return null;
    final before = currentQueue.toList();
    final playing = currentSong.value;
    await _audioHandler.customAction("clearQueue");
    if (playing == null || before.length <= 1) return null;
    return () {
      if (!_audioReady || currentSong.value?.id != playing.id) return;
      _audioHandler.customAction(
          'restoreQueue', {'queue': before, 'currentId': playing.id});
    };
  }

  void shuffleQueue() {
    if (!_audioReady) return;
    _audioHandler.customAction("shuffleQueue");
  }

  Future<void> toggleShuffleMode() async {
    if (!_audioReady) return;
    final shuffleModeEnabled = isShuffleModeEnabled.value;
    shuffleModeEnabled
        ? _audioHandler.setShuffleMode(AudioServiceShuffleMode.none)
        : _audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
    isShuffleModeEnabled.value = !shuffleModeEnabled;
    await _prefs.put("isShuffleModeEnabled", !shuffleModeEnabled);
    // restrict queue loop mode when shuffle mode is enabled
    if (isShuffleModeEnabled.isTrue && isQueueLoopModeEnabled.isFalse) {
      isQueueLoopModeEnabled.value = true;
    } else if (isShuffleModeEnabled.isFalse) {
      isQueueLoopModeEnabled.value =
          _prefs.get("queueLoopModeEnabled", defaultValue: false);
    }
  }

  void onReorder(int oldIndex, int newIndex) {
    if (!_audioReady) return;
    _audioHandler.customAction(
        "reorderQueue", {"oldIndex": oldIndex, "newIndex": newIndex});
  }

  /// True while video mode's mpv engine owns playback — the transport
  /// (play/pause/seek) is routed to it instead of the audio pipeline.
  bool get _videoModeActive =>
      Get.isRegistered<VideoModeController>() &&
      Get.find<VideoModeController>().isActive.value;

  void play() {
    if (!_audioReady) return;
    if (_videoModeActive) {
      final vm = Get.find<VideoModeController>();
      if (!vm.isVideoPlaying.value) vm.playPauseVideo();
      return;
    }
    final h = _tagged;
    h != null ? h.playFrom(PlaybackCommandSource.user) : _audioHandler.play();
  }

  void pause({PlaybackCommandSource source = PlaybackCommandSource.user}) {
    if (!_audioReady) return;
    if (_videoModeActive) {
      final vm = Get.find<VideoModeController>();
      if (vm.isVideoPlaying.value) vm.playPauseVideo();
      return;
    }
    final h = _tagged;
    h != null ? h.pauseFrom(source) : _audioHandler.pause();
  }

  void playPause() {
    if (initFlagForPlayer) return;
    if (!_audioReady) return;
    if (_videoModeActive) {
      Get.find<VideoModeController>().playPauseVideo();
      return;
    }
    final wasPlaying = _audioHandler.playbackState.value.playing;
    wasPlaying ? pause() : play();
    // for gesture player
    if (Get.find<SettingsScreenController>().playerUi.value == 1) {
      gesturePlayerVisibleState.value = wasPlaying ? 1 : 0;
      gesturePlayerStateAnimationController?.reset();
      gesturePlayerStateAnimationController?.forward();
    }
  }

  /// Video mode owns a paused audio pipeline — skip must hand off first.
  Future<bool> _handoffVideoThen(Future<bool> Function() action) async {
    if (shouldHandoffVideoBeforeSkip(_videoModeActive)) {
      await Get.find<VideoModeController>().disable(resume: false);
    }
    return action();
  }

  /// [restart] false skips the "restart when past 3 s" rule and always goes
  /// to the previous track (the mini player's swipe).
  Future<bool> prev({bool restart = true}) async {
    if (!_audioReady) return false;
    return _handoffVideoThen(() async {
      final result = await _audioHandler.customAction(
          'skipToPrevious', {'source': 'user', if (!restart) 'restart': false});
      return playByIndexDidStart(result);
    });
  }

  Future<bool> next() async {
    if (!_audioReady) return false;
    return _handoffVideoThen(() async {
      final result = await _audioHandler
          .customAction('skipToNext', {'source': 'user'});
      return playByIndexDidStart(result);
    });
  }

  void seek(Duration position,
      {PlaybackCommandSource source = PlaybackCommandSource.user}) {
    if (_videoModeActive) {
      Get.find<VideoModeController>().seekVideo(position);
      return;
    }
    if (!_audioReady) return;
    final h = _tagged;
    h != null ? h.seekFrom(position, source) : _audioHandler.seek(position);
  }

  /// True when the currently playing item is a podcast episode (from the
  /// Podcasts section) — drives podcast-only chrome (shownotes, autoplay).
  bool get isCurrentSongPodcast {
    final s = currentSong.value;
    if (s == null) return false;
    return s.isPodcastEpisode;
  }

  /// True for audiobook chapters (Audiobookshelf abs_ and free lv_ ids).
  bool get isCurrentSongAudiobook {
    final s = currentSong.value;
    if (s == null) return false;
    return s.isAudiobook;
  }

  /// Podcast OR audiobook — ±skip / speed transport (not podcast-only tools).
  bool get usesLongFormTransport =>
      isCurrentSongPodcast || isCurrentSongAudiobook;

  /// True when the current item can show the in-player 16:9 video surface
  /// (music videos + YouTube-sourced podcast episodes).
  bool get isCurrentSongVideo {
    final s = currentSong.value;
    if (s == null) return false;
    return s.canShowPlayerVideo;
  }

  /// Seek by a relative offset (podcast ±skip), clamped to [0, total].
  void seekBy(Duration offset) {
    final status = progressBarStatus.value;
    var target = status.current + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (status.total > Duration.zero && target > status.total) {
      target = status.total;
    }
    seek(target);
  }

  void seekByIndex(int index) {
    if (!_audioReady) return;
    // An intentional re-tap of the row that is already playing is a genuine
    // new play, so let it through the duplicate gate.
    _playLogGate.reset();
    _audioHandler.customAction("playByIndex", {"index": index});
  }

  void toggleSkipSilence(bool enable) {
    _audioHandler.customAction("toggleSkipSilence", {"enable": enable});
  }

  /// Music's speed and pitch from Settings: a podcast episode or audiobook
  /// playing now keeps its own speed, so only the pitch reaches it.
  void setMusicSpeedAndPitch({required double speed, required double pitch}) {
    setSpeedAndPitch(
        speed: isCurrentSongPodcast
            ? currentPodcastProfile.speed
            : isCurrentSongAudiobook
                ? AudiobookPlayback.speed
                : speed,
        pitch: pitch);
  }

  void setSpeedAndPitch({required double speed, required double pitch}) {
    _audioHandler
        .customAction("setSpeedAndPitch", {"speed": speed, "pitch": pitch});
    if (_videoModeActive) {
      Get.find<VideoModeController>().setVideoSpeed(speed);
    }
  }

  /// Re-applies the full audio-effect chain from persisted settings.
  void applyAudioFx() {
    _audioHandler.customAction("setAudioFx");
  }

  void toggleLoudnessNormalization(bool enable) {
    _audioHandler
        .customAction("toggleLoudnessNormalization", {"enable": enable});
  }

  Future<void> toggleLoopMode() async {
    isLoopModeEnabled.isFalse
        ? _audioHandler.setRepeatMode(AudioServiceRepeatMode.one)
        : _audioHandler.setRepeatMode(AudioServiceRepeatMode.none);
    isLoopModeEnabled.value = !isLoopModeEnabled.value;
    await _prefs.put("isLoopModeEnabled", isLoopModeEnabled.value);
  }

  /// Spotify-style repeat state: 0 = off, 1 = repeat all (queue), 2 = repeat
  /// one. Repeat-one dominates the queue loop in the handler.
  int get repeatState =>
      isLoopModeEnabled.value ? 2 : (isQueueLoopModeEnabled.value ? 1 : 0);

  /// Cycle the repeat button: off → repeat all → repeat one → off.
  Future<void> cycleRepeatMode() async {
    switch (repeatState) {
      case 0: // off → all
        await toggleQueueLoopMode(showMessage: false);
        break;
      case 1: // all → one
        if (isLoopModeEnabled.isFalse) await toggleLoopMode();
        break;
      default: // one → off
        if (isLoopModeEnabled.isTrue) await toggleLoopMode();
        if (isQueueLoopModeEnabled.isTrue) {
          await toggleQueueLoopMode(showMessage: false);
        }
    }
  }

  Future<void> toggleQueueLoopMode({bool showMessage = true}) async {
    if (isShuffleModeEnabled.isTrue && isQueueLoopModeEnabled.isTrue) {
      if (!showMessage) return;
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "queueLoopNotDisMsg1".tr,
          size: SanckBarSize.BIG, duration: const Duration(seconds: 2)));
      return;
    }

    if (isRadioModeOn && isQueueLoopModeEnabled.isFalse) {
      if (!showMessage) return;
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "queueLoopNotDisMsg2".tr,
          size: SanckBarSize.BIG, duration: const Duration(seconds: 2)));
      return;
    }

    isQueueLoopModeEnabled.value = !isQueueLoopModeEnabled.value;
    await _audioHandler.customAction(
        "toggleQueueLoopMode", {"enable": isQueueLoopModeEnabled.value});
    await _prefs.put("queueLoopModeEnabled", isQueueLoopModeEnabled.value);
  }

  Future<void> setVolume(int value) async {
    _audioHandler.customAction("setVolume", {"value": value});
    volume.value = value;
    await _prefs.put("volume", value);
  }

  Future<void> mute() async {
    int? vol;
    if (volume.value != 0) {
      vol = 0;
    } else {
      vol = await _prefs.get("volume", defaultValue: 10);
      if (vol == 0) {
        vol = 10;
        await _prefs.put("volume", vol);
      }
    }
    _audioHandler.customAction("setVolume", {"value": vol!});
    volume.value = vol;
  }

  String? _favPersistSongId;

  Future<void> _checkFav() async {
    final song = currentSong.value;
    if (song == null) return;
    if (shouldKeepOptimisticFav(
      currentSongId: song.id,
      persistSongId: _favPersistSongId,
    )) {
      return;
    }
    final box = HiveBoxes.favSync();
    if (box != null) {
      isCurrentSongFav.value = box.containsKey(song.id);
    } else {
      isCurrentSongFav.value = (await HiveBoxes.fav()).containsKey(song.id);
    }
    _reportLikeToMediaSession(song.id, isCurrentSongFav.value);
  }

  Future<void> toggleFavourite() async {
    final currMediaItem = currentSong.value;
    if (currMediaItem == null) return;
    await toggleFavouriteFor(currMediaItem);
  }

  /// Like/unlike [song] in LIBFAV. Used by the now-playing heart and song rows.
  Future<void> toggleFavouriteFor(MediaItem song, {bool? adding}) async {
    final isCurrent = currentSong.value?.id == song.id;
    final currentlyFav =
        isCurrent ? isCurrentSongFav.isTrue : HiveBoxes.favContains(song.id);
    final nextAdding = adding ?? !currentlyFav;
    if (isCurrent) {
      isCurrentSongFav.value = nextAdding;
      _favPersistSongId = song.id;
      _reportLikeToMediaSession(song.id, nextAdding);
    }
    unawaited(_persistFavourite(song, nextAdding).whenComplete(() {
      if (_favPersistSongId == song.id) _favPersistSongId = null;
    }));
    if (Get.isRegistered<DiscoveryService>()) {
      Get.find<DiscoveryService>().onFavorite(song, add: nextAdding);
    }
    // Mirror to Spotify's Liked Songs when like sync is on.
    unawaited(SpotifyLikeSync.onFavorite(song, add: nextAdding));
    // And to YouTube Music's likes, when kept in step.
    unawaited(YtLikeSync.onFavorite(song, add: nextAdding));
    if (nextAdding &&
        Get.find<SettingsScreenController>()
            .autoDownloadFavoriteSongEnabled
            .isTrue) {
      Get.find<Downloader>().download(song);
    }
  }

  /// Keeps the heart on the notification / lock screen in step with the
  /// app (the save itself happens in the background).
  void _reportLikeToMediaSession(String songId, bool liked) {
    if (!_audioReady) return;
    _audioHandler.customAction('setLiked', {'id': songId, 'liked': liked});
  }

  Future<void> _persistFavourite(MediaItem currMediaItem, bool adding) async {
    final box = await HiveBoxes.fav();
    adding
        ? box.put(currMediaItem.id, MediaItemBuilder.toJson(currMediaItem))
        : box.delete(currMediaItem.id);
    try {
      final playlistController = Get.find<PlaylistScreenController>(
          tag: const Key("LIBFAV").hashCode.toString());
      adding
          ? playlistController.addNRemoveItemsinList(currMediaItem,
              action: 'add', index: 0)
          : playlistController.addNRemoveItemsinList(currMediaItem,
              action: 'remove');
      // ignore: empty_catches
    } catch (e) {}
  }

  /// Insert ~5 similar tracks after the current song (sideways exploration).
  Future<bool> moreLikeThisPlayNext([MediaItem? seed]) async {
    final song = seed ?? currentSong.value;
    if (song == null || !Get.isRegistered<DiscoveryService>()) {
      _snackQueueResult('operationFailed');
      return false;
    }
    final list =
        await Get.find<DiscoveryService>().moreLikeThisPlayNext(song, limit: 5);
    if (list.isEmpty) {
      _snackQueueResult('noSimilarSongs');
      return false;
    }
    var inserted = false;
    for (final s in list.reversed) {
      if (await playNext(s)) inserted = true;
    }
    _snackQueueResult(inserted ? 'moreLikeThisAdded' : 'operationFailed');
    return inserted;
  }

  void _snackQueueResult(String key) {
    final context = Get.context;
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(snackbar(
      context,
      key.tr,
      size: SanckBarSize.MEDIUM,
    ));
  }

  // ignore: prefer_typing_uninitialized_variables
  var recentItem;

  /// This function is used to add a mediaItem/Song to Recently played playlist
  Future<void> _addToRP(MediaItem mediaItem) async {
    if (recentItem != mediaItem) {
      final box = await HiveBoxes.open(HiveBoxes.libRp);
      String? removedSongId;
      if (box.keys.length >= recentlyPlayedMax) {
        removedSongId = box.getAt(0)['videoId'];
        box.deleteAt(0);
      }
      final valuesCopy = box.values.toList();
      for (int i = valuesCopy.length - 1; i >= 0; i--) {
        if (valuesCopy[i]['videoId'] == mediaItem.id) {
          box.deleteAt(i);
        }
      }
      // With when, for its day in the list.
      box.add(recentlyPlayedEntry(mediaItem, DateTime.now()));
      try {
        final playlistController = Get.find<PlaylistScreenController>(
            tag: const Key("LIBRP").hashCode.toString());
        if (removedSongId != null) {
          playlistController.songList
              .removeWhere((element) => element.id == removedSongId);
        }
        // removes current duplicate item from list
        playlistController.songList
            .removeWhere((element) => element.id == mediaItem.id);
        // adds current item to list
        playlistController.addNRemoveItemsinList(mediaItem,
            action: 'add', index: 0);

        // ignore: empty_catches
      } catch (e) {}
    }
    recentItem = mediaItem;
  }

  Future<void> showLyrics() async {
    showLyricsflag.value = !showLyricsflag.value;
    if (showLyricsflag.value) await _loadLyrics();
  }

  /// Fetches the current song's lyrics without opening them, for the lyric
  /// line under the title in the full player.
  Future<void> prefetchLyrics() => _loadLyrics();

  /// One lookup per song: a prefetch and a tap on lyrics share it.
  Future<void>? _lyricsLoad;
  String? _lyricsLoadId;

  Future<void> _loadLyrics() {
    final song = currentSong.value;
    // Missing only for want of a connection: not the song's last word.
    if (song == null ||
        (lyrics['offline'] != true &&
            (lyrics["synced"].isNotEmpty ||
                lyrics['plainLyrics'].isNotEmpty))) {
      return Future.value();
    }
    if (_lyricsLoadId == song.id && _lyricsLoad != null) return _lyricsLoad!;
    _lyricsLoadId = song.id;
    return _lyricsLoad = _fetchLyrics(song).whenComplete(() {
      if (_lyricsLoadId == song.id) {
        _lyricsLoad = null;
        _lyricsLoadId = null;
      }
    });
  }

  Future<void> _fetchLyrics(MediaItem song) async {
    isLyricsLoading.value = true;
    // A skip during the (sometimes slow) lookups must not put this
    // song's lyrics on the next one.
    bool stillCurrent() => currentSong.value?.id == song.id;
    Map<String, dynamic> result;
    try {
      final Map<String, dynamic>? lyricsR =
          await SyncedLyricsService.getSyncedLyrics(
              song, progressBarStatus.value.total.inSeconds);
      if (lyricsR != null) {
        result = lyricsR;
      } else {
        if (!stillCurrent()) return;
        // Kept once fetched, so they show offline too.
        final plain = await SyncedLyricsService.plainLyrics(
            song.id, () => SyncedLyricsService.youTubeLyrics(song.id));
        result = {"synced": "", "plainLyrics": plain ?? "NA"};
      }
    } catch (e) {
      result = {"synced": "", "plainLyrics": "NA"};
    }
    if (!stillCurrent()) return;
    // None found with no connection: that's why (the lyrics say so, and
    // are looked up again once it's back).
    if (lyricsMissing(result) && OfflinePlayback.offline.value) {
      result = {...result, 'offline': true};
    }
    lyrics.value = result;
    isLyricsLoading.value = false;
  }

  /// Search lyrics' pick for [song]: shown now when it's playing.
  void useLyrics(MediaItem song, Map<String, dynamic> picked) {
    if (currentSong.value?.id != song.id) return;
    lyrics.value = Map<String, dynamic>.from(picked);
    isLyricsLoading.value = false;
    if (showLyricsflag.isFalse) showLyricsflag.value = true;
  }

  void changeLyricsMode(int? val) {
    if (val == null) return;
    _prefs.put("lyricsMode", val);
    lyricsMode.value = val;
  }

  void sleepEndOfSong() {
    isSleepTimerActive.value = true;
    isSleepEndOfSongActive.value = true;
  }

  /// Podcasts with chapters: sleep when the chapter playing now ends (the
  /// end of the episode in the last chapter).
  void sleepEndOfChapter() {
    final pos = progressBarStatus.value.current;
    final current = _chapterAt(pos.inMilliseconds / 1000.0);
    _sleepChapterEnd = current == null ? null : _endOfChapter(current);
    isSleepTimerActive.value = true;
    isSleepEndOfChapterActive.value = true;
  }

  /// See [sleepFadeApplies].
  bool get _sleepFades => sleepFadeApplies(
        videoMode: _videoModeActive,
        mixActive: Get.isRegistered<PlaylistMixService>() &&
            Get.find<PlaylistMixService>().mixPlaybackActive.isTrue,
      );

  /// Once less than [sleepFadeLength] of wall-clock time is left, fade out
  /// and let the handler pause. True while a fade owns the stop.
  bool _maybeStartSleepFade(Duration remainingContent) {
    if (_sleepFadeStarted) return true;
    if (!_sleepFades) return false;
    final speed = _audioHandler.playbackState.value.speed;
    // Stop a second before the end so the episode can't roll on to the
    // next one while fading.
    final wall = wallClockRemaining(remainingContent, speed) -
        const Duration(seconds: 1);
    if (wall > sleepFadeLength || wall <= Duration.zero) return false;
    _startSleepFade(wall);
    return true;
  }

  void _startSleepFade(Duration length) {
    _sleepFadeStarted = true;
    _audioHandler.customAction(
        'sleepFadePause', {'ms': length.inMilliseconds}).then((done) {
      if (done == true && _sleepFadeStarted) {
        _sleepFadeStarted = false;
        cancelSleepTimer();
      }
    });
  }

  /// The length the running timer was started with, for [restartSleepTimer].
  int _sleepTimerLength = 0;

  bool startSleepTimer(int minutes) {
    if (!canArmSleepTimer(minutes)) return false;
    timerDuration = minutes * 60;
    _sleepTimerLength = timerDuration;
    isSleepTimerActive.value = true;
    if ((sleepTimer != null && !sleepTimer!.isActive) || sleepTimer == null) {
      sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final left = timerDuration - timer.tick;
        if (left > 0 &&
            !_sleepFadeStarted &&
            _sleepFades &&
            left <= sleepFadeLength.inSeconds) {
          _startSleepFade(Duration(seconds: left));
        }
        if (timer.tick == timerDuration) {
          sleepTimer?.cancel();
          // A fade pauses by itself.
          if (!_sleepFadeStarted) {
            pause(source: PlaybackCommandSource.sleepTimer);
          }
          isSleepTimerActive.value = false;
          timerDuration = 0;
          timerDurationLeft.value = 0;
        } else {
          timerDurationLeft.value = timerDuration - timer.tick;
        }
      });
    }
    return true;
  }

  void addFiveMinutes() {
    timerDuration += 300;
    _cancelSleepFade();
  }

  /// Back to the length the timer was started with (a shake, see
  /// [SleepShake]), fading in again if it had begun to fade out.
  void restartSleepTimer() {
    final timer = sleepTimer;
    if (timer == null || !timer.isActive || _sleepTimerLength <= 0) return;
    timerDuration = timer.tick + _sleepTimerLength;
    timerDurationLeft.value = _sleepTimerLength;
    _cancelSleepFade();
  }

  void _cancelSleepFade() {
    if (!_sleepFadeStarted) return;
    _sleepFadeStarted = false;
    _audioHandler.customAction('cancelSleepFade');
  }

  /// AntennaPod's automatic sleep timer: playback starting within its
  /// hours starts the sleep timer, none running, for the length picked
  /// last, and says so with Undo. [now] is for tests.
  @visibleForTesting
  void autoSleep({DateTime? now}) {
    final at = now ?? DateTime.now();
    if (!AutoSleepTimer.startsAt(at, timerRunning: isSleepTimerActive.isTrue)) {
      return;
    }
    final minutes = AutoSleepTimer.minutes;
    if (!startSleepTimer(minutes)) return;
    showUndoSnackbar(undoSnackbarTarget(null),
        'autoSleepTimerOn'.trParams({'time': formatSleepMinutes(minutes)}),
        onUndo: turnOffSleepTimer);
  }

  /// You turned the sleep timer off: the automatic one doesn't start
  /// again until its hours are over.
  void turnOffSleepTimer() {
    cancelSleepTimer();
    AutoSleepTimer.decline(DateTime.now());
  }

  void cancelSleepTimer() {
    _cancelSleepFade();
    if (isSleepEndOfSongActive.isTrue) {
      isSleepEndOfSongActive.value = false;
    }
    if (isSleepEndOfChapterActive.isTrue) {
      isSleepEndOfChapterActive.value = false;
    }
    _sleepChapterEnd = null;
    sleepTimer?.cancel();
    isSleepTimerActive.value = false;
    timerDuration = 0;
    timerDurationLeft.value = 0;
  }

  Future<void> openEqualizer() async {
    await _audioHandler.customAction("openEqualizer");
  }

  /// The phone's equalizer bands for Riff's equalizer (null: it has none,
  /// or nothing has played yet).
  Future<EqualizerLayout?> equalizerLayout() async {
    if (!_audioReady) return null;
    return EqualizerLayout.fromMap(
        await _audioHandler.customAction('equalizerLayout'));
  }

  /// Called from audio handler when audio is not playable, a stream resolve
  /// fails, or playback hits a runtime error. [isRetrying] shows a softer
  /// “retrying…” snackbar instead of a hard failure.
  void notifyPlayError(String message, {bool isRetrying = false}) {
    final text = isRetrying ? "streamRetrying".tr : _localizePlayError(message);
    if (!isRetrying) {
      playbackError.value = text;
    }
    final context = Get.context;
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(snackbar(
      context,
      text,
      size: SanckBarSize.MEDIUM,
      duration: Duration(seconds: isRetrying ? 2 : 3),
    ));
  }

  void clearPlaybackError() {
    if (playbackError.value != null) playbackError.value = null;
  }

  /// An explicit song didn't play: explicit content is off (Settings).
  void notifyExplicitOff() {
    final context = Get.context;
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, "explicitOffMsg".tr, size: SanckBarSize.MEDIUM));
  }

  /// A song that needs a connection didn't play: there's none.
  void notifyOffline() {
    final context = Get.context;
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, "offlineSongMsg".tr, size: SanckBarSize.MEDIUM));
  }

  /// Explicit content was turned off: an explicit song playing stops there
  /// and the next one that may play starts (paused, the next Play skips it).
  Future<void> skipIfExplicit() async {
    if (ExplicitContent.blocks(currentSong.value) &&
        buttonState.value == PlayButtonState.playing) {
      await next();
    }
  }

  /// Skip a dead stream and try the next queue item.
  Future<bool> skipFailedPlayback() async {
    final hasNext = currentQueue.length > currentSongIndex.value + 1;
    if (shouldRetryInsteadOfSkip(
      hasNext: hasNext,
      radioOn: isRadioModeOn,
    )) {
      return retryPlayback();
    }
    if (!canRetryOrSkipPlayback(
      audioReady: _audioReady,
      queueLength: currentQueue.length,
      index: currentSongIndex.value,
    )) {
      return false;
    }
    clearPlaybackError();
    return next();
  }

  /// Force a fresh stream URL for the current queue index.
  Future<bool> retryPlayback() async {
    await _waitForAudioHandler();
    if (!canRetryOrSkipPlayback(
      audioReady: _audioReady,
      queueLength: currentQueue.length,
      index: currentSongIndex.value,
    )) {
      return false;
    }
    clearPlaybackError();
    var posMs = progressBarStatus.value.current.inMilliseconds;
    if (posMs <= 0) {
      final id = currentSong.value?.id;
      if (id != null) {
        posMs = PodcastProgressService.positionMs(id) ?? 0;
      }
    }
    if (posMs <= 0 && _pendingResumeMs > 0) {
      posMs = _pendingResumeMs;
    }
    final result = await _audioHandler.customAction("playByIndex", {
      "index": currentSongIndex.value,
      "newUrl": true,
      if (posMs > 0) "position": posMs,
    });
    return !playByIndexHardFailed(result);
  }

  static String _localizePlayError(String message) {
    switch (message) {
      case "networkError":
        return "networkError".tr;
      case "songNotPlayable":
        return "songNotPlayable".tr;
      case "songRequiresPurchase":
      case "Song requires purchase":
        return "songRequiresPurchase".tr;
      case "songUnavailable":
      case "Song is unavailable":
        return "songUnavailable".tr;
      case "streamUnknownError":
      case "Unknown error occurred":
        return "streamUnknownError".tr;
      case "streamPlaybackFailed":
        return "streamPlaybackFailed".tr;
      case "streamLoadFailed":
        return "streamLoadFailed".tr;
      case "streamBotBlocked":
        return "streamBotBlocked".tr;
      case "radioContinuationFailed":
        return "radioContinuationFailed".tr;
      default:
        if (message.isEmpty) return "streamLoadFailed".tr;
        final lower = message.toLowerCase();
        if (lower.contains('network') || lower.contains('socket')) {
          return "networkError".tr;
        }
        if (lower.contains('unavailable')) return "songUnavailable".tr;
        if (lower.contains('purchase')) return "songRequiresPurchase".tr;
        if (lower.contains('bot') || lower.contains('sign in to confirm')) {
          return "streamBotBlocked".tr;
        }
        return message;
    }
  }

  /// GetX calls this on delete (it never calls [dispose] on a controller).
  /// The audio handler and its player outlive the controller, so playback
  /// is left alone; the panel's ScrollController belongs to the panel.
  @override
  void onClose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    for (final w in _workers) {
      w.dispose();
    }
    _workers.clear();
    if (Get.isRegistered<SmartQueueService>()) {
      Get.find<SmartQueueService>().detach(this);
    }
    // Before super.onClose: the ticker mixin asserts no ticker is active.
    gesturePlayerStateAnimationController?.dispose();
    gesturePlayerStateAnimationController = null;
    sleepTimer?.cancel();
    SleepShake.stop();
    _lyricsPrefetchTimer?.cancel();
    if (GetPlatform.isWindows) {
      Get.delete<WindowsAudioService>();
    }
    _setWakelock(false);
    playerPanelPosition.dispose();
    super.onClose();
  }
}

enum PlayButtonState { paused, playing, loading }

/// Whether a lyrics lookup's [result] has no lyrics at all.
bool lyricsMissing(Map<String, dynamic> result) =>
    result['plainLyrics'] == 'NA' &&
    '${result['synced'] ?? ''}'.isEmpty &&
    '${result['ttml'] ?? ''}'.isEmpty;
