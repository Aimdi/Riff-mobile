import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

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
import '/services/playlist_mix_service.dart';
import '/services/audiobookshelf_service.dart';
import '/services/cloud_music_service.dart';
import '/services/podcast_progress_service.dart';
import '/services/shuffle_order.dart';
import '/services/stream_service.dart';
import '/ui/screens/Podcasts/podcast_queue_controller.dart';
import '/models/hm_streaming_data.dart';
import '/ui/player/player_controller.dart';
import '/ui/player/radio_continuation.dart';
import '/ui/player/video_mode_controller.dart';
import '../ui/screens/Home/home_screen_controller.dart';
import '/services/background_task.dart';
import '/services/client_config_service.dart';
import '/services/permission_service.dart';
import '/services/play_by_index_skip.dart';
import '/services/play_runtime_error.dart';
import '/ui/player/video_handoff.dart';
import '../utils/helper.dart';
import '/models/media_Item_builder.dart';
import '/utils/songs_url_cache.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '../ui/screens/Library/library_controller.dart';
// ignore: unused_import, implementation_imports, depend_on_referenced_packages
import "package:media_kit/src/player/platform_player.dart" show MPVLogLevel;

Future<AudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationIcon: 'mipmap/ic_launcher_monochrome',
      androidNotificationChannelId: 'com.mycompany.myapp.audio',
      androidNotificationChannelName: 'Harmony Music Notification',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler with GetxServiceMixin {
  // ignore: prefer_typing_uninitialized_variables
  late final _cacheDir;
  late AudioPlayer _player;
  late MediaLibrary _mediaLibrary;
  // ignore: prefer_typing_uninitialized_variables
  dynamic currentIndex;
  int currentShuffleIndex = 0;
  late String? currentSongUrl;
  bool isPlayingUsingLockCachingSource = false;
  bool loopModeEnabled = false;
  bool queueLoopModeEnabled = false;
  bool shuffleModeEnabled = false;
  bool loudnessNormalizationEnabled = false;
  // var networkErrorPause = false;
  bool isSongLoading = true;
  double _baseVolume = 1.0;
  bool _mixTransitionInProgress = false;
  bool _startMutedForMix = false;
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
      JustAudioMediaKit.title = 'Harmony music';
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
    _createCacheDir();
    _addEmptyList();
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenToPlaybackForNextSong();
    _listenForSequenceStateChanges();
    final appPrefsBox = Hive.box("AppPrefs");
    _player
        .setSkipSilenceEnabled(appPrefsBox.get("skipSilenceEnabled") ?? false);
    _player.setSpeed((appPrefsBox.get("playbackSpeed") ?? 1.0).toDouble());
    _player.setPitch((appPrefsBox.get("playbackPitch") ?? 1.0).toDouble());
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
  }

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
      'loudnessMb': box.get("volumeBoostMb") ?? 0,
      'reverb': box.get("reverbPreset") ?? 0,
      'virtualizer': box.get("virtualizer") ?? 0,
    });
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      if (_player.processingState == ProcessingState.ready) {
        final id = mediaItem.value?.id;
        if (id != null) _resetStreamRetryBudget(songId: id);
        _consecutiveResolveFails = 0;
      }
      final playing = _player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
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

      //print("set ${playbackState.value.queueIndex},${event.currentIndex}");
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
        await skipToNext();
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
    required int songIndex,
    required String errorMessage,
    required int errorCode,
  }) async {
    if (songIndex != currentIndex) return false;
    _consecutiveResolveFails++;
    final next = _getNextSongIndex();
    if (shouldSkipAfterUnresolvableTrack(
      consecutiveFails: _consecutiveResolveFails,
      maxConsecutiveFails: _maxConsecutiveResolveFails,
      currentIndex: currentIndex is int ? currentIndex as int : songIndex,
      nextIndex: next,
      loopOne: loopModeEnabled,
    )) {
      printINFO(
          'playByIndex: track will not resolve, skipping to next (fail $_consecutiveResolveFails)');
      await skipToNext();
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
                await skipToNext();
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

      final remainingMs = durationMs - posMs;
      if (remainingMs > 0 && remainingMs < 45000) {
        final id = mediaItem.value?.id;
        if (id != null && _prefetchArmedForId != id) {
          _prefetchArmedForId = id;
          prefetchNextInQueue();
        }
      }

      if (posMs >= (durationMs - playerDurationOffset)) {
        final id = mediaItem.value?.id;
        if (shouldArmEofAdvance(currentId: id, lastArmedId: _eofArmedForId)) {
          await _triggerNext();
        }
      }
    });
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

  Future<void> _triggerNext() async {
    if (_eofAdvanceInProgress) return;
    _eofAdvanceInProgress = true;
    try {
      if (loopModeEnabled) {
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

      await skipToNext();
    } finally {
      _eofAdvanceInProgress = false;
    }
  }

  void _listenForSequenceStateChanges() {
    _player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.effectiveSequence;
      if (sequence == null || sequence.isEmpty) return;
    });
  }

  void _listenForDurationChanges() {
    _player.durationStream.listen((duration) async {
      final currQueue = queue.value;
      if (currentIndex == null || currQueue.isEmpty || duration == null) return;
      final currentSong = queue.value[currentIndex];
      if (currentSong.duration == null || currentIndex == 0) {
        final newMediaItem = currentSong.copyWith(duration: duration);
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
    if (url.contains('/cache') ||
        (Get.find<SettingsScreenController>().cacheSongs.isTrue &&
            url.contains("http"))) {
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
    return AudioSource.uri(
      Uri.tryParse(url)!,
      tag: mediaItem,
    );
  }

  @override
  // ignore: avoid_renaming_method_parameters
  Future<void> removeQueueItem(MediaItem mediaItem_) async {
    if (shuffleModeEnabled) {
      final id = mediaItem_.id;
      final itemIndex = shuffledQueue.indexOf(id);
      if (currentShuffleIndex > itemIndex) {
        currentShuffleIndex -= 1;
      }
      shuffledQueue.remove(id);
    }

    final currentQueue = queue.value;
    final currentSong = mediaItem.value;
    final itemIndex = currentQueue.indexOf(mediaItem_);
    if (currentIndex > itemIndex) {
      currentIndex -= 1;
    }
    currentQueue.remove(mediaItem_);
    queue.add(currentQueue);
    mediaItem.add(currentSong);
  }

  @override
  Future<void> play() async {
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
    // Workaround for network error pause in case of PlayingUsingLockCachingSource
    // if (isPlayingUsingLockCachingSource && networkErrorPause) {
    //   await _player.play();
    //   Future.delayed(const Duration(seconds: 2)).then((value) {
    //     if (_player.playing) {
    //       networkErrorPause = false;
    //     }
    //   });
    //   await _player.play();
    //   return;
    // }
    try {
      await _player.play();
    } catch (e) {
      printERROR('play() player start failed: $e');
      await _handleRuntimePlaybackError(e, position: _player.position);
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    // Notification / OS seeks bypass PlayerController.seek — still nudge video.
    if (Get.isRegistered<PlayerController>()) {
      Get.find<PlayerController>().videoSeekSignal.value++;
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await customAction("playByIndex", {'index': index});
  }

  int _getNextSongIndex() {
    if (shuffleModeEnabled) {
      if (currentShuffleIndex + 1 >= shuffledQueue.length) {
        shuffledQueue.shuffle();
        currentShuffleIndex = 0;
      } else {
        currentShuffleIndex += 1;
      }
      final at = resolveShuffledQueueIndex(
        queueIds: queue.value.map((e) => e.id).toList(),
        shuffledId: shuffledQueue[currentShuffleIndex],
      );
      return isValidQueueIndex(at, queue.value.length) ? at : currentIndex;
    }

    if (queue.value.length > currentIndex + 1) {
      return currentIndex + 1;
    } else if (queueLoopModeEnabled) {
      return 0;
    } else {
      return currentIndex;
    }
  }

  int _getPrevSongIndex() {
    if (shuffleModeEnabled) {
      if (currentShuffleIndex - 1 < 0) {
        shuffledQueue.shuffle();
        currentShuffleIndex = shuffledQueue.length - 1;
      } else {
        currentShuffleIndex -= 1;
      }
      final at = resolveShuffledQueueIndex(
        queueIds: queue.value.map((e) => e.id).toList(),
        shuffledId: shuffledQueue[currentShuffleIndex],
      );
      return isValidQueueIndex(at, queue.value.length) ? at : currentIndex;
    }

    if (currentIndex - 1 >= 0) {
      return currentIndex - 1;
    } else {
      return currentIndex;
    }
  }

  @override
  Future<void> skipToNext() async {
    await skipToNextResult();
  }

  /// True when skip started another track (or radio extend). Last-track pause is false.
  Future<bool> skipToNextResult() async {
    final from = currentIndex is int ? currentIndex as int : -1;
    final index = _getNextSongIndex();
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
    _player.seek(Duration.zero);
    _player.pause();
    return false;
  }

  @override
  Future<void> skipToPrevious() async {
    await skipToPreviousResult();
  }

  /// True when previous restarted the track or started the prior item.
  Future<bool> skipToPreviousResult() async {
    if (shouldRestartOnPrevious(_player.position)) {
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
      case 'dispose':
        await _player.dispose();
        super.stop();
        break;

      case 'setSpeedAndPitch':
        await _player.setSpeed((extras!['speed'] as num).toDouble());
        await _player.setPitch((extras['pitch'] as num).toDouble());
        break;

      case 'setAudioFx':
        _applyAudioFx();
        break;

      case 'skipToNext':
        return skipToNextResult();

      case 'skipToPrevious':
        return skipToPreviousResult();

      case 'playByIndex':
        final songIndex = coercePlayByIndex(extras!['index']);
        if (!isValidQueueIndex(songIndex, queue.value.length)) {
          isSongLoading = false;
          playbackState.add(playbackState.value.copyWith(
            processingState: AudioProcessingState.idle,
          ));
          return false;
        }
        currentIndex = songIndex;
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
        if (resolveFailed) {
          return _onPlayByIndexUnresolvable(
            songIndex: songIndex,
            errorMessage: "streamLoadFailed",
            errorCode: 500,
          );
        }
        if (shouldClearLoadingOnStalePlayByIndex(
          requestedIndex: songIndex,
          currentIndex: currentIndex,
        )) {
          isSongLoading = false;
          return null;
        } else if (!streamInfo.playable) {
          return _onPlayByIndexUnresolvable(
            songIndex: songIndex,
            errorMessage: streamInfo.statusMSG,
            errorCode: 404,
          );
        }
        _consecutiveResolveFails = 0;
        currentSongUrl = currentSong.extras!['url'] = streamInfo.audio!.url;
        playbackState
            .add(playbackState.value.copyWith(queueIndex: currentIndex));
        await _playList.add(_createAudioSource(currentSong));

        isSongLoading = false;
        if (loudnessNormalizationEnabled && GetPlatform.isAndroid) {
          _normalizeVolume(streamInfo.audio!.loudnessDb);
        } else {
          _baseVolume = _player.volume.clamp(0.0, 1.0);
          if (_baseVolume <= 0) _baseVolume = 1.0;
        }
        if (_startMutedForMix) {
          await _player.setVolume(0);
          _startMutedForMix = false;
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
          if (!songsCacheBox.containsKey(song.id) &&
              await File("$_cacheDir/cachedSongs/${song.id}.mp3").exists()) {
            song.extras!['url'] = currentSongUrl;
            song.extras!['date'] = DateTime.now().millisecondsSinceEpoch;
            final dbStreamData = Hive.box("SongsUrlCache").get(song.id);
            final jsonData = MediaItemBuilder.toJson(song);
            jsonData['duration'] = _player.duration!.inSeconds;
            // playbility status and info
            jsonData['streamInfo'] = dbStreamData != null
                ? [
                    true,
                    dbStreamData[(Hive.box('AppPrefs').get('dataSaver') ==
                                true ||
                            Hive.box('AppPrefs').get('streamingQuality') == 0)
                        ? 'lowQualityAudio'
                        : "highQualityAudio"]
                  ]
                : null;
            songsCacheBox.put(song.id, jsonData);
            LibrarySongsController librarySongsController =
                Get.find<LibrarySongsController>();
            if (!librarySongsController.isClosed) {
              librarySongsController.librarySongsList.value =
                  librarySongsController.librarySongsList.toList() + [song];
            }
          }
        }
        break;

      case 'setSourceNPlay':
        final currMed = (extras!['mediaItem'] as MediaItem);
        final futureStreamInfo = checkNGetUrl(currMed.id);
        isSongLoading = true;
        currentIndex = 0;
        await _playList.clear();
        mediaItem.add(currMed);
        queue.add([currMed]);
        late final HMStreamingData streamInfo;
        try {
          streamInfo = await futureStreamInfo;
        } catch (e) {
          printERROR('setSourceNPlay stream resolve failed: $e');
          currentSongUrl = null;
          isSongLoading = false;
          Get.find<PlayerController>().notifyPlayError("streamLoadFailed");
          playbackState.add(playbackState.value
              .copyWith(processingState: AudioProcessingState.error));
          return;
        }
        if (!streamInfo.playable) {
          currentSongUrl = null;
          isSongLoading = false;
          Get.find<PlayerController>().notifyPlayError(streamInfo.statusMSG);
          playbackState.add(playbackState.value
              .copyWith(processingState: AudioProcessingState.error));
          return;
        }
        currentSongUrl = currMed.extras!['url'] = streamInfo.audio!.url;

        await _playList.add(_createAudioSource(currMed));
        isSongLoading = false;

        // Normalize audio
        if (loudnessNormalizationEnabled && GetPlatform.isAndroid) {
          _normalizeVolume(streamInfo.audio!.loudnessDb);
        }

        try {
          await _player.play();
        } catch (e) {
          printERROR('setSourceNPlay player start failed: $e');
          await _handleRuntimePlaybackError(e, position: Duration.zero);
          return false;
        }
        prefetchNextInQueue();
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

      case 'setVolume':
        _baseVolume = (extras!['value'] / 100).clamp(0.0, 1.0);
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
    double loudnessDifference = -5 - currentLoudnessDb;

    // Converted loudness difference to a volume multiplier
    // We use a factor to convert dB difference to a linear scale
    // 10^(difference / 20) converts dB difference to a linear volume factor
    final volumeAdjustment = pow(10.0, loudnessDifference / 20.0);
    printINFO(
        "loudness:$currentLoudnessDb Normalized volume: $volumeAdjustment");
    _baseVolume = volumeAdjustment.toDouble().clamp(0, 1.0);
    _player.setVolume(_baseVolume);
  }

  Future<void> saveSessionData() async {
    final currQueue = queue.value;
    // Persist whenever the queue is non-empty so Home can offer
    // "Continue listening" even if auto-restore is turned off.
    if (currQueue.isEmpty) {
      return;
    }
    final queueData =
        currQueue.map((e) => MediaItemBuilder.toJson(e)).toList();
    final currIndex = currentIndex ?? 0;
    final position = _player.position.inMilliseconds;
    final prevSessionData = await Hive.openBox("prevSessionData");
    await prevSessionData.clear();
    await prevSessionData.putAll(
        {"queue": queueData, "position": position, "index": currIndex});
    await prevSessionData.close();
    printINFO("Saved session data");
  }

  /// Android Auto
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    return _mediaLibrary.getByRootId(parentMediaId);
  }

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
    return Stream.fromFuture(
            _mediaLibrary.getByRootId(parentMediaId).then((items) => items))
        .map((_) => <String, dynamic>{})
        .shareValue();
  }

  // only for Android Auto
  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    customEvent.add({
      'eventType': 'playFromMediaId',
      'songId': mediaId,
      'libraryId': extras!['libraryId'],
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
    await _player.stop();
    return super.stop();
  }

// Work around used [useNewInstanceOfExplode = false] to Fix Connection closed before full header was received issue
  Future<HMStreamingData> checkNGetUrl(String songId,
      {bool generateNewUrl = false, bool offlineReplacementUrl = false}) async {
    printINFO("Requested id : $songId");
    // Podcast episodes, Audiobookshelf tracks and Cloud (self-hosted music
    // server) songs carry a direct stream URL — no YouTube stream resolution
    // needed (same pattern Lissen uses for ABS).
    if (songId.startsWith("podcast_") ||
        songId.startsWith("abs_") ||
        songId.startsWith("cloud_") ||
        songId.startsWith("slsk_")) {
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
    final songDownloadsBox = Hive.box("SongDownloads");
    if (!offlineReplacementUrl &&
        (await Hive.openBox("SongsCache")).containsKey(songId)) {
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
      final qualityIndex = (() {
        final dataSaver = Hive.box('AppPrefs').get('dataSaver') == true;
        if (dataSaver) return 0; // Low
        return Hive.box('AppPrefs').get('streamingQuality') ?? 1;
      })();
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

      streamInfo.setQualityIndex(qualityIndex as int);
      return streamInfo;
    }
  }

  /// Warm [SongsUrlCache] for [songId] without blocking playback.
  void prefetchStreamUrl(String songId) {
    if (songId.isEmpty ||
        songId.startsWith('podcast_') ||
        songId.startsWith('abs_') ||
        songId.startsWith('cloud_') ||
        songId.startsWith('slsk_')) {
      return;
    }
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

class UrlError extends Error {
  String message() => 'Unable to fetch url';
}

// for Android Auto
class MediaLibrary {
  static const albumsRootId = 'albums';
  static const songsRootId = 'songs';
  static const favoritesRootId = "LIBFAV";
  static const playlistsRootId = 'playlists';

  Future<List<MediaItem>> getByRootId(String id) async {
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
    await box.close();
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
    await box.close();
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

    if (!libId.contains("SongDownloads")) {
      await box.close();
    }

    if (libId == "LIBRP") {
      return songs.reversed.toList();
    }

    return songs;
  }
}
