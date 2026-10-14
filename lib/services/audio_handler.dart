import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';

import 'package:hive/hive.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';
// ignore: depend_on_referenced_packages
import 'package:rxdart/rxdart.dart';

import '/models/album.dart';
import '../models/playlist.dart';
import '/services/equalizer.dart';
import '/services/riff_equalizer.dart';
import '/services/youtube_stream_headers.dart';
import '/services/playlist_mix_service.dart';
import '/services/audiobookshelf_service.dart';
import '/services/cloud_music_service.dart';
import '/services/music_service.dart' show MusicServices;
import '/services/podcast_inbox_counts.dart';
import '/services/podcast_progress_service.dart';
import '/services/android_auto_paging.dart';
import '/services/playback_hardening.dart';
import '/services/podcast_service.dart';
import '/ui/widgets/podcast_play.dart' show podcastEpisodeToMediaItem;
import '/services/audiobook_playback.dart';
import '/services/podcast_playback_profile.dart';
import '/models/media_item_extras.dart';
import '/services/now_playing_controls.dart';
import '/services/queue_undo.dart';
import '/services/normalization_level.dart';
import '/services/shuffle_order.dart';
import '/services/song_fade.dart';
import '/services/stream_service.dart';
import '/services/network_kind.dart';
import '/ui/screens/Podcasts/podcast_queue_controller.dart';
import '/models/hm_streaming_data.dart';
import '/ui/player/player_controller.dart';
import '/ui/player/radio_continuation.dart';
import '/ui/player/video_mode_controller.dart';
import '/ui/screens/Search/search_play_top.dart' show songsFromSearchResult;
import '../ui/screens/Home/home_screen_controller.dart';
import '/services/background_task.dart';
import '/services/client_config_service.dart';
import '/services/permission_service.dart';
import '/services/play_by_index_skip.dart';
import '/services/play_runtime_error.dart';
import '/ui/player/video_handoff.dart';
import '../utils/helper.dart';
import '/models/media_Item_builder.dart';
import '/utils/hive_boxes.dart';
import '/utils/songs_url_cache.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '../ui/screens/Library/library_controller.dart';

Future<AudioHandler> initAudioService() async {
  // On Linux the MPRIS backend uses the channel name as the player identity
  // and the channel id in its D-Bus name, so media keys and desktop widgets
  // show "Riff". Android keeps its existing notification channel.
  final linux = GetPlatform.isLinux;
  return await AudioService.init(
    builder: () => MyAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationIcon: 'drawable/ic_stat_riff',
      androidNotificationChannelId:
          linux ? 'riff' : 'com.mycompany.myapp.audio',
      androidNotificationChannelName:
          linux ? 'Riff' : 'Harmony Music Notification',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // Android Auto shows its search button.
      androidBrowsableRootExtras: const {
        'android.media.browse.SEARCH_SUPPORTED': true,
      },
    ),
  );
}

const _e2eStreamUrl = String.fromEnvironment('RIFF_E2E_STREAM_URL');

class MyAudioHandler extends BaseAudioHandler with GetxServiceMixin {
  // ignore: prefer_typing_uninitialized_variables
  late final _cacheDir;
  Future<void> _cacheDirReady = Future.value();
  late AudioPlayer _player;
  late MediaLibrary _mediaLibrary;
  // ignore: prefer_typing_uninitialized_variables
  dynamic currentIndex;
  int currentShuffleIndex = 0;

  /// Bumped by every playByIndex; a request whose id is no longer current
  /// was superseded and must not touch the player.
  int _playRequestId = 0;

  /// In-flight stream lookups per song id, so the prefetch and the real
  /// play (or a double tap) share one resolve.
  final _urlInflight = <String, Future<HMStreamingData>>{};
  String? currentSongUrl;
  bool isPlayingUsingLockCachingSource = false;
  bool loopModeEnabled = false;
  bool queueLoopModeEnabled = false;
  bool shuffleModeEnabled = false;
  bool loudnessNormalizationEnabled = false;
  bool isSongLoading = true;
  double _baseVolume = 1.0;

  /// Podcast voice boost in mB while a podcast episode plays (null: the
  /// user's own volume boost applies, as for music).
  int? _podcastLoudnessMb;

  /// When the current podcast episode was paused, for smart resume.
  DateTime? _longFormPausedAt;

  /// Bumped to cancel a running sleep-timer fade.
  int _sleepFadeToken = 0;
  double? _sleepFadeRestoreVolume;

  /// Volume to restore when a muted podcast segment ends.
  double? _segmentMuteRestore;

  // ── Command sources and the playback watchdog ────────────────────────
  /// Inside a media-button press (headset, Bluetooth).
  int _mediaButtonDepth = 0;

  /// Last time Android Auto (or another browser) listed our library.
  DateTime? _lastAutoBrowseAt;
  bool _carMode = false;

  /// The last seek a person made (app, notification, Android Auto), and a
  /// counter bumped by each; automatic skips check both.
  SeekRecord? lastUserSeek;
  int userSeekSerial = 0;

  final _watchdog = PlaybackWatchdog();
  Timer? _watchdogTimer;
  int _watchdogTicks = 0;
  bool _mixTransitionInProgress = false;
  bool _startMutedForMix = false;

  /// Fade between songs: while it has the volume lowered, the level it
  /// plays at otherwise.
  double? _songFadeBase;

  /// The song fading in after the one before faded out, and over how long.
  String? _songFadeInId;
  int _songFadeInMs = 0;
  /// Song id we already near-end-prefetched, so the 45s listener fires once.
  String? _prefetchArmedForId;
  /// Song id we already EOF-advanced, so position ticks cannot double-skip.
  String? _eofArmedForId;
  bool _eofAdvanceInProgress = false;

  /// Auto URL-refresh budget after stream death (PLAY-1). Reset on song change
  /// or when playback reaches ready.
  String? _streamRetrySongId;
  int _streamRetryCount = 0;
  static const int _maxStreamUrlRetries = 2;
  bool _runtimeErrorInFlight = false;

  /// Consecutive playByIndex resolve failures. Reset when playback is ready
  /// so a later dead track can still skip once without looping the queue.
  int _consecutiveResolveFails = 0;
  static const int _maxConsecutiveResolveFails = 1;

  // list of shuffled queue songs ids
  List<String> shuffledQueue = [];

  final _playList =
      ConcatenatingAudioSource(children: [], useLazyPreparation: true);

  MyAudioHandler() {
    if (GetPlatform.isWindows || GetPlatform.isLinux) {
      JustAudioMediaKit.title = 'Riff';
      JustAudioMediaKit.protocolWhitelist = const ['http', 'https', 'file'];
    }
    _mediaLibrary = MediaLibrary();
    _player = AudioPlayer(
        audioLoadConfiguration: const AudioLoadConfiguration(
            androidLoadControl: AndroidLoadControl(
      minBufferDuration: Duration(seconds: 50),
      maxBufferDuration: Duration(seconds: 120),
      bufferForPlaybackDuration: Duration(milliseconds: 50),
      bufferForPlaybackAfterRebufferDuration: Duration(seconds: 2),
    )));
    _cacheDirReady = _createCacheDir();
    _addEmptyList();
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenToPlaybackForNextSong();
    final appPrefsBox = Hive.box("AppPrefs");
    _player
        .setSkipSilenceEnabled(appPrefsBox.get("skipSilenceEnabled") ?? false);
    _player.setSpeed((appPrefsBox.get("playbackSpeed") ?? 1.0).toDouble());
    _setPitch((appPrefsBox.get("playbackPitch") ?? 1.0).toDouble());
    loopModeEnabled = appPrefsBox.get("isLoopModeEnabled") ?? false;
    shuffleModeEnabled = appPrefsBox.get("isShuffleModeEnabled") ?? false;
    queueLoopModeEnabled =
        Hive.box("AppPrefs").get("queueLoopModeEnabled") ?? false;
    loudnessNormalizationEnabled =
        appPrefsBox.get("loudnessNormalizationEnabled") ?? false;
    _listenForDurationChanges();
    if (GetPlatform.isAndroid) {
      _listenSessionIdStream();
    }
    _listenForPodcastPauses();
    _listenForWatchdog();
  }

  /// Source of a command that came from outside the app (notification,
  /// lock screen, Android Auto, headset).
  PlaybackCommandSource _externalSource() => classifyExternalCommand(
        mediaButton: _mediaButtonDepth > 0,
        carMode: _carMode,
        lastBrowseAt: _lastAutoBrowseAt,
        now: DateTime.now(),
      );

  void _logCommand(String command, PlaybackCommandSource source,
      [String detail = '']) {
    if (!kDebugMode) return;
    printINFO('[transport] $command ← ${source.name}'
        '${detail.isEmpty ? '' : ' $detail'}');
  }

  Future<void> _refreshCarMode() async {
    if (!GetPlatform.isAndroid) return;
    try {
      _carMode = await _fxChannel.invokeMethod<bool>('isCarMode') ?? false;
    } catch (_) {
      _carMode = false;
    }
  }

  /// Headset / Bluetooth buttons arrive here; whatever they trigger is
  /// tagged [PlaybackCommandSource.system].
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    _mediaButtonDepth++;
    try {
      await super.click(button);
    } finally {
      _mediaButtonDepth--;
    }
  }

  // ── Watchdog ──────────────────────────────────────────────────────────

  /// Runs while the player or the session says something is playing (a
  /// Dart timer in the audio service's process, so it keeps going with the
  /// screen off).
  void _listenForWatchdog() {
    _player.playingStream.listen((_) => _syncWatchdogTimer());
    playbackState.listen((_) => _syncWatchdogTimer());
  }

  void _syncWatchdogTimer() {
    final wanted = _player.playing || playbackState.value.playing;
    if (wanted && _watchdogTimer == null) {
      _watchdog.reset();
      _watchdogTimer = Timer.periodic(
          const Duration(seconds: 2), (_) => _watchdogTick());
    } else if (!wanted && _watchdogTimer != null) {
      _watchdogTimer!.cancel();
      _watchdogTimer = null;
      _watchdog.reset();
    }
  }

  static WatchdogProcessing _watchdogProcessing(ProcessingState s) =>
      switch (s) {
        ProcessingState.idle => WatchdogProcessing.idle,
        ProcessingState.loading => WatchdogProcessing.loading,
        ProcessingState.buffering => WatchdogProcessing.buffering,
        ProcessingState.ready => WatchdogProcessing.ready,
        ProcessingState.completed => WatchdogProcessing.completed,
      };

  bool _watchdogBusy = false;

  Future<void> _watchdogTick() async {
    if (_watchdogBusy) return;
    _watchdogBusy = true;
    try {
      if (++_watchdogTicks % 5 == 0) unawaited(_refreshCarMode());
      final videoMode = Get.isRegistered<VideoModeController>() &&
          Get.find<VideoModeController>().isActive.value;
      final action = _watchdog.tick(WatchdogSample(
        nowMs: DateTime.now().millisecondsSinceEpoch,
        positionMs: _player.position.inMilliseconds,
        playerPlaying: _player.playing,
        processing: _watchdogProcessing(_player.processingState),
        sessionPlaying: playbackState.value.playing,
        busy: isSongLoading ||
            videoMode ||
            _mixTransitionInProgress ||
            _eofAdvanceInProgress ||
            _runtimeErrorInFlight ||
            _sleepFadeRestoreVolume != null ||
            // The UI shows a playback error; republishing would hide it.
            playbackState.value.processingState == AudioProcessingState.error,
      ));
      switch (action) {
        case WatchdogAction.none:
          break;
        case WatchdogAction.reseek:
          final at = _player.position;
          printWarning('Watchdog: stalled at ${at.inMilliseconds}ms, re-seeking');
          _logCommand('seek', PlaybackCommandSource.watchdog, 'stall');
          await _player.seek(at);
        case WatchdogAction.replay:
          printWarning('Watchdog: still stalled, pause + play');
          _logCommand('pause+play', PlaybackCommandSource.watchdog, 'stall');
          final at = _player.position;
          await _player.pause();
          await _player.seek(at);
          await _player.play();
        case WatchdogAction.giveUp:
          printERROR('Watchdog: playback stuck at '
              '${_player.position.inMilliseconds}ms, giving up until it moves');
        case WatchdogAction.republish:
          printWarning('Watchdog: session said playing='
              '${playbackState.value.playing}, player says '
              '${_player.playing}; resyncing');
          _publishPlaybackState();
      }
    } catch (e) {
      printERROR('Watchdog tick failed: $e');
    } finally {
      _watchdogBusy = false;
    }
  }

  // ── Automatic skips ───────────────────────────────────────────────────

  /// Step the volume from [from] to [to] over [length]. Stops early (and
  /// returns false) when [keepGoing] says so.
  Future<bool> _rampVolume(double from, double to, Duration length,
      {Duration step = const Duration(milliseconds: 40),
      bool Function()? keepGoing}) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < length) {
      if (keepGoing != null && !keepGoing()) return false;
      await _player.setVolume(volumeRamp(
          from: from, to: to, elapsed: watch.elapsed, length: length));
      await Future<void>.delayed(step);
    }
    if (keepGoing != null && !keepGoing()) return false;
    await _player.setVolume(to);
    return true;
  }

  /// Automatic segment skip (podcast segments, SponsorBlock): duck, seek
  /// to [target], fade back in. Called with the [seekSerial] seen when the
  /// skip was decided; if a person seeks meanwhile (app, notification,
  /// Android Auto) or the track changes, the skip is dropped and the
  /// volume put back. True when it skipped.
  Future<bool> autoSkipTo(Duration target,
      {required int seekSerial, required String? itemId}) async {
    bool valid() => autoSkipStillValid(
        seekSerialAtStart: seekSerial,
        seekSerialNow: userSeekSerial,
        itemAtStart: itemId,
        itemNow: mediaItem.value?.id);
    if (!valid()) return false;
    final base = _player.volume;
    final ducked = base * autoSkipDuckLevel;
    if (!await _rampVolume(base, ducked, autoSkipDuck, keepGoing: valid)) {
      await _player.setVolume(base);
      _logCommand('autoSkip', PlaybackCommandSource.autoSkip,
          'dropped: a person sought first');
      return false;
    }
    await seekFrom(target, PlaybackCommandSource.autoSkip);
    await _rampVolume(ducked, base, autoSkipFadeIn);
    return true;
  }

  /// Smart resume: remember when a podcast episode or audiobook stopped
  /// playing (any cause: pause button, notification, headset, audio
  /// focus); forget it once playback runs again.
  void _listenForPodcastPauses() {
    _player.playingStream.listen((playing) {
      if (playing) {
        _longFormPausedAt = null;
        return;
      }
      final item = mediaItem.value;
      if (item == null || !smartResumeApplies(item) || isSongLoading) return;
      if (_player.processingState == ProcessingState.completed) return;
      _longFormPausedAt ??= DateTime.now();
    });
  }

  /// Podcast playback profile (speed, trim silence, voice boost) for
  /// [item]; any other item gets music's own settings back, except that
  /// audiobooks keep their own speed.
  Future<void> _applyPlaybackProfile(MediaItem? item) async {
    try {
      if (item != null && item.isPodcastEpisode) {
        final p = PodcastPlaybackPrefs.forItem(item);
        await _player.setSpeed(p.speed);
        await _player
            .setSkipSilenceEnabled(GetPlatform.isAndroid && p.trimSilence);
        final boost = p.voiceBoost == PodcastVoiceBoost.off
            ? null
            : p.voiceBoost.loudnessMb;
        if (boost != _podcastLoudnessMb) {
          _podcastLoudnessMb = boost;
          if (GetPlatform.isAndroid) _applyAudioFx();
        }
      } else {
        final prefs = Hive.box("AppPrefs");
        await _player.setSpeed(item != null && item.isAudiobook
            ? AudiobookPlayback.speed
            : (prefs.get("playbackSpeed") ?? 1.0).toDouble());
        await _player
            .setSkipSilenceEnabled(prefs.get("skipSilenceEnabled") ?? false);
        if (_podcastLoudnessMb != null) {
          _podcastLoudnessMb = null;
          if (GetPlatform.isAndroid) _applyAudioFx();
        }
      }
    } catch (e) {
      printERROR('applyPlaybackProfile: $e');
    }
  }

  /// Notification / headset skip for podcast episodes (by the show's skip
  /// lengths) and audiobooks. Music keeps the handler default (nothing).
  Future<void> _longFormSkip(
      {required bool forward, required PlaybackCommandSource source}) async {
    final item = mediaItem.value;
    if (item == null) return;
    final int seconds;
    if (item.isPodcastEpisode) {
      final p = PodcastPlaybackPrefs.forItem(item);
      seconds = forward ? p.skipForwardSec : p.skipBackSec;
    } else if (item.isAudiobook) {
      seconds = forward
          ? AudiobookPlayback.skipForwardSec
          : AudiobookPlayback.skipBackSec;
    } else {
      return;
    }
    var target =
        _player.position + Duration(seconds: forward ? seconds : -seconds);
    final total = _player.duration;
    if (target.isNegative) target = Duration.zero;
    if (total != null && target > total) target = total;
    await seekFrom(target, source);
  }

  @override
  Future<void> fastForward() =>
      _longFormSkip(forward: true, source: _externalSource());

  @override
  Future<void> rewind() =>
      _longFormSkip(forward: false, source: _externalSource());

  Future<void> _createCacheDir() async {
    _cacheDir = (await getTemporaryDirectory()).path;
    if (!Directory("$_cacheDir/cachedSongs/").existsSync()) {
      Directory("$_cacheDir/cachedSongs/").createSync(recursive: true);
    }
  }

  void _addEmptyList() {
    try {
      _player.setAudioSource(_playList);
    } catch (r) {
      printERROR(r.toString());
    }
  }

  static const _fxChannel = MethodChannel('riff/newpipe');

  /// The desktop (mpv) player is created without pitch support, so a pitch
  /// change throws there; desktop keeps the original pitch instead.
  Future<void> _setPitch(double pitch) async {
    if (GetPlatform.isDesktop) return;
    await _player.setPitch(pitch);
  }

  void _listenSessionIdStream() {
    _player.androidAudioSessionIdStream.listen((int? id) {
      if (id != null) {
        EqualizerService.initAudioEffect(id);
        // Re-bind the whole effect chain to the new session.
        _applyAudioFx(id);
      }
    });
  }

  /// Pushes the full effect chain (bass, volume boost, reverb, virtualizer)
  /// to the native session from persisted settings.
  void _applyAudioFx([int? sessionId]) {
    final id = sessionId ?? _player.androidAudioSessionId;
    if (id == null) return;
    final box = Hive.box("AppPrefs");
    _fxChannel.invokeMethod('setAudioFx', {
      'sessionId': id,
      'bass': box.get("bassBoost") ?? 0,
      'loudnessMb': _effectiveLoudnessMb(box.get("volumeBoostMb")),
      'reverb': box.get("reverbPreset") ?? 0,
      'virtualizer': box.get("virtualizer") ?? 0,
      'eqEnabled': RiffEqualizer.enabled,
      'eqLevels': RiffEqualizer.levelsMb,
    });
  }

  /// The user's volume boost, raised to the podcast voice boost while a
  /// podcast episode with voice boost plays.
  int _effectiveLoudnessMb(Object? userMb) {
    final user = userMb is num ? userMb.toInt() : 0;
    final voice = _podcastLoudnessMb;
    if (voice == null) return user;
    return max(user, voice);
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      if (_player.processingState == ProcessingState.ready) {
        final id = mediaItem.value?.id;
        if (id != null) _resetStreamRetryBudget(songId: id);
        _consecutiveResolveFails = 0;
      }
      _publishPlaybackState();
    }, onError: (Object e, StackTrace st) async {
      if (e is PlayerException) {
        printERROR('Error code: ${e.code}');
        printERROR('Error message: ${e.message}');
      } else {
        printERROR('An error occurred: $e');
      }
      await _handleRuntimePlaybackError(e, position: _player.position);
    });
  }

  /// The app's last word on whether the playing song is liked (see
  /// [nowPlayingLiked]); set through the 'setLiked' custom action.
  String? _likedReportId;
  bool _likedReport = false;

  /// Media session state from the player's real state (notification,
  /// Android Auto, lock screen and the app's UI all read it).
  void _publishPlaybackState() {
      final playing = _player.playing;
      final item = mediaItem.value;
      final longForm =
          item != null && (item.isPodcastEpisode || item.isAudiobook);
      playbackState.add(playbackState.value.copyWith(
        // Podcast episodes and audiobooks: skip back / forward (rewind /
        // fastForward) by the show's lengths or the book's. Music keeps
        // previous / next, plus the like heart.
        controls: nowPlayingControls(
          longForm: longForm,
          playing: playing,
          canLike: item != null && !longForm,
          liked: nowPlayingLiked(
            currentId: item?.id,
            reportedId: _likedReportId,
            reportedLiked: _likedReport,
            stored: HiveBoxes.favContains,
          ),
          likeLabel: 'addToFavorites'.tr,
          unlikeLabel: 'removeFromFavorites'.tr,
        ),
        systemActions: const {
          MediaAction.seek,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: isSongLoading
            ? AudioProcessingState.loading
            : const {
                ProcessingState.idle: AudioProcessingState.idle,
                ProcessingState.loading: AudioProcessingState.loading,
                ProcessingState.buffering: AudioProcessingState.buffering,
                ProcessingState.ready: AudioProcessingState.ready,
                ProcessingState.completed: AudioProcessingState.completed,
              }[_player.processingState]!,
        repeatMode: const {
          LoopMode.off: AudioServiceRepeatMode.none,
          LoopMode.one: AudioServiceRepeatMode.one,
          LoopMode.all: AudioServiceRepeatMode.all,
        }[_player.loopMode]!,
        shuffleMode: (shuffleModeEnabled)
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: currentIndex,
      ));
  }

  String? _currentQueueSongId() {
    if (currentIndex is! int) return null;
    final i = currentIndex as int;
    if (i < 0 || i >= queue.value.length) return null;
    return queue.value[i].id;
  }

  /// Runtime just_audio failure after a URL was handed off (403, drop, decode).
  /// Returns true when playback was restarted or skip-to-next began.
  Future<bool> _handleRuntimePlaybackError(
    Object e, {
    required Duration position,
  }) async {
    if (_runtimeErrorInFlight) return false;
    _runtimeErrorInFlight = true;
    final songId = _currentQueueSongId();
    try {
      if (isPlayingUsingLockCachingSource &&
          isCacheConnectionClosedError(e)) {
        await _player.stop();
        await _player.seek(position, index: 0);
        await _player.play();
        return true;
      }

      if (shouldRefreshUrlOnRuntimeError(e) &&
          _canAutoRetryUrlRefresh(songId)) {
        await _player.stop();
        if (Get.isRegistered<PlayerController>()) {
          Get.find<PlayerController>()
              .notifyPlayError("streamRetrying", isRetrying: true);
        }
        final attempt = _streamRetryCount;
        if (attempt > 0) {
          await Future.delayed(
              Duration(milliseconds: attempt == 1 ? 800 : 2000));
        }
        _runtimeErrorInFlight = false;
        final result = await customAction("playByIndex", {
          'index': currentIndex,
          'newUrl': true,
          'position': position.inMilliseconds,
        });
        return !playByIndexHardFailed(result);
      }

      try {
        await _player.stop();
      } catch (_) {
        try {
          await _player.pause();
        } catch (_) {}
      }
      if (Get.isRegistered<PlayerController>()) {
        Get.find<PlayerController>().notifyPlayError("streamPlaybackFailed");
      }
      _consecutiveResolveFails++;
      final next = _getNextSongIndex();
      if (shouldSkipAfterUnresolvableTrack(
        consecutiveFails: _consecutiveResolveFails,
        maxConsecutiveFails: _maxConsecutiveResolveFails,
        currentIndex: currentIndex is int ? currentIndex as int : 0,
        nextIndex: next,
        loopOne: loopModeEnabled,
      )) {
        await skipToNextResult(source: PlaybackCommandSource.system);
        return true;
      }
      return false;
    } finally {
      _runtimeErrorInFlight = false;
    }
  }

  bool _canAutoRetryUrlRefresh(String? songId) {
    if (!canAutoRetryUrlRefresh(
      songId: songId,
      budgetSongId: _streamRetrySongId,
      retryCount: _streamRetryCount,
      maxRetries: _maxStreamUrlRetries,
    )) {
      return false;
    }
    if (_streamRetrySongId != songId) {
      _streamRetrySongId = songId;
      _streamRetryCount = 0;
    }
    _streamRetryCount++;
    return true;
  }

  void _resetStreamRetryBudget({String? songId}) {
    if (songId != null && songId != _streamRetrySongId) {
      _streamRetrySongId = songId;
    }
    _streamRetryCount = 0;
  }

  /// After generateNewUrl retry still fails: skip to next once when allowed.
  /// Returns true when skip-to-next was started, false when playback stopped.
  Future<bool> _onPlayByIndexUnresolvable({
    required String songId,
    required String errorMessage,
    required int errorCode,
  }) async {
    // The queue was replaced while the stream resolved: nothing to report,
    // but don't leave the session on "loading".
    if (isStalePlayByIndex(
        requestedSongId: songId, currentSongId: _currentQueueSongId())) {
      isSongLoading = false;
      return false;
    }
    _consecutiveResolveFails++;
    final next = _getNextSongIndex();
    if (shouldSkipAfterUnresolvableTrack(
      consecutiveFails: _consecutiveResolveFails,
      maxConsecutiveFails: _maxConsecutiveResolveFails,
      currentIndex: currentIndex as int,
      nextIndex: next,
      loopOne: loopModeEnabled,
    )) {
      printINFO(
          'playByIndex: track will not resolve, skipping to next (fail $_consecutiveResolveFails)');
      await skipToNextResult(source: PlaybackCommandSource.system);
      return true;
    }
    currentSongUrl = null;
    isSongLoading = false;
    if (Get.isRegistered<PlayerController>()) {
      Get.find<PlayerController>().notifyPlayError(errorMessage);
    }
    playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        errorCode: errorCode,
        errorMessage: errorMessage));
    return false;
  }

  void _listenToPlaybackForNextSong() {
    final playerDurationOffset = GetPlatform.isWindows
        ? 200
        : GetPlatform.isLinux
            ? 700
            : 0;
    _player.positionStream.listen((value) async {
      if (_player.duration == null || _player.duration?.inSeconds == 0) {
        return;
      }
      final durationMs = _player.duration!.inMilliseconds;
      final posMs = value.inMilliseconds;

      // Mix mode: fade out near the end, then advance.
      if (!_mixTransitionInProgress && _isMixPlaybackActive()) {
        final style = _currentMixStyle();
        final fadeMs = style.fadeDuration.inMilliseconds;
        if (fadeMs > 0) {
          final remaining = durationMs - posMs;
          if (remaining <= fadeMs && remaining > 50) {
            _mixTransitionInProgress = true;
            try {
              await _mixFadeTo(0.0, Duration(milliseconds: remaining));
              if (loopModeEnabled) {
                await _player.seek(Duration.zero);
                await _mixFadeTo(_baseVolume, style.fadeDuration);
                if (!_player.playing) _player.play();
              } else {
                final nextIndex = _getNextSongIndex();
                if (Get.isRegistered<PlaylistMixService>()) {
                  Get.find<PlaylistMixService>()
                      .advancePlaybackIndex(nextIndex);
                }
                _startMutedForMix = true;
                await skipToNextResult(source: PlaybackCommandSource.system);
                await _mixFadeTo(_baseVolume, style.fadeDuration);
              }
            } finally {
              _mixTransitionInProgress = false;
            }
            return;
          }
        }
      }

      if (_mixTransitionInProgress) return;

      _songFadeTick(posMs, durationMs - playerDurationOffset);

      // A show that skips its outro ends the episode where it begins.
      final outroCut = _podcastOutroCutMs(durationMs);

      final remainingMs = (outroCut ?? durationMs) - posMs;
      if (remainingMs > 0 && remainingMs < 45000) {
        final id = mediaItem.value?.id;
        if (id != null && _prefetchArmedForId != id) {
          _prefetchArmedForId = id;
          prefetchNextInQueue();
        }
      }

      if (outroCut != null && await _maybeEndAtOutro(posMs, outroCut)) {
        return;
      }

      if (posMs >= (durationMs - playerDurationOffset)) {
        final id = mediaItem.value?.id;
        if (shouldArmEofAdvance(currentId: id, lastArmedId: _eofArmedForId)) {
          await _triggerNext();
        }
      }
    });
  }

  /// Where the playing episode ends when its show skips the outro, or null.
  int? _podcastOutroCutMs(int durationMs) {
    final item = mediaItem.value;
    if (item == null || !item.isPodcastEpisode) return null;
    return podcastOutroCutMs(
        totalMs: durationMs, trim: PodcastPlaybackPrefs.trimForItem(item));
  }

  /// The episode an outro skip already ended, so ticks past the cut (paused
  /// there when continuous playback is off) don't end it again.
  String? _outroEndedForId;

  /// Ends the playing episode at its show's outro ([cutMs]) as if it had
  /// played out: marked played, then the usual end of an episode (the next
  /// one, or a pause when continuous playback is off). Only while playing,
  /// so scrubbing into the outro while paused doesn't skip.
  Future<bool> _maybeEndAtOutro(int posMs, int cutMs) async {
    final id = mediaItem.value?.id;
    if (id == null) return false;
    if (posMs < cutMs) {
      // Played or sought back before the cut: it can end there again.
      if (_outroEndedForId == id) _outroEndedForId = null;
      return false;
    }
    if (!_player.playing || isSongLoading || _outroEndedForId == id) {
      return false;
    }
    _outroEndedForId = id;
    await _triggerNext();
    // Only now: marking it played takes it out of the podcast Up Next,
    // which _triggerNext reads to know what follows it.
    PodcastProgressService.markPlayed(id);
    return true;
  }

  /// Ends the playing episode now as if it had played out (the player's
  /// Mark as played): the usual end of an episode, the next one or a pause
  /// when continuous playback is off, even with repeat one on; then marked
  /// played, as at its outro. Still on it, it waits from the start: saving
  /// where it was, when another plays, would take the mark back.
  Future<void> _finishEpisode() async {
    final item = mediaItem.value;
    if (item == null || !item.isPodcastEpisode) return;
    // Already ending (it played out meanwhile): only the mark is left.
    if (!_eofAdvanceInProgress) {
      await _triggerNext(repeatOne: false);
      if (mediaItem.value?.id == item.id) {
        await _player.seek(Duration.zero);
        // Played again from the start, its end ends it again.
        _eofArmedForId = null;
      }
    }
    PodcastProgressService.markPlayed(item.id);
  }

  bool _isMixPlaybackActive() {
    try {
      if (!Get.isRegistered<PlaylistMixService>()) return false;
      return Get.find<PlaylistMixService>().mixPlaybackActive.isTrue;
    } catch (_) {
      return false;
    }
  }

  MixTransitionStyle _currentMixStyle() {
    try {
      if (!Get.isRegistered<PlaylistMixService>()) {
        return MixTransitionStyle.auto;
      }
      return Get.find<PlaylistMixService>().playbackStyle;
    } catch (_) {
      return MixTransitionStyle.auto;
    }
  }

  Future<void> _mixFadeTo(double target, Duration duration) async {
    if (duration <= Duration.zero) {
      await _player.setVolume(target.clamp(0.0, 1.0));
      return;
    }
    final start = _player.volume;
    const steps = 16;
    final stepDur = Duration(
      milliseconds: (duration.inMilliseconds / steps).round().clamp(20, 500),
    );
    for (var i = 1; i <= steps; i++) {
      if (!_mixTransitionInProgress && target == 0.0) break;
      final t = i / steps;
      final v = start + (target - start) * t;
      await _player.setVolume(v.clamp(0.0, 1.0));
      await Future<void>.delayed(stepDur);
    }
    await _player.setVolume(target.clamp(0.0, 1.0));
  }

  // ── Fade between songs ────────────────────────────────────────────────

  /// The last seconds of a song fade out, the first ones of the song after
  /// it fade in. The volume follows the position ([posMs] of a song that
  /// ends at [endMs]), so a seek, pause, stall or speed change just moves
  /// along the fade and can't leave the volume low.
  void _songFadeTick(int posMs, int endMs) {
    // A loading song's ticks are the last one's, and the sleep timer's
    // fade has the volume meanwhile.
    if (isSongLoading || _sleepFadeRestoreVolume != null) return;
    final item = mediaItem.value;
    var inMs = 0;
    if (item != null && item.id == _songFadeInId) {
      if (posMs < _songFadeInMs) {
        inMs = _songFadeInMs;
      } else {
        _songFadeInId = null;
      }
    }
    var outMs = item == null ? 0 : _songFadeLength(item, endMs);
    // Not near the end yet; or repeat-one, a Mix (it has its own
    // transitions) or the last song of the queue, which play out as they
    // are.
    if (outMs > 0 &&
        (endMs - posMs >= outMs ||
            loopModeEnabled ||
            _isMixPlaybackActive() ||
            !_hasNextSong())) {
      outMs = 0;
    }
    final factor =
        songFadeFactor(posMs: posMs, lengthMs: endMs, inMs: inMs, outMs: outMs);
    if (factor == null) {
      _endSongFade();
      return;
    }
    final level = (_songFadeBase ??= _player.volume) * factor;
    if ((_player.volume - level).abs() > 0.001) {
      unawaited(_player.setVolume(level.clamp(0.0, 1.0)));
    }
  }

  /// How long [item], [lengthMs] long, fades for: music only, podcasts and
  /// audiobooks play as they are.
  static int _songFadeLength(MediaItem item, int lengthMs) {
    if (item.isPodcastEpisode || item.isAudiobook) return 0;
    return songFadeMs(seconds: SongFade.seconds, lengthMs: lengthMs);
  }

  bool _hasNextSong() =>
      currentIndex is int && _getNextSongIndex() != currentIndex;

  /// Puts the volume back if the fade between songs lowered it.
  void _endSongFade() {
    _songFadeInId = null;
    final base = _songFadeBase;
    if (base == null) return;
    _songFadeBase = null;
    unawaited(_player.setVolume(base));
  }

  /// [song] follows one that faded out: it starts silent and fades in up
  /// to [level], or plays at it straight away (a podcast, a short song).
  Future<void> _startSongFadeIn(MediaItem song, double level) async {
    final length = _player.duration ?? song.duration;
    final ms = _songFadeLength(song, length?.inMilliseconds ?? 0);
    if (ms <= 0) {
      _songFadeBase = null;
      _songFadeInId = null;
      await _player.setVolume(level);
      return;
    }
    _songFadeBase = level;
    _songFadeInId = song.id;
    _songFadeInMs = ms;
    await _player.setVolume(0);
  }

  /// The end of the playing item. [repeatOne] false moves on even with
  /// repeat one on (an episode marked played).
  Future<void> _triggerNext({bool repeatOne = true}) async {
    if (_eofAdvanceInProgress) return;
    _eofAdvanceInProgress = true;
    try {
      if (repeatOne && loopModeEnabled) {
        // Block a second EOF tick while we seek, then clear so loop-one
        // can arm again on the next pass of the same track.
        _eofArmedForId = mediaItem.value?.id;
        await _player.seek(Duration.zero);
        if (!_player.playing) {
          _player.play();
        }
        _eofArmedForId = null;
        return;
      }

      _eofArmedForId = mediaItem.value?.id;

      // AntennaPod-experimental: continuous podcast playback can be toggled off
      // so an episode ends without auto-advancing.
      final item = (currentIndex != null &&
              currentIndex! >= 0 &&
              currentIndex! < queue.value.length)
          ? queue.value[currentIndex!]
          : null;
      if (item != null && PodcastProgressService.isPodcastItem(item)) {
        final continuous = Hive.box('AppPrefs')
                .get('podcastContinuousPlayback', defaultValue: true) ==
            true;
        if (!continuous) {
          await pause();
          return;
        }
        // Playing a lone Continue item with continuous on: append the rest of
        // the manual Podcast Queue so listening keeps going.
        final nextIdx = _getNextSongIndex();
        if (nextIdx == currentIndex &&
            Get.isRegistered<PodcastQueueController>()) {
          final pq = Get.find<PodcastQueueController>().queue;
          final qi = pq.indexWhere((e) => e.id == item.id);
          final rest = qi >= 0
              ? pq.sublist(qi + 1).toList()
              : pq.where((e) => e.id != item.id).toList();
          if (rest.isNotEmpty) {
            await addQueueItems(rest);
          }
        }
        // Finished episode leaves the manual Up Next queue.
        if (Get.isRegistered<PodcastQueueController>()) {
          Get.find<PodcastQueueController>().removeById(item.id);
        }
      }

      await skipToNextResult(source: PlaybackCommandSource.system);
    } finally {
      _eofAdvanceInProgress = false;
    }
  }

  void _listenForDurationChanges() {
    _player.durationStream.listen((duration) async {
      final currQueue = queue.value;
      if (currentIndex == null || currQueue.isEmpty || duration == null) return;
      final currentSong = queue.value[currentIndex];
      // Re-announce only when the real length differs from what the item
      // says (metadata lengths are often rounded or missing), and store it
      // back so later events don't re-emit the same item again.
      final known = currentSong.duration;
      if (known == null ||
          (known - duration).abs() > const Duration(seconds: 1)) {
        final newMediaItem = currentSong.copyWith(duration: duration);
        currQueue[currentIndex] = newMediaItem;
        queue.add(currQueue);
        mediaItem.add(newMediaItem);
      }
    });
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    // notify system
    final newQueue = queue.value..addAll(mediaItems);
    queue.add(newQueue);

    if (shuffleModeEnabled) {
      final mediaItemsIds = mediaItems.toList().map((item) => item.id).toList();
      shuffledQueue = appendToShuffleOrder(
          shuffledQueue, currentShuffleIndex, mediaItemsIds);
    }
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    final newQueue = this.queue.value
      ..replaceRange(0, this.queue.value.length, queue);
    this.queue.add(newQueue);
    // The old shuffle order belongs to the old queue.
    if (shuffleModeEnabled && newQueue.isNotEmpty) _shuffleCmd(0);
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    if (shuffleModeEnabled) {
      shuffledQueue.add(mediaItem.id);
    }

    // notify system
    final newQueue = queue.value..add(mediaItem);
    queue.add(newQueue);
  }

  AudioSource _createAudioSource(MediaItem mediaItem) {
    final url = mediaItem.extras!['url'] as String;
    // Song caching is for YouTube tracks: podcast, Audiobookshelf, cloud and
    // Soulseek items have their own sources (tokenised ABS URLs expire) and
    // must not end up in the Library's cached songs.
    // YouTube podcast episodes are plain video ids but can run for hours;
    // LockCachingAudioSource keeps the whole download in memory, which can
    // exhaust the heap and take the app down. Stream them uncached.
    final cacheable = !_hasDirectStreamUrl(mediaItem.id) &&
        mediaItem.extras?['isPodcast'] != true;
    if (cacheable &&
        (url.contains('/cache') ||
            (Get.find<SettingsScreenController>().cacheSongs.isTrue &&
                url.contains("http")))) {
      printINFO("Playing Using LockCaching");
      isPlayingUsingLockCachingSource = true;
      return LockCachingAudioSource(
        Uri.parse(url),
        cacheFile: File("$_cacheDir/cachedSongs/${mediaItem.id}.mp3"),
        tag: mediaItem,
      );
    }

    printINFO("Playing Using AudioSource.uri");
    isPlayingUsingLockCachingSource = false;
    // A YouTube stream fetched by ExoPlayer itself (no caching proxy) is
    // sent the headers of the client its url was issued to, as NewPipe
    // does; a mismatched User-Agent is one way YouTube answers 403.
    return AudioSource.uri(
      Uri.parse(url),
      headers: youtubeStreamHeaders(url),
      tag: mediaItem,
    );
  }

  /// Auto goes by [NetworkKind.lastMetered]: [checkNGetUrl] asks afresh
  /// as each song starts.
  static int _streamingQualityIndex() {
    final prefs = Hive.box('AppPrefs');
    return streamingQualityIndex(
        dataSaver: prefs.get('dataSaver'),
        streamingQuality: prefs.get('streamingQuality'),
        metered: NetworkKind.lastMetered);
  }

  static bool _hasDirectStreamUrl(String id) =>
      id.startsWith("podcast_") ||
      id.startsWith("abs_") ||
      id.startsWith("lv_") ||
      id.startsWith("cloud_") ||
      id.startsWith("slsk_");

  @override
  // ignore: avoid_renaming_method_parameters
  Future<void> removeQueueItem(MediaItem mediaItem_) async {
    final currentQueue = queue.value;
    final itemIndex = currentQueue.indexOf(mediaItem_);
    // Already gone (removed from a sheet opened before the queue changed):
    // moving the cursors anyway pointed them at the previous song.
    if (itemIndex < 0) return;
    if (shuffleModeEnabled) {
      final id = mediaItem_.id;
      currentShuffleIndex = indexAfterRemoval(
          currentIndex: currentShuffleIndex,
          removedIndex: shuffledQueue.indexOf(id));
      shuffledQueue.remove(id);
    }

    final currentSong = mediaItem.value;
    currentIndex =
        indexAfterRemoval(currentIndex: currentIndex, removedIndex: itemIndex);
    currentQueue.remove(mediaItem_);
    queue.add(currentQueue);
    mediaItem.add(currentSong);
  }

  /// From the notification, lock screen, Android Auto or a headset.
  @override
  Future<void> play() => playFrom(_externalSource());

  Future<void> playFrom(PlaybackCommandSource source) async {
    _logCommand('play', source);
    // Video mode's engine owns playback (and plays the audio itself):
    // ignore stray transport (e.g. media notification) so the paused
    // audio pipeline can't start underneath the video.
    if (Get.isRegistered<VideoModeController>() &&
        Get.find<VideoModeController>().isActive.value) {
      return;
    }
    if (currentSongUrl == null ||
        (GetPlatform.isDesktop &&
            (_player.duration == null ||
                _player.duration?.inMilliseconds == 0))) {
      await customAction("playByIndex", {'index': currentIndex});
      return;
    }
    await _maybeSmartResume();
    try {
      await _player.play();
    } catch (e) {
      printERROR('play() player start failed: $e');
      await _handleRuntimePlaybackError(e, position: _player.position);
    }
  }

  /// Podcasts and audiobooks: after a pause, step back a little (longer
  /// pause, longer step) so the sentence that was cut off plays again.
  Future<void> _maybeSmartResume() async {
    final pausedAt = _longFormPausedAt;
    _longFormPausedAt = null;
    final item = mediaItem.value;
    if (pausedAt == null || item == null || !smartResumeApplies(item)) return;
    if (!PodcastPlaybackPrefs.smartResume) return;
    final rewind = smartResumeRewind(DateTime.now().difference(pausedAt));
    if (rewind == Duration.zero) return;
    try {
      await _player.seek(smartResumeTarget(_player.position, rewind));
    } catch (_) {}
  }

  @override
  Future<void> pause() => pauseFrom(_externalSource());

  Future<void> pauseFrom(PlaybackCommandSource source) {
    _logCommand('pause', source);
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) =>
      seekFrom(position, _externalSource());

  Future<void> seekFrom(Duration position, PlaybackCommandSource source) async {
    _logCommand('seek', source, '→ ${position.inMilliseconds}ms');
    if (source.isUserIntent) {
      userSeekSerial++;
      lastUserSeek = SeekRecord(
          source: source,
          atMs: DateTime.now().millisecondsSinceEpoch,
          targetMs: position.inMilliseconds);
    }
    _watchdog.reset();
    await _player.seek(position);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    _logCommand('skipToQueueItem', _externalSource(), '#$index');
    await customAction("playByIndex", {'index': index});
  }

  /// Keeps [currentShuffleIndex] on the song that is playing and rebuilds
  /// [shuffledQueue] when it no longer matches the queue (updateQueue and
  /// session resume replace the queue wholesale). Returns the position, or
  /// -1 for an empty queue.
  int _syncShufflePos() {
    final q = queue.value;
    if (q.isEmpty) return -1;
    final idx = currentIndex is int && isValidQueueIndex(currentIndex as int, q.length)
        ? currentIndex as int
        : 0;
    var pos = shuffledQueue.length == q.length
        ? shuffledQueue.indexOf(q[idx].id)
        : -1;
    if (pos < 0) {
      _shuffleCmd(idx);
      pos = 0;
    }
    currentShuffleIndex = pos;
    return pos;
  }

  /// Queue index of the next song. Only a real skip passes [advance]: the
  /// prefetch and the "is there a next track" checks just look, and used to
  /// move the shuffle cursor too, so shuffle skipped songs.
  int _getNextSongIndex({bool advance = false}) {
    if (shuffleModeEnabled) {
      final pos = _syncShufflePos();
      if (pos < 0) return currentIndex;
      final ids = queue.value.map((e) => e.id).toList();
      final String nextId;
      if (pos + 1 < shuffledQueue.length) {
        nextId = shuffledQueue[pos + 1];
        if (advance) currentShuffleIndex = pos + 1;
      } else if (advance) {
        shuffledQueue.shuffle();
        currentShuffleIndex = 0;
        nextId = shuffledQueue[0];
      } else {
        // Past the end the order is reshuffled on the real skip; for a
        // look-ahead any other track counts as "next".
        final cur = currentIndex is int ? currentIndex as int : 0;
        return ids.length > 1 ? (cur + 1) % ids.length : currentIndex;
      }
      final at = resolveShuffledQueueIndex(queueIds: ids, shuffledId: nextId);
      return isValidQueueIndex(at, ids.length) ? at : currentIndex;
    }

    if (queue.value.length > currentIndex + 1) {
      return currentIndex + 1;
    } else if (queueLoopModeEnabled) {
      return 0;
    } else {
      return currentIndex;
    }
  }

  /// Queue index of the previous song; moves the shuffle cursor (only the
  /// Previous button calls this).
  int _getPrevSongIndex() {
    if (shuffleModeEnabled) {
      final pos = _syncShufflePos();
      if (pos < 0) return currentIndex;
      if (pos - 1 < 0) {
        shuffledQueue.shuffle();
        currentShuffleIndex = shuffledQueue.length - 1;
      } else {
        currentShuffleIndex = pos - 1;
      }
      final ids = queue.value.map((e) => e.id).toList();
      final at = resolveShuffledQueueIndex(
        queueIds: ids,
        shuffledId: shuffledQueue[currentShuffleIndex],
      );
      return isValidQueueIndex(at, ids.length) ? at : currentIndex;
    }

    if (currentIndex - 1 >= 0) {
      return currentIndex - 1;
    } else {
      return currentIndex;
    }
  }

  @override
  Future<void> skipToNext() async {
    await skipToNextResult(source: _externalSource());
  }

  /// True when skip started another track (or radio extend). Last-track pause is false.
  Future<bool> skipToNextResult(
      {PlaybackCommandSource source = PlaybackCommandSource.system}) async {
    _logCommand('skipToNext', source);
    final from = currentIndex is int ? currentIndex as int : -1;
    final index = _getNextSongIndex(advance: true);
    if (skipNextDidAdvance(fromIndex: from, toIndex: index)) {
      if (_player.position != Duration.zero) _player.seek(Duration.zero);
      final result = await customAction("playByIndex", {'index': index});
      return !playByIndexHardFailed(result);
    }
    final radioOn = Get.isRegistered<PlayerController>() &&
        Get.find<PlayerController>().isRadioModeOn;
    if (radioShouldExtendInsteadOfPause(radioOn: radioOn, hasNext: false)) {
      return Get.find<PlayerController>().extendRadioThenPlayNext();
    }
    // Autoplay (when on): songs like the last one play on.
    if (Get.isRegistered<PlayerController>() &&
        await Get.find<PlayerController>().autoplayAfterQueue()) {
      return true;
    }
    _player.seek(Duration.zero);
    _player.pause();
    return false;
  }

  @override
  Future<void> skipToPrevious() async {
    await skipToPreviousResult(source: _externalSource());
  }

  /// True when previous restarted the track or started the prior item.
  /// [restart] false always goes to the prior item (the mini player's
  /// swipe shows that track sliding in, so restarting would contradict it).
  Future<bool> skipToPreviousResult(
      {PlaybackCommandSource source = PlaybackCommandSource.system,
      bool restart = true}) async {
    _logCommand('skipToPrevious', source);
    if (restart && shouldRestartOnPrevious(_player.position)) {
      _player.seek(Duration.zero);
      return true;
    }
    _player.seek(Duration.zero);
    final from = currentIndex is int ? currentIndex as int : -1;
    final index = _getPrevSongIndex();
    if (!skipNextDidAdvance(fromIndex: from, toIndex: index)) {
      return true;
    }
    final result = await customAction("playByIndex", {'index': index});
    return !playByIndexHardFailed(result);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    if (repeatMode == AudioServiceRepeatMode.none) {
      loopModeEnabled = false;
    } else {
      loopModeEnabled = true;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      shuffleModeEnabled = false;
      shuffledQueue.clear();
    } else {
      _shuffleCmd(currentIndex);
      shuffleModeEnabled = true;
    }
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'setSpeedAndPitch':
        await _player.setSpeed((extras!['speed'] as num).toDouble());
        await _setPitch((extras['pitch'] as num).toDouble());
        break;

      case 'setAudioFx':
        _applyAudioFx();
        break;

      // Riff's equalizer screen: the phone's bands, null without any.
      case 'equalizerLayout':
        final id = _player.androidAudioSessionId;
        if (id == null) return null;
        try {
          return await _fxChannel.invokeMethod('eqLayout', {'sessionId': id});
        } catch (_) {
          return null;
        }

      case 'skipToNext':
        return skipToNextResult(
            source: PlaybackCommandSource.parse(extras?['source']));

      case 'skipToPrevious':
        return skipToPreviousResult(
            source: PlaybackCommandSource.parse(extras?['source']),
            restart: extras?['restart'] != false);

      case 'finishEpisode':
        await _finishEpisode();
        break;

      case 'playByIndex':
        final songIndex = coercePlayByIndex(extras!['index']);
        if (!isValidQueueIndex(songIndex, queue.value.length)) {
          isSongLoading = false;
          playbackState.add(playbackState.value.copyWith(
            processingState: AudioProcessingState.idle,
          ));
          return false;
        }
        // Fade between songs: the song after one that faded out fades in;
        // anything else played meanwhile puts the volume back first.
        final fadeIn = _songFadeBase != null && _eofAdvanceInProgress;
        if (!fadeIn) _endSongFade();
        currentIndex = songIndex;
        if (shuffleModeEnabled) _syncShufflePos();
        final requestId = ++_playRequestId;
        bool superseded() => requestId != _playRequestId;
        final isNewUrlReq = extras['newUrl'] ?? false;
        final currentSong = queue.value[currentIndex];
        final futureStreamInfo =
            checkNGetUrl(currentSong.id, generateNewUrl: isNewUrlReq);
        final bool restoreSession = extras['restoreSession'] ?? false;
        isSongLoading = true;
        playbackState.add(playbackState.value
            .copyWith(processingState: AudioProcessingState.loading));
        if (_playList.children.isNotEmpty) {
          await _playList.clear();
        }

        mediaItem.add(currentSong);
        _longFormPausedAt = null;
        // Podcast episodes play with their show's profile (this is also the
        // queue auto-advance path); anything else gets music's settings.
        await _applyPlaybackProfile(currentSong);
        late HMStreamingData streamInfo;
        var resolveFailed = false;
        try {
          streamInfo = await futureStreamInfo;
          if (!streamInfo.playable && isNewUrlReq != true) {
            printINFO(
                'playByIndex: first resolve not playable, retrying with new URL');
            streamInfo =
                await checkNGetUrl(currentSong.id, generateNewUrl: true);
          }
        } catch (e) {
          printERROR('playByIndex stream resolve failed: $e');
          if (isNewUrlReq != true) {
            try {
              streamInfo =
                  await checkNGetUrl(currentSong.id, generateNewUrl: true);
            } catch (e2) {
              printERROR('playByIndex stream resolve retry failed: $e2');
              resolveFailed = true;
            }
          } else {
            resolveFailed = true;
          }
        }
        // A newer play request owns the player (and the loading state).
        if (superseded()) return null;
        if (resolveFailed) {
          return _onPlayByIndexUnresolvable(
            songId: currentSong.id,
            errorMessage: "streamLoadFailed",
            errorCode: 500,
          );
        }
        if (isStalePlayByIndex(
          requestedSongId: currentSong.id,
          currentSongId: _currentQueueSongId(),
        )) {
          isSongLoading = false;
          return null;
        } else if (!streamInfo.playable) {
          return _onPlayByIndexUnresolvable(
            songId: currentSong.id,
            errorMessage: streamInfo.statusMSG,
            errorCode: 404,
          );
        }
        _consecutiveResolveFails = 0;
        try {
          currentSongUrl = currentSong.extras!['url'] = streamInfo.audio!.url;
          playbackState
              .add(playbackState.value.copyWith(queueIndex: currentIndex));
          // A second request for the same song (double tap, retry) could
          // otherwise both land here and queue the track twice.
          if (_playList.children.isNotEmpty) await _playList.clear();
          if (superseded()) return null;
          await _playList.add(_createAudioSource(currentSong));
        } catch (e) {
          // Never leave the notification stuck on "loading".
          printERROR('playByIndex source setup failed: $e');
          isSongLoading = false;
          return _handleRuntimePlaybackError(e, position: Duration.zero);
        }

        isSongLoading = false;
        // The fade between songs keeps the level it lowered the volume from.
        final level = _songFadeBase ?? _player.volume;
        final normalize = loudnessNormalizationEnabled && GetPlatform.isAndroid;
        if (normalize) {
          _normalizeVolume(streamInfo.audio!.loudnessDb);
        } else {
          _baseVolume = level.clamp(0.0, 1.0);
          if (_baseVolume <= 0) _baseVolume = 1.0;
        }
        if (_startMutedForMix) {
          await _player.setVolume(0);
          _startMutedForMix = false;
        }
        if (fadeIn) {
          await _startSongFadeIn(currentSong, normalize ? _baseVolume : level);
        }

        final resumeMs = (extras['position'] as num?)?.toInt() ?? 0;
        try {
          if (restoreSession || resumeMs > 0) {
            // Desktop previously skipped restore entirely; always load+seek when
            // we have a saved/retry position so cold start and error recovery work.
            await _player.load();
            if (resumeMs > 0) {
              await _player.seek(Duration(milliseconds: resumeMs));
            }
            if (!restoreSession) {
              await _player.play();
            }
          } else {
            await _player.play();
          }
        } catch (e) {
          printERROR('playByIndex player start failed: $e');
          return _handleRuntimePlaybackError(
            e,
            position: Duration(milliseconds: resumeMs),
          );
        }
        prefetchNextInQueue();
        return true;

      case 'checkWithCacheDb':
        if (isPlayingUsingLockCachingSource) {
          final song = extras!['mediaItem'] as MediaItem;
          final songsCacheBox = Hive.box("SongsCache");
          if (!_hasDirectStreamUrl(song.id) &&
              !songsCacheBox.containsKey(song.id) &&
              await File("$_cacheDir/cachedSongs/${song.id}.mp3").exists()) {
            // The next track may already have replaced the source.
            final duration = _player.duration;
            if (duration == null || mediaItem.value?.id != song.id) break;
            song.extras!['url'] = currentSongUrl;
            song.extras!['date'] = DateTime.now().millisecondsSinceEpoch;
            final dbStreamData = Hive.box("SongsUrlCache").get(song.id);
            final jsonData = MediaItemBuilder.toJson(song);
            jsonData['duration'] = duration.inSeconds;
            // playbility status and info
            jsonData['streamInfo'] = dbStreamData != null
                ? [
                    true,
                    dbStreamData[_streamingQualityIndex() == 0
                        ? 'lowQualityAudio'
                        : "highQualityAudio"]
                  ]
                : null;
            songsCacheBox.put(song.id, jsonData);
            if (!Get.isRegistered<LibrarySongsController>()) break;
            LibrarySongsController librarySongsController =
                Get.find<LibrarySongsController>();
            if (!librarySongsController.isClosed) {
              librarySongsController.librarySongsList.value =
                  librarySongsController.librarySongsList.toList() + [song];
            }
          }
        }
        break;

      case 'toggleSkipSilence':
        final enable = (extras!['enable'] as bool);
        await _player.setSkipSilenceEnabled(enable);
        break;

      case 'toggleLoudnessNormalization':
        loudnessNormalizationEnabled = (extras!['enable'] as bool);
        if (!loudnessNormalizationEnabled) {
          _baseVolume = 1.0;
          _player.setVolume(1.0);
          return;
        }

        if (loudnessNormalizationEnabled) {
          try {
            final currentSongId = (queue.value[currentIndex]).id;
            if (Hive.box("SongsUrlCache").containsKey(currentSongId)) {
              final songJson = Hive.box("SongsUrlCache").get(currentSongId);
              _normalizeVolume((songJson)["highQualityAudio"]["loudnessDb"]);
              return;
            }

            if (Hive.box("SongDownloads").containsKey(currentSongId)) {
              final streamInfo =
                  (Hive.box("SongDownloads").get(currentSongId))["streamInfo"];

              _normalizeVolume(
                  streamInfo == null ? 0 : streamInfo[1]["loudnessDb"]);
            }
          } catch (e) {
            printERROR(e);
          }
        }
        break;

      case 'shuffleQueue':
        final currentQueue = queue.value;
        final currentItem = currentQueue[currentIndex];
        currentQueue.remove(currentItem);
        currentQueue.shuffle();
        currentQueue.insert(0, currentItem);
        queue.add(currentQueue);
        mediaItem.add(currentItem);
        currentIndex = 0;
        break;

      case 'reorderQueue':
        final oldIndex = extras!['oldIndex'];
        int newIndex = extras['newIndex'];

        if (oldIndex < newIndex) {
          newIndex--;
        }

        final currentQueue = queue.value;
        final currentItem = currentQueue[currentIndex];
        final item = currentQueue.removeAt(
          oldIndex,
        );
        currentQueue.insert(newIndex, item);
        currentIndex = currentQueue.indexOf(currentItem);
        queue.add(currentQueue);
        mediaItem.add(currentItem);
        break;

      case 'addPlayNextItem':
        final song = extras!['mediaItem'] as MediaItem;
        final currentQueue = queue.value;
        currentQueue.insert(currentIndex + 1, song);
        queue.add(currentQueue);
        if (shuffleModeEnabled) {
          shuffledQueue.insert(currentShuffleIndex + 1, song.id);
        }
        break;

      case 'openEqualizer':
        EqualizerService.openEqualizer(_player.androidAudioSessionId!);
        break;

      case 'saveSession':
        await saveSessionData();
        break;

      case 'setSegmentMute':
        // Podcast segments set to "Mute": silence, then the old volume.
        if (extras?['muted'] == true) {
          _segmentMuteRestore ??= _player.volume;
          await _player.setVolume(0);
        } else {
          final restore = _segmentMuteRestore;
          _segmentMuteRestore = null;
          if (restore != null) await _player.setVolume(restore);
        }
        break;

      case 'refreshPlaybackProfile':
        // Podcast settings changed while something is playing.
        await _applyPlaybackProfile(mediaItem.value);
        break;

      case 'sleepFadePause':
        // Sleep timer: fade out, pause, put the volume back.
        final ms = (extras?['ms'] as num?)?.toInt() ?? 10000;
        final length = Duration(milliseconds: ms.clamp(0, 60000));
        final token = ++_sleepFadeToken;
        final restore = _sleepFadeRestoreVolume ??= _player.volume;
        _logCommand('fade-out', PlaybackCommandSource.sleepTimer,
            '${length.inMilliseconds}ms');
        // Same ramp as the auto-skip duck, in coarser steps.
        if (!await _rampVolume(restore, 0, length,
            step: const Duration(milliseconds: 250),
            keepGoing: () => token == _sleepFadeToken)) {
          return false;
        }
        await pauseFrom(PlaybackCommandSource.sleepTimer);
        await _player.setVolume(restore);
        _sleepFadeRestoreVolume = null;
        return true;

      case 'cancelSleepFade':
        _sleepFadeToken++;
        final restore = _sleepFadeRestoreVolume;
        _sleepFadeRestoreVolume = null;
        if (restore != null) await _player.setVolume(restore);
        break;

      case 'setVolume':
        _baseVolume = (extras!['value'] / 100).clamp(0.0, 1.0);
        // A fade between songs carries on from the new level.
        if (_songFadeBase != null) _songFadeBase = _baseVolume;
        _player.setVolume(_baseVolume);
        break;

      case 'shuffleCmd':
        final songIndex = extras!['index'];
        _shuffleCmd(songIndex);
        break;

      case 'upadateMediaItemInAudioService':
        //added to update media item from player controller
        final songIndex = extras!['index'];
        currentIndex = songIndex;
        mediaItem.add(queue.value[currentIndex]);
        break;

      case 'toggleQueueLoopMode':
        queueLoopModeEnabled = extras!['enable'];
        break;

      case likeActionName:
        // The heart on the notification / lock screen / Android Auto.
        if (Get.isRegistered<PlayerController>()) {
          await Get.find<PlayerController>().toggleFavourite();
        }
        break;

      case 'setLiked':
        // The app checked or toggled the playing song's like.
        _likedReportId = extras!['id'] as String?;
        _likedReport = extras['liked'] == true;
        _publishPlaybackState();
        break;

      case 'removeQueueItemUndoable':
        // Removes like removeQueueItem, and says where the song was so
        // Undo can put it back in the same place.
        final item = extras!['mediaItem'] as MediaItem;
        final at = queue.value.indexWhere((e) => e.id == item.id);
        if (at < 0) return null;
        final shuffleAt =
            shuffleModeEnabled ? shuffledQueue.indexOf(item.id) : -1;
        await removeQueueItem(queue.value[at]);
        return {'index': at, 'shuffleIndex': shuffleAt};

      case 'restoreQueueItem':
        final item = extras!['mediaItem'] as MediaItem;
        final currentQueue = queue.value;
        // Already back (e.g. re-added from a menu meanwhile).
        if (currentQueue.any((e) => e.id == item.id)) break;
        final cur = currentIndex is int ? currentIndex as int : 0;
        final at = restoreQueuePositions(
          queueLength: currentQueue.length,
          currentIndex: cur,
          index: extras['index'] as int? ?? currentQueue.length,
          shuffleLength: shuffledQueue.length,
          currentShuffleIndex: currentShuffleIndex,
          shuffleIndex: extras['shuffleIndex'] as int? ?? -1,
        );
        final currentSong = mediaItem.value;
        currentQueue.insert(at.index, item);
        currentIndex = at.currentIndex;
        if (shuffleModeEnabled) {
          shuffledQueue.insert(at.shuffleIndex, item.id);
          currentShuffleIndex = at.currentShuffleIndex;
        }
        queue.add(currentQueue);
        mediaItem.add(currentSong);
        break;

      case 'restoreQueue':
        // Undo "Clear queue": only while the same song is still playing.
        final snapshot = (extras!['queue'] as List).cast<MediaItem>();
        final currentSong = mediaItem.value;
        final at = snapshot.indexWhere((e) => e.id == currentSong?.id);
        if (currentSong == null || at < 0) break;
        final restored =
            mergeRestoredQueue<MediaItem>(snapshot, queue.value, (e) => e.id);
        final currentQueue = queue.value
          ..replaceRange(0, queue.value.length, restored);
        currentIndex = at;
        queue.add(currentQueue);
        if (shuffleModeEnabled) _shuffleCmd(at);
        mediaItem.add(currentSong);
        break;

      case 'clearQueue':
        customAction("reorderQueue", {'oldIndex': currentIndex, 'newIndex': 0});
        final newQueue = queue.value;
        newQueue.removeRange(1, newQueue.length);
        queue.add(newQueue);
        if (shuffleModeEnabled) {
          shuffledQueue.clear();
          shuffledQueue.add(newQueue[0].id);
          currentShuffleIndex = 0;
        }
        break;
      default:
        break;
    }
  }

  void _shuffleCmd(int index) {
    final queueIds = queue.value.toList().map((item) => item.id).toList();
    final currentSongId = queueIds.removeAt(index);
    queueIds.shuffle();
    queueIds.insert(0, currentSongId);
    shuffledQueue.replaceRange(0, shuffledQueue.length, queueIds);
    currentShuffleIndex = 0;
  }

  void _normalizeVolume(double currentLoudnessDb) {
    // 0.0 means "loudness unknown" (older cache entries / failed fetch):
    // normalizing against it would just lower the volume to ~56%.
    if (currentLoudnessDb == 0.0) {
      _baseVolume = 1.0;
      _player.setVolume(1.0);
      return;
    }
    // Brought to the volume level chosen in Settings (Normal: −5 dB).
    final volumeAdjustment = normalizedVolume(
        currentLoudnessDb, NormalizationLevel.selected.value.targetDb);
    printINFO(
        "loudness:$currentLoudnessDb Normalized volume: $volumeAdjustment");
    _baseVolume = volumeAdjustment;
    _player.setVolume(_baseVolume);
  }

  Future<void> _sessionSave = Future.value();
  String? _lastSavedSession;

  /// Saves the queue, index and position for resume / "Continue listening".
  /// Runs on every trip to the background, so calls are serialised (two
  /// overlapping saves used to close the shared box under each other) and
  /// an unchanged session is not rewritten.
  Future<void> saveSessionData() {
    _sessionSave = _sessionSave
        .then((_) => _saveSessionData())
        .catchError((Object e) => printERROR('Session save failed: $e'));
    return _sessionSave;
  }

  Future<void> _saveSessionData() async {
    final currQueue = List<MediaItem>.of(queue.value);
    // Persist whenever the queue is non-empty so Home can offer
    // "Continue listening" even if auto-restore is turned off.
    if (currQueue.isEmpty) {
      return;
    }
    final currIndex = currentIndex ?? 0;
    final position = _player.position.inMilliseconds;
    final signature =
        '${currQueue.map((e) => e.id).join(',')}|$currIndex|${position ~/ 1000}';
    if (signature == _lastSavedSession) return;
    final queueData =
        currQueue.map((e) => MediaItemBuilder.toJson(e)).toList();
    final prevSessionData = Hive.isBoxOpen("prevSessionData")
        ? Hive.box("prevSessionData")
        : await Hive.openBox("prevSessionData");
    await prevSessionData.putAll(
        {"queue": queueData, "position": position, "index": currIndex});
    _lastSavedSession = signature;
    printINFO("Saved session data");
  }

  /// Android Auto
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    // Only outside browsers (Android Auto, mostly) list the library.
    _lastAutoBrowseAt = DateTime.now();
    unawaited(_refreshCarMode());
    return _mediaLibrary.browse(parentMediaId, options);
  }

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
    return Stream.fromFuture(
            _mediaLibrary.getByRootId(parentMediaId).then((items) => items))
        .map((_) => <String, dynamic>{})
        .shareValue();
  }

  /// Android Auto's search button: the songs found for [query], played
  /// from that list like the car's others.
  @override
  Future<List<MediaItem>> search(String query,
      [Map<String, dynamic>? extras]) async {
    _lastAutoBrowseAt = DateTime.now();
    final found = await _mediaLibrary.searchSongs(query);
    return _mediaLibrary._forCar(MediaLibrary.searchResultsId, found);
  }

  /// "Play … on Riff", to Android Auto or the Assistant: the player plays
  /// what [MediaLibrary.voiceSearchList] finds.
  @override
  Future<void> playFromSearch(String query,
      [Map<String, dynamic>? extras]) async {
    customEvent.add({'eventType': 'playFromSearch', 'query': query});
  }

  // only for Android Auto
  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    customEvent.add({
      'eventType': 'playFromMediaId',
      'songId': mediaId,
      // Not every car sends the item's extras back; the player then finds
      // the list the item was browsed from.
      'libraryId': extras?['libraryId'] ?? MediaLibrary.listIdFor(mediaId),
    });
  }

  @override
  Future<void> onTaskRemoved() async {
    final stopForegroundService =
        Get.find<SettingsScreenController>().stopPlyabackOnSwipeAway.value;
    if (stopForegroundService) {
      await Get.find<HomeScreenController>().cachedHomeScreenData();
      await saveSessionData();
      await stop();
    }
  }

  @override
  Future<void> stop() async {
    _logCommand('stop', _externalSource());
    await _player.stop();
    return super.stop();
  }

// Work around used [useNewInstanceOfExplode = false] to Fix Connection closed before full header was received issue
  Future<HMStreamingData> checkNGetUrl(String songId,
      {bool generateNewUrl = false, bool offlineReplacementUrl = false}) {
    if (generateNewUrl || offlineReplacementUrl) {
      return _checkNGetUrl(songId,
          generateNewUrl: generateNewUrl,
          offlineReplacementUrl: offlineReplacementUrl);
    }
    final pending = _urlInflight[songId];
    if (pending != null) return pending;
    final lookup = _checkNGetUrl(songId);
    _urlInflight[songId] = lookup;
    lookup.whenComplete(() {
      if (identical(_urlInflight[songId], lookup)) _urlInflight.remove(songId);
    }).ignore();
    return lookup;
  }

  Future<HMStreamingData> _checkNGetUrl(String songId,
      {bool generateNewUrl = false, bool offlineReplacementUrl = false}) async {
    await _cacheDirReady;
    printINFO("Requested id : $songId");
    // Podcast episodes, Audiobookshelf tracks and Cloud (self-hosted music
    // server) songs carry a direct stream URL — no YouTube stream resolution
    // needed (same pattern Lissen uses for ABS).
    if (_hasDirectStreamUrl(songId)) {
      MediaItem? item;
      for (final e in queue.value) {
        if (e.id == songId) {
          item = e;
          break;
        }
      }
      var url = item?.extras?['url'] as String?;
      // Prefer a downloaded local copy for any podcast episode (RSS podcast_*
      // ids and YTM video-id episodes flagged isPodcast).
      final isPodcast = songId.startsWith("podcast_") ||
          item?.extras?['isPodcast'] == true;
      if (isPodcast && Hive.isBoxOpen("PodcastDownloads")) {
        final local = Hive.box("PodcastDownloads").get(songId);
        String? path;
        if (local is String && local.isNotEmpty) {
          path = local;
        } else if (local is Map && local['path'] is String) {
          path = local['path'] as String;
        }
        if (path != null && path.isNotEmpty && File(path).existsSync()) {
          // Keep the remote enclosure URL: extras['url'] is overwritten with
          // the resolved local URL once playback starts, and the saved progress
          // record is built from these extras — without this the "Continue"
          // entry points at a file that disappears with the download.
          if (url != null && url.isNotEmpty) {
            item?.extras?['remoteUrl'] ??= url;
          }
          url = "file://$path";
        }
      }
      // Refresh ABS stream URL on retry — tokenized URLs expire.
      if (generateNewUrl &&
          songId.startsWith('abs_') &&
          Get.isRegistered<AudiobookshelfService>()) {
        final abs = Get.find<AudiobookshelfService>();
        final itemId = item?.extras?['absItemId']?.toString();
        final trackIndex = (item?.extras?['absTrackIndex'] as num?)?.toInt();
        if (itemId != null && trackIndex != null) {
          try {
            final detail = await abs.openBook(itemId);
            final refreshed = abs.toMediaItems(detail);
            final match = refreshed.firstWhereOrNull(
                (m) => (m.extras?['absTrackIndex'] as num?)?.toInt() ==
                    trackIndex);
            if (match != null) {
              url = match.extras?['url'] as String?;
              item?.extras?['url'] = url;
              item?.extras?['absSessionId'] = match.extras?['absSessionId'];
            }
          } catch (e) {
            printERROR('ABS URL refresh failed: $e');
          }
        }
      }
      if (generateNewUrl &&
          songId.startsWith('cloud_') &&
          Get.isRegistered<CloudMusicService>()) {
        try {
          final serverId = cloudServerSongId(songId);
          if (serverId.isNotEmpty) {
            url = Get.find<CloudMusicService>().streamUrl(serverId);
            item?.extras?['url'] = url;
          }
        } catch (e) {
          printERROR('Cloud URL refresh failed: $e');
        }
      }
      if (url != null && url.isNotEmpty) {
        final audio = Audio(
            audioCodec: Codec.mp4a,
            bitrate: 0,
            loudnessDb: 0,
            duration: 0,
            size: 0,
            url: url,
            itag: 0);
        return HMStreamingData(
            playable: true,
            statusMSG: "OK",
            lowQualityAudio: audio,
            highQualityAudio: audio);
      }
      return HMStreamingData(playable: false, statusMSG: "networkError");
    }
    // Device E2E builds only (empty, and compiled out, everywhere else):
    // YouTube refuses stream urls to CI runners, so every YouTube id plays
    // this file instead and the rest of the playback path runs as on a phone.
    if (_e2eStreamUrl.isNotEmpty) {
      final audio = Audio(
          audioCodec: Codec.mp4a,
          bitrate: 64000,
          loudnessDb: 0,
          duration: 0,
          size: 0,
          url: _e2eStreamUrl,
          itag: 140);
      return HMStreamingData(
          playable: true,
          statusMSG: "OK",
          lowQualityAudio: audio,
          highQualityAudio: audio);
    }
    final songDownloadsBox = Hive.box("SongDownloads");
    final songsCache = await Hive.openBox("SongsCache");
    if (!offlineReplacementUrl && songsCache.containsKey(songId)) {
      // Android clears the temp dir under storage pressure (and on "Clear
      // cache") while the Hive entry survives: without this the song would
      // be unplayable forever, retries included.
      if (generateNewUrl ||
          !File("$_cacheDir/cachedSongs/$songId.mp3").existsSync()) {
        await songsCache.delete(songId);
        return _checkNGetUrl(songId, generateNewUrl: generateNewUrl);
      }
      printINFO("Got Song from cachedbox ($songId)");
      // if contains stream Info
      final streamInfo = Hive.box("SongsCache").get(songId)["streamInfo"];
      Audio? cacheAudioPlaceholder;
      if (streamInfo != null && streamInfo.isNotEmpty) {
        streamInfo[1]['url'] = "file://$_cacheDir/cachedSongs/$songId.mp3";
        cacheAudioPlaceholder = Audio.fromJson(streamInfo[1]);
      } else {
        cacheAudioPlaceholder = Audio(
            audioCodec: Codec.mp4a,
            bitrate: 0,
            loudnessDb: 0,
            duration: 0,
            size: 0,
            url: "file://$_cacheDir/cachedSongs/$songId.mp3",
            itag: 0);
      }

      return HMStreamingData(
          playable: true,
          statusMSG: "OK",
          lowQualityAudio: cacheAudioPlaceholder,
          highQualityAudio: cacheAudioPlaceholder);
    } else if (!offlineReplacementUrl && songDownloadsBox.containsKey(songId)) {
      final song = songDownloadsBox.get(songId);
      final streamInfoJson = song["streamInfo"];
      Audio? audio;
      final path = song['url'];
      if (streamInfoJson != null && streamInfoJson.isNotEmpty) {
        audio = Audio.fromJson(streamInfoJson[1]);
      } else {
        audio = Audio(
            itag: 140,
            audioCodec: Codec.mp4a,
            bitrate: 0,
            duration: 0,
            loudnessDb: 0,
            url: path,
            size: 0);
      }

      final streamInfo = HMStreamingData(
          playable: true,
          statusMSG: "OK",
          highQualityAudio: audio,
          lowQualityAudio: audio);

      if (path.contains(
          "${Get.find<SettingsScreenController>().supportDirPath}/Music")) {
        return streamInfo;
      }
      //check file access and if file exist in storage
      final status = await PermissionService.getExtStoragePermission();
      if (status && await File(path).exists()) {
        return streamInfo;
      }
      //in case file doesnot found in storage, song will be played online
      return checkNGetUrl(songId, offlineReplacementUrl: true);
    } else {
      //check if song stream url is cached and allocate url accordingly
      final songsUrlCacheBox = Hive.box("SongsUrlCache");
      // Auto quality goes by the connection the song starts on.
      if (Hive.box('AppPrefs').get('streamingQuality') ==
          autoStreamingQuality) {
        await NetworkKind.isMetered();
      }
      final qualityIndex = _streamingQualityIndex();
      HMStreamingData? streamInfo;
      if (songsUrlCacheBox.containsKey(songId) && !generateNewUrl) {
        try {
          final streamInfoJson = songsUrlCacheBox.get(songId);
          if (streamInfoJson is Map &&
              songsUrlCacheQualityUsable(
                streamInfoJson,
                qualityIndex: qualityIndex,
              )) {
            printINFO("Got cached Url ($songId)");
            streamInfo = HMStreamingData.fromJson(streamInfoJson);
          }
        } catch (e) {
          printERROR("Bad SongsUrlCache entry for $songId: $e");
          try {
            await songsUrlCacheBox.delete(songId);
          } catch (_) {}
        }
      }

      if (streamInfo == null) {
        final token = RootIsolateToken.instance;
        // Remote client config + optional YT login cookies are handed over
        // by value: the spawned isolate shares no statics or Hive.
        final clientConfigJson = ClientConfigService.currentJson;
        final authHeaders = StreamProvider.authHeadersFromSession();
        Map<String, dynamic> streamInfoJson;
        try {
          if (token != null) {
            streamInfoJson = await Isolate.run(() => getStreamInfo(
                  songId,
                  token,
                  clientConfigJson: clientConfigJson,
                  fetchLoudness: loudnessNormalizationEnabled,
                  authHeaders: authHeaders,
                ));
          } else {
            streamInfoJson = await getStreamInfo(
              songId,
              null,
              clientConfigJson: clientConfigJson,
              fetchLoudness: loudnessNormalizationEnabled,
              authHeaders: authHeaders,
            );
          }
        } catch (e) {
          printERROR("getStreamInfo isolate failed, retrying in-place: $e");
          try {
            streamInfoJson = await StreamProvider.fetch(songId,
                    clientConfigJson: clientConfigJson,
                    authHeaders: authHeaders)
                .then((p) => p.hmStreamingData);
          } catch (e2) {
            printERROR("stream resolve failed: $e2");
            // A retired client is the usual cause: pull a fresh remote
            // config (TTL-bypassing, 5-min cooldown) so the next attempt —
            // or the next track — can use a published fix.
            unawaited(ClientConfigService.forceRefresh());
            return HMStreamingData(
                playable: false, statusMSG: "streamLoadFailed");
          }
        }
        try {
          streamInfo = HMStreamingData.fromJson(streamInfoJson);
        } catch (e) {
          printERROR("HMStreamingData.fromJson failed: $e");
          unawaited(ClientConfigService.forceRefresh());
          return HMStreamingData(
              playable: false, statusMSG: "streamLoadFailed");
        }
        if (streamInfo.playable) {
          try {
            songsUrlCacheBox.put(songId, streamInfoJson);
          } catch (_) {}
        } else if (streamInfo.statusMSG == "streamLoadFailed" ||
            streamInfo.statusMSG == "streamBotBlocked") {
          // The retired-client case does NOT throw: StreamProvider.fetch
          // returns playable:false, so the catch blocks above never see it.
          // This is the branch a published client fix actually needs to reach.
          // Deliberately excludes songRequiresPurchase and networkError — a
          // fresh client list fixes neither, and burning the cooldown on them
          // would leave none for the failure it can fix.
          unawaited(ClientConfigService.forceRefresh());
        }
      }

      streamInfo.setQualityIndex(qualityIndex);
      return streamInfo;
    }
  }

  /// Warm [SongsUrlCache] for [songId] without blocking playback.
  void prefetchStreamUrl(String songId) {
    if (songId.isEmpty || _hasDirectStreamUrl(songId)) return;
    unawaited(() async {
      try {
        await checkNGetUrl(songId);
      } catch (_) {}
    }());
  }

  /// Prefetch the next queue item once the current track is playing.
  void prefetchNextInQueue() {
    try {
      if (queue.value.isEmpty) return;
      final next = _getNextSongIndex();
      if (next == currentIndex) return;
      if (next < 0 || next >= queue.value.length) return;
      prefetchStreamUrl(queue.value[next].id);
    } catch (_) {}
  }
}

// for Android Auto
class MediaLibrary {
  static const albumsRootId = 'albums';
  static const songsRootId = 'songs';
  static const favoritesRootId = "LIBFAV";
  static const playlistsRootId = 'playlists';
  static const podcastsRootId = 'riff_podcasts';
  static const podcastProgressId = 'aa_pod_progress';
  static const podcastFeedPrefix = 'aa_pod_feed:';

  /// The podcast queue and the Inbox, first under Podcasts in the car, as
  /// Pocket Casts puts Up Next and AntennaPod its queue and Inbox there.
  static const podcastQueueId = 'aa_pod_queue';
  static const podcastInboxId = 'aa_pod_inbox';

  /// What the car's search, or a voice request, found.
  static const searchResultsId = 'aa_search';

  /// Podcast episode lists Android Auto browsed, by list id: played from
  /// there without fetching the feed again.
  static final autoPodcastLists = <String, List<MediaItem>>{};

  /// Which browsed list an item came from (for cars that don't send the
  /// item's extras back with "play").
  static final _browsedFrom = <String, String>{};

  static String? listIdFor(String mediaId) => _browsedFrom[mediaId];

  /// Lists assembled for the car (podcasts, discovery mixes, Fresh finds)
  /// rather than stored in a Hive box named after the list. Opening one of
  /// these ids as a box creates an empty box, so play them from
  /// [getByRootId].
  static bool isBuiltList(String listId) =>
      listId.startsWith('aa_pod_') ||
      listId.startsWith('riff_mix_') ||
      listId == freshFindsRootId ||
      listId == searchResultsId;

  /// Songs found for [query] (YouTube Music's song search, best match
  /// first), kept as the car-built list [searchResultsId]. Empty when
  /// nothing is asked for or the search fails.
  Future<List<MediaItem>> searchSongs(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty || !Get.isRegistered<MusicServices>()) return const [];
    final List<MediaItem> songs;
    try {
      songs = songsFromSearchResult(await Get.find<MusicServices>()
          .search(q, filter: 'songs', limit: limit));
    } catch (e) {
      printERROR('Android Auto search ($q): $e');
      return const [];
    }
    final tagged = [
      for (final m in songs)
        m.copyWith(playable: true, extras: {
          ...?m.extras,
          'libraryId': searchResultsId,
          'discoverySource': 'android_auto',
        })
    ];
    if (autoPodcastLists.length > 20) autoPodcastLists.clear();
    autoPodcastLists[searchResultsId] = tagged;
    for (final m in tagged) {
      _browsedFrom[m.id] = searchResultsId;
    }
    return tagged;
  }

  /// What "play … on Riff" plays: the songs found for [query], the best
  /// match first; with nothing asked for ("play music on Riff"), your
  /// Favorites, shuffled.
  Future<List<MediaItem>> voiceSearchList(String query,
      {Random? random}) async {
    if (query.trim().isNotEmpty) return searchSongs(query);
    final box = await HiveBoxes.fav();
    return [for (final e in box.values) MediaItemBuilder.fromJson(e)]
      ..shuffle(random);
  }

  /// Android Auto `getChildren`: one page when the car asks for pages,
  /// else the whole list if it's short, or sections ("1–100", …) if not.
  /// Items carry only small extras, so no answer can outgrow the binder.
  Future<List<MediaItem>> browse(
      String id, Map<String, dynamic>? options) async {
    final section = parseAutoSectionId(id);
    final listId = section?.parentId ?? id;
    final all = await getByRootId(listId);
    if (section != null) {
      final start = section.start.clamp(0, all.length);
      final end = (start + autoSectionSize).clamp(0, all.length);
      return _forCar(listId, all.sublist(start, end));
    }
    switch (planAutoBrowse(all.length, options)) {
      case AutoRange(:final start, :final end):
        return _forCar(listId, all.sublist(start, end));
      case AutoSections(:final starts, :final total):
        return [
          for (final start in starts)
            MediaItem(
              id: autoSectionId(id, start),
              title: autoSectionLabel(start, total),
              playable: false,
            )
        ];
    }
  }

  List<MediaItem> _forCar(String listId, List<MediaItem> items) {
    if (_browsedFrom.length > 5000) _browsedFrom.clear();
    return [
      for (final m in items)
        () {
          if (m.playable == true) _browsedFrom[m.id] = listId;
          return m.copyWith(extras: slimAutoExtras(m.extras));
        }()
    ];
  }

  /// Followed podcasts: Continue listening, then each feed show.
  Future<List<MediaItem>> getPodcastNodes() async {
    final nodes = <MediaItem>[
      MediaItem(id: podcastQueueId, title: "queue".tr, playable: false),
      MediaItem(id: podcastInboxId, title: "podcastInbox".tr, playable: false),
      MediaItem(
          id: podcastProgressId,
          title: "continueListening".tr,
          playable: false),
    ];
    try {
      for (final s in PodcastService.subscriptions) {
        final feed = '${s['feedUrl'] ?? ''}';
        if (feed.isEmpty) continue;
        nodes.add(MediaItem(
          id: '$podcastFeedPrefix$feed',
          title: '${s['title'] ?? ''}',
          artUri: Uri.tryParse('${s['artwork'] ?? ''}'),
          playable: false,
        ));
      }
    } catch (_) {}
    return nodes;
  }

  Future<List<MediaItem>> getPodcastList(String id) async {
    List<MediaItem> items = const [];
    try {
      if (id == podcastProgressId) {
        items = PodcastProgressService.inProgress()
            .map(PodcastProgressService.toMediaItem)
            .toList();
      } else if (id == podcastQueueId) {
        items = Get.isRegistered<PodcastQueueController>()
            ? Get.find<PodcastQueueController>().queue.toList()
            : const [];
      } else if (id == podcastInboxId) {
        // The Inbox as the app lists it, newest first, from its last
        // refresh (the car doesn't fetch every feed).
        items = PodcastInboxCounts.waiting().take(100).toList();
      } else if (id.startsWith(podcastFeedPrefix)) {
        final feed = id.substring(podcastFeedPrefix.length);
        final sub = PodcastService.subscriptions.firstWhere(
            (s) => s['feedUrl'] == feed,
            orElse: () => <String, dynamic>{'feedUrl': feed});
        final raw = await PodcastService.episodes(
            feed, '${sub['title'] ?? ''}', '${sub['artwork'] ?? ''}');
        items = [for (final e in raw) podcastEpisodeToMediaItem(e, sub)];
      }
    } catch (e) {
      printERROR('Android Auto podcasts ($id): $e');
    }
    final tagged = [
      for (final m in items)
        m.copyWith(
            playable: true,
            extras: {...?m.extras, 'libraryId': id, 'discoverySource': 'android_auto'})
    ];
    if (autoPodcastLists.length > 20) autoPodcastLists.clear();
    autoPodcastLists[id] = tagged;
    return tagged;
  }

  Future<List<MediaItem>> getByRootId(String id) async {
    if (id == podcastsRootId) return getPodcastNodes();
    if (id == podcastProgressId ||
        id == podcastQueueId ||
        id == podcastInboxId ||
        id.startsWith(podcastFeedPrefix)) {
      return getPodcastList(id);
    }
    switch (id) {
      case AudioService.browsableRootId:
        return Future.value(getRoot());
      case songsRootId:
        return getLibSongs("SongDownloads");
      case favoritesRootId:
        return getLibSongs("LIBFAV");
      case albumsRootId:
        return getAlbums();
      case playlistsRootId:
        return getPlaylists();
      case AudioService.recentRootId:
        return getLibSongs("LIBRP");
      case dailyMixesRootId:
        return getDiscoveryMixes(kind: 'daily_mix');
      case freshFindsRootId:
        return getDiscoveryMixes(kind: 'fresh_finds', asSongs: true);
      default:
        // Individual mix playlists
        if (id.startsWith('riff_mix_')) {
          return getDiscoveryMixTracks(id.substring('riff_mix_'.length));
        }
        return getLibSongs(id);
    }
  }

  Future<List<MediaItem>> getDiscoveryMixes(
      {required String kind, bool asSongs = false}) async {
    try {
      if (!Hive.isBoxOpen('riff_mixes')) {
        await Hive.openBox('riff_mixes');
      }
      final box = Hive.box('riff_mixes');
      final mixes = box.values.whereType<Map>().where((m) => m['kind'] == kind);
      if (asSongs) {
        for (final m in mixes) {
          final tracks = m['tracks'] as List? ?? [];
          return tracks.map((t) {
            final song = MediaItemBuilder.fromJson(t);
            return MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
              artUri: song.artUri,
              extras: {
                ...?song.extras,
                'discoverySource': 'android_auto',
              },
              playable: true,
            );
          }).toList();
        }
        return [];
      }
      return mixes
          .map((m) => MediaItem(
                id: 'riff_mix_${m['id']}',
                title: m['title'] as String? ?? 'Mix',
                playable: false,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<MediaItem>> getDiscoveryMixTracks(String mixId) async {
    try {
      if (!Hive.isBoxOpen('riff_mixes')) {
        await Hive.openBox('riff_mixes');
      }
      final m = Hive.box('riff_mixes').get(mixId);
      if (m is! Map) return [];
      final tracks = m['tracks'] as List? ?? [];
      return tracks.map((t) {
        final song = MediaItemBuilder.fromJson(t);
        return MediaItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
          artUri: song.artUri,
          extras: {
            ...?song.extras,
            'discoverySource': 'android_auto',
          },
          playable: true,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static const dailyMixesRootId = 'riff_daily_mixes';
  static const freshFindsRootId = 'riff_fresh_finds';

  List<MediaItem> getRoot() {
    return [
      MediaItem(
        id: songsRootId,
        title: "songs".tr,
        playable: false,
      ),
      MediaItem(
        id: favoritesRootId,
        title: "favorites".tr,
        playable: false,
      ),
      MediaItem(
        id: albumsRootId,
        title: "albums".tr,
        playable: false,
      ),
      MediaItem(
        id: playlistsRootId,
        title: "playlists".tr,
        playable: false,
      ),
      MediaItem(
        id: podcastsRootId,
        title: "podcasts".tr,
        playable: false,
      ),
      MediaItem(
        id: dailyMixesRootId,
        title: "dailyMixes".tr,
        playable: false,
      ),
      MediaItem(
        id: freshFindsRootId,
        title: "freshFinds".tr,
        playable: false,
      ),
    ];
  }

  Future<List<MediaItem>> getAlbums() async {
    final box = await Hive.openBox("LibraryAlbums");
    final albums =
        box.values.map((item) => Album.fromJson(item).toMediaItem()).toList();
    // Shared box (Hive hands every caller the same instance): never close
    // it here, or the player and other screens using it fail mid-write.
    return albums;
  }

  Future<List<MediaItem>> getPlaylists() async {
    final box = await Hive.openBox("LibraryPlaylists");
    final playlists = [
      ...LibraryPlaylistsController.initPlst.map((e) => e.toMediaItem()),
      ...(box.values
          .map((item) => Playlist.fromJson(item).toMediaItem())
          .toList())
    ];
    // Shared box (Hive hands every caller the same instance): never close
    // it here, or the player and other screens using it fail mid-write.
    return playlists;
  }

  Future<List<MediaItem>> getLibSongs(String libId) async {
    Box<dynamic> box;
    try {
      box = await Hive.openBox(libId);
    } catch (e) {
      box = await Hive.openBox(libId);
    }
    final songs = box.values.toList().map((e) {
      final song = MediaItemBuilder.fromJson(e);
      return MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        artUri: song.artUri,
        extras: {
          ...?song.extras,
          "libraryId": libId,
          "discoverySource": "android_auto",
        },
        playable: true,
      );
    }).toList();

    // Shared box (Hive hands every caller the same instance): never close
    // it here, or the player and other screens using it fail mid-write.

    if (libId == "LIBRP") {
      return songs.reversed.toList();
    }

    return songs;
  }
}
