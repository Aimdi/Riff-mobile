import 'dart:async';
import 'package:flutter_lyric/lyric_ui/ui_netease.dart';
import 'package:hive/hive.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';

import '../../models/playling_from.dart';
import '../../services/downloader.dart';
import '../../services/discovery/discovery_service.dart';
import '../../services/discovery/discovery_types.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '../widgets/snackbar.dart';
import '/services/listenbrainz_service.dart';
import '/services/stats_service.dart';
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
import '/services/sponsorblock_service.dart';
import '/services/podcast_service.dart';
import '/services/podcast_progress_service.dart';

class PlayerController extends GetxController
    with GetSingleTickerProviderStateMixin {
  final _audioHandler = Get.find<AudioHandler>();
  final _musicServices = Get.find<MusicServices>();
  final currentQueue = <MediaItem>[].obs;

  final playerPaneOpacity = (1.0).obs;
  final isPlayerpanelTopVisible = true.obs;
  final isPanelGTHOpened = false.obs;
  /// True when the main player panel is nearly fully open. Muted in-player
  /// video pauses while this is false so decoding stops behind the mini player.
  final isPlayerPanelOpen = false.obs;
  /// Bumped on every seek so [PlayerVideoSurface] can hard-sync immediately.
  final videoSeekSignal = 0.obs;
  final playerPanelMinHeight = 0.0.obs;
  bool initFlagForPlayer = true;
  final isQueueReorderingInProcess = false.obs;
  PanelController playerPanelController = PanelController();
  PanelController queuePanelController = PanelController();
  AnimationController? gesturePlayerStateAnimationController;
  Animation<double>? gesturePlayerStateAnimation;
  bool isRadioModeOn = false;
  String? radioContinuationParam;
  dynamic radioInitiatorItem;
  Timer? sleepTimer;
  int timerDuration = 0;
  final timerDurationLeft = 0.obs;
  final isSleepTimerActive = false.obs;
  final isSleepEndOfSongActive = false.obs;
  final volume = 100.obs;

  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero, current: Duration.zero, total: Duration.zero)
      .obs;

  final currentSongIndex = (0).obs;
  final isFirstSong = true;
  final isLastSong = true;
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

  // track whether wakelock is currently enabled to avoid repeated calls
  bool _wakelockActive = false;

  var _newSongFlag = true;
  final isCurrentSongBuffered = false.obs;

  /// SponsorBlock segments for the current video id.
  List<SponsorBlockSegment> _sponsorSegments = const [];
  String? _sponsorVideoId;
  String? _lastSkippedSegmentUuid;
  bool _sponsorSeekInFlight = false;
  final sponsorBlockActiveCategory = RxnString();

  /// Podcasting 2.0 chapters for the current podcast episode (ad auto-skip).
  List<PodcastChapter> _chapters = const [];
  String? _chaptersForSongId;
  bool _chapterSeekInFlight = false;
  // True while playback is inside an ad chapter (drives the "Skip ad" chip).
  final inAdChapter = false.obs;
  bool get hasChapters => _chapters.isNotEmpty;

  bool get podcastAutoSkipAds =>
      Hive.box('AppPrefs').get('podcastAutoSkipAds', defaultValue: true);
  set podcastAutoSkipAds(bool v) =>
      Hive.box('AppPrefs').put('podcastAutoSkipAds', v);

  // Podcast resume: persist position periodically and auto-seek to the saved
  // position when a partially-played episode starts.
  int _lastProgressSaveMs = 0;
  String? _pendingResumeId;
  int _pendingResumeMs = 0;

  late StreamSubscription<bool> keyboardSubscription;

  @override
  onInit() {
    _init();
    super.onInit();
  }

  @override
  void onReady() {
    if (GetPlatform.isWindows) {
      Get.put(WindowsAudioService());
    }
    _restorePrevSession();
    super.onReady();
  }

  void _init() async {
    //_createAppDocDir();
    _listenForChangesInPlayerState();
    _listenForChangesInPosition();
    _listenForChangesInBufferedPosition();
    _listenForChangesInDuration();
    _listenForPlaylistChange();
    _listenForKeyboardActivity();
    _setInitLyricsMode();
    final appPrefs = Hive.box("AppPrefs");
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
    lyricsMode.value = Hive.box("AppPrefs").get("lyricsMode") ?? 0;
  }

  void panellistener(double x) {
    if (x >= 0 && x <= 0.2) {
      playerPaneOpacity.value = 1 - (x * 5);
      isPlayerpanelTopVisible.value = true;
    } else if (x > 0.2) {
      isPlayerpanelTopVisible.value = false;
    }

    if (x > 0.6) {
      isPanelGTHOpened.value = true;
    } else {
      isPanelGTHOpened.value = false;
    }

    // Hysteresis near fully-open so the last bit of the gesture doesn't thrash.
    final open = isPlayerPanelOpen.value ? x >= 0.85 : x >= 0.95;
    if (isPlayerPanelOpen.value != open) {
      isPlayerPanelOpen.value = open;
    }
  }

  void _listenForKeyboardActivity() {
    var keyboardVisibilityController = KeyboardVisibilityController();
    keyboardSubscription =
        keyboardVisibilityController.onChange.listen((bool visible) {
      visible ? playerPanelController.hide() : playerPanelController.show();
    });
  }

  void _listenForChangesInPlayerState() {
    _audioHandler.playbackState.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;
      if (processingState == AudioProcessingState.loading) {
        buttonState.value = PlayButtonState.loading;
      } else if (processingState == AudioProcessingState.buffering) {
        buttonState.value = PlayButtonState.loading;
      } else if (!isPlaying || processingState == AudioProcessingState.error) {
        buttonState.value = PlayButtonState.paused;
      } else if (processingState != AudioProcessingState.completed) {
        buttonState.value = PlayButtonState.playing;
      } else {
        _audioHandler.seek(Duration.zero);
        _audioHandler.pause();
      }

      final settings = Get.find<SettingsScreenController>();
      // Keep the screen awake whenever playback is active and the setting is enabled.
      final shouldEnable = settings.keepScreenAwake.isTrue && isPlaying;
      _setWakelock(shouldEnable);
    });
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

  void _listenForChangesInPosition() {
    AudioService.position.listen((position) {
      final oldState = progressBarStatus.value;
      if (isSleepEndOfSongActive.isTrue) {
        timerDurationLeft.value = oldState.total.inSeconds - position.inSeconds;
        if (timerDurationLeft.value == 1) {
          pause();
          cancelSleepTimer();
        }
      }
      progressBarStatus.update((val) {
        val!.current = position;
        val.buffered = oldState.buffered;
        val.total = oldState.total;
      });
      // Feed skip/listen fraction tracking (notification & headset skips too).
      if (Get.isRegistered<DiscoveryService>()) {
        Get.find<DiscoveryService>().onPositionTick(position.inMilliseconds);
      }
      _maybeSkipSponsorBlock(position);
      _maybeSkipAdChapter(position);
      _handlePodcastProgress(position);
    });
  }

  void _handlePodcastProgress(Duration position) {
    final song = currentSong.value;
    if (song == null || !PodcastProgressService.isPodcastItem(song)) return;
    final total = progressBarStatus.value.total;

    // Auto-resume once: a partially-played episode that just started near 0.
    if (_pendingResumeId == song.id &&
        _pendingResumeMs > 5000 &&
        position.inMilliseconds < 4000) {
      final target = Duration(milliseconds: _pendingResumeMs);
      _pendingResumeId = null;
      if (total <= Duration.zero ||
          target < total - const Duration(seconds: 10)) {
        seek(target);
        return;
      }
    }

    // Persist position at most every 5s.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastProgressSaveMs >= 5000) {
      _lastProgressSaveMs = nowMs;
      PodcastProgressService.save(song, position, total, nowMs: nowMs);
    }
  }

  Future<void> _loadChaptersFor(MediaItem item) async {
    _chaptersForSongId = item.id;
    _chapters = const [];
    inAdChapter.value = false;
    final url = item.extras?['chaptersUrl'] as String?;
    if (url == null || url.isEmpty) return;
    final chs = await PodcastService.chapters(url);
    if (_chaptersForSongId == item.id) _chapters = chs;
  }

  /// The chapter covering [sec], if any (chapters are start-only + sorted).
  PodcastChapter? _chapterAt(double sec) {
    PodcastChapter? current;
    for (final c in _chapters) {
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
    final idx = _chapters.indexOf(c);
    if (idx >= 0 && idx + 1 < _chapters.length) {
      return Duration(
          milliseconds: (_chapters[idx + 1].startSec * 1000).round());
    }
    return null;
  }

  void _maybeSkipAdChapter(Duration position) {
    if (_chapters.isEmpty) {
      if (inAdChapter.isTrue) inAdChapter.value = false;
      return;
    }
    final sec = position.inMilliseconds / 1000.0;
    final current = _chapterAt(sec);
    final isAd = current?.isAd ?? false;
    if (inAdChapter.value != isAd) inAdChapter.value = isAd;
    if (!isAd || !podcastAutoSkipAds || _chapterSeekInFlight) return;
    final target = _endOfChapter(current!);
    if (target == null) return;
    final total = progressBarStatus.value.total;
    if (total > Duration.zero &&
        target >= total - const Duration(milliseconds: 400)) {
      return;
    }
    _chapterSeekInFlight = true;
    printINFO('Ad chapter skip "${current.title}" → ${target.inSeconds}s');
    seek(target);
    Future.delayed(const Duration(milliseconds: 350),
        () => _chapterSeekInFlight = false);
  }

  /// Manual "Skip ad": jump past the current ad chapter if in one, else jump
  /// forward 30s (universal fallback for feeds without chapters).
  void skipAd() {
    final sec = progressBarStatus.value.current.inMilliseconds / 1000.0;
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
    sponsorBlockActiveCategory.value = null;
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
    if (active == null) {
      if (sponsorBlockActiveCategory.value != null) {
        sponsorBlockActiveCategory.value = null;
      }
      return;
    }
    if (active.uuid == _lastSkippedSegmentUuid) return;

    final target = sb.seekTargetIfInSegment(_sponsorSegments, sec);
    if (target == null) return;

    // Don't skip past the end of the track — just leave it to natural end.
    final total = progressBarStatus.value.total;
    if (total > Duration.zero && target >= total - const Duration(milliseconds: 400)) {
      return;
    }

    _lastSkippedSegmentUuid = active.uuid;
    _sponsorSeekInFlight = true;
    sponsorBlockActiveCategory.value = active.category;
    printINFO(
        'SponsorBlock skip ${active.category} ${active.start.toStringAsFixed(1)}s → ${active.end.toStringAsFixed(1)}s');
    seek(target);
    Future.delayed(const Duration(milliseconds: 350), () {
      _sponsorSeekInFlight = false;
    });
  }

  void _listenForChangesInBufferedPosition() {
    _audioHandler.playbackState.listen((playbackState) {
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
      progressBarStatus.update((val) {
        val!.buffered = playbackState.bufferedPosition;
        val.current = oldState.current;
        val.total = oldState.total;
      });
    });
  }

  void _listenForChangesInDuration() {
    _audioHandler.mediaItem.listen((mediaItem) async {
      final oldState = progressBarStatus.value;
      progressBarStatus.update((val) {
        val!.total = mediaItem?.duration ?? Duration.zero;
        val.current = oldState.current;
        val.buffered = oldState.buffered;
      });
      if (mediaItem != null) {
        printINFO(mediaItem.title);
        _newSongFlag = true;
        isCurrentSongBuffered.value = false;
        // Capture position before switching so DiscoveryService can score the skip.
        final posMs = progressBarStatus.value.current.inMilliseconds;
        // Persist the outgoing podcast episode's position before switching.
        PodcastProgressService.save(
            currentSong.value,
            Duration(milliseconds: posMs),
            progressBarStatus.value.total,
            nowMs: DateTime.now().millisecondsSinceEpoch);
        currentSong.value = mediaItem;
        // Arm auto-resume for the incoming podcast episode (either backend).
        if (PodcastProgressService.isPodcastItem(mediaItem)) {
          _pendingResumeId = mediaItem.id;
          _pendingResumeMs =
              PodcastProgressService.positionMs(mediaItem.id) ?? 0;
        } else {
          _pendingResumeId = null;
        }
        currentSongIndex.value = currentQueue
            .indexWhere((element) => element.id == currentSong.value!.id);
        // Fire-and-forget SponsorBlock load for this video id.
        unawaited(_loadSponsorBlockFor(mediaItem.id));
        // Podcast chapters (ad auto-skip) for this episode.
        unawaited(_loadChaptersFor(mediaItem));
        await _checkFav();
        await _addToRP(currentSong.value!);
        StatsService.recordPlay(currentSong.value!);
        ListenBrainzService.submitListen(currentSong.value!);
        if (Get.isRegistered<DiscoveryService>()) {
          await Get.find<DiscoveryService>()
              .onMediaChanged(mediaItem, positionMs: posMs);
        }
        if (isRadioModeOn && (currentSong.value!.id == currentQueue.last.id)) {
          await _addRadioContinuation(radioInitiatorItem!);
        }
        lyrics.value = {"synced": "", "plainLyrics": ""};
        showLyricsflag.value = false;
        if (isDesktopLyricsDialogOpen) {
          Navigator.pop(Get.context!);
        }

        // reset player visible state when player is in gesture mode
        if (Get.find<SettingsScreenController>().playerUi.value == 1) {
          gesturePlayerVisibleState.value = 2;
        }
      }
    });
  }

  void _listenForPlaylistChange() {
    _audioHandler.queue.listen((queue) {
      currentQueue.value = queue;
      currentQueue.refresh();
    });
  }

  Future<void> _restorePrevSession() async {
    final restrorePrevSessionEnabled =
        Hive.box("AppPrefs").get("restrorePlaybackSession") ?? false;
    if (restrorePrevSessionEnabled) {
      final prevSessionData = await Hive.openBox("prevSessionData");
      if (prevSessionData.keys.isNotEmpty) {
        final songList = (prevSessionData.get("queue") as List)
            .map((e) => MediaItemBuilder.fromJson(e))
            .toList();
        final int currentIndex = prevSessionData.get("index");
        final int position = prevSessionData.get("position");
        prevSessionData.close();
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

  void _listenForCustomEvents() {
    _audioHandler.customEvent.listen((event) {
      if (event['eventType'] == 'playFromMediaId') {
        _playViaAndroidAuto(event['songId'], event['libraryId']);
      }
    });
  }

  ///pushSongToPlaylist method clear previous song queue, plays the tapped song and push related
  ///songs into Queue
  Future<void> pushSongToQueue(MediaItem? mediaItem,
      {String? playlistid, bool radio = false}) async {
    /// update playing from value
    playinfrom.value = PlaylingFrom(
        type: PlaylingFromType.SELECTION,
        name: radio ? "randomRadio".tr : "randomSelection".tr);

    /// set global radio mode flag
    isRadioModeOn = radio;

    Future.delayed(
      Duration.zero,
      () async {
        List<MediaItem> tracks;
        if (radio &&
            mediaItem != null &&
            Get.isRegistered<DiscoveryService>()) {
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
              videoId: mediaItem?.id ?? "",
              radio: radio,
              playlistId: playlistid);
          radioContinuationParam = content['additionalParamsForNext'];
          final src =
              radio ? DiscoverySource.radio : DiscoverySource.userClick;
          tracks = Get.isRegistered<DiscoveryService>()
              ? DiscoveryService.tagAll(
                  List<MediaItem>.from(content['tracks']), src)
              : List<MediaItem>.from(content['tracks']);
        }
        await _audioHandler.updateQueue(tracks);
        if (isShuffleModeEnabled.isTrue) {
          await _audioHandler.customAction("shuffleCmd", {"index": 0});
        }

        // added here to broadcast current mediaitem via Audio Service as list is updated
        // if radio is started on current playing song
        if (radio && (currentSong.value?.id == mediaItem?.id)) {
          _audioHandler
              .customAction("upadateMediaItemInAudioService", {"index": 0});
        }
      },
    ).then((value) async {
      if (playlistid != null) {
        _playerPanelCheck();
        await _audioHandler.customAction("playByIndex", {"index": 0});
      } else {
        if (Hive.box("AppPrefs").get("discoverContentType") == "BOLI") {
          Get.find<HomeScreenController>()
              .changeDiscoverContent("BOLI", songId: mediaItem!.id);
        }
      }
    });

    if (playlistid != null ||
        (radio && (currentSong.value?.id == mediaItem?.id))) {
      return;
    }

    //currentSong.value = mediaItem;
    _playerPanelCheck();
    final seed = mediaItem == null
        ? null
        : (Get.isRegistered<DiscoveryService>()
            ? DiscoveryService.withSource(
                mediaItem,
                radio ? DiscoverySource.radio : DiscoverySource.userClick)
            : mediaItem);
    await _audioHandler
        .customAction("setSourceNPlay", {'mediaItem': seed});

    // disable queue loop mode when radio is started
    if (radio &&
        isQueueLoopModeEnabled.isTrue &&
        isShuffleModeEnabled.isFalse) {
      toggleQueueLoopMode();
    }
  }

  Future<void> playPlayListSong(List<MediaItem> mediaItems, int index,
      {PlaylingFrom? playfrom}) async {
    isRadioModeOn = false;
    //open player pane,set current song and push first song into playing list,

    /// update playing from value
    playinfrom.value =
        playfrom ?? PlaylingFrom(type: PlaylingFromType.SELECTION);

    //for changing home content based on last interation
    Future.delayed(const Duration(seconds: 3), () {
      if (Hive.box("AppPrefs").get("discoverContentType") == "BOLI") {
        Get.find<HomeScreenController>()
            .changeDiscoverContent("BOLI", songId: mediaItems[index].id);
      }
    });

    _playerPanelCheck();
    final tagged = Get.isRegistered<DiscoveryService>()
        ? mediaItems
            .map((m) => m.extras?['discoverySource'] != null
                ? m
                : DiscoveryService.withSource(m, DiscoverySource.userClick))
            .toList()
        : mediaItems;
    await _audioHandler.updateQueue(tagged);
    if (isShuffleModeEnabled.value) {
      await _audioHandler.customAction("shuffleCmd", {"index": index});
    }
    await _audioHandler.customAction("playByIndex", {"index": index});
  }

  Future<void> startRadio(MediaItem? mediaItem, {String? playlistid}) async {
    radioInitiatorItem = mediaItem ?? playlistid;
    await pushSongToQueue(mediaItem, playlistid: playlistid, radio: true);
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
  Future<void> enqueueSong(MediaItem mediaItem) async {
    if (currentQueue.isEmpty) {
      await playPlayListSong([mediaItem], 0);
      return;
    }
    //check if song is available in queue and if not add it to queue
    if (!currentQueue.contains(mediaItem)) {
      _audioHandler.addQueueItem(mediaItem);
    }
  }

  ///enqueueSongList method add song List to current queue
  Future<void> enqueueSongList(List<MediaItem> mediaItems) async {
    if (currentQueue.isEmpty) {
      await playPlayListSong(mediaItems, 0);
      return;
    }
    final listToEnqueue = <MediaItem>[];
    for (MediaItem item in mediaItems) {
      if (!currentQueue.contains(item)) {
        listToEnqueue.add(item);
      }
    }
    _audioHandler.addQueueItems(listToEnqueue);
  }

  void _playViaAndroidAuto(String songId, String libraryId) {
    Hive.openBox(libraryId).then((box) {
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
      playPlayListSong(songList, songIndex);
      if (libraryId != "SongDownloads") {
        box.close();
      }
    });
  }

  void playNext(MediaItem song) {
    if (currentQueue.isEmpty) {
      enqueueSong(song);
      return;
    }
    int index = -1;
    for (int i = 0; i < currentQueue.length; i++) {
      if (song.id == (currentQueue[i]).id) {
        index = i;
        break;
      }
    }
    final currentIndx = currentSongIndex.value;
    if (index == currentIndx) {
      return;
    }
    if (index != -1) {
      if (currentQueue.length == 1 ||
          (currentQueue.length == 2 && index == 1)) {
        return;
      }
      onReorder(index, currentSongIndex.value + 1);
    } else {
      //Will add song just below the current song
      (currentIndx == currentQueue.length - 1)
          ? enqueueSong(song)
          : _audioHandler.customAction("addPlayNextItem", {"mediaItem": song});
    }
  }

  void _playerPanelCheck({bool restoreSession = false}) {
    final isWideScreen = Get.size.width > 800;
    final autoOpenPlayer = Hive.box("AppPrefs").get("autoOpenPlayer") ?? true;
    if ((!isWideScreen && autoOpenPlayer && playerPanelController.isAttached) &&
        !restoreSession) {
      playerPanelController.open();
    }

    if (initFlagForPlayer) {
      final miniPlayerHeight = isWideScreen ? 105.0 : 75.0;
      if (Get.find<SettingsScreenController>().isBottomNavBarEnabled.isFalse ||
          getCurrentRouteName() != '/homeScreen') {
        playerPanelMinHeight.value =
            miniPlayerHeight + Get.mediaQuery.viewPadding.bottom;
      } else {
        playerPanelMinHeight.value = miniPlayerHeight;
      }
      initFlagForPlayer = false;
    }
  }

  void removeFromQueue(MediaItem song) {
    _audioHandler.removeQueueItem(song);
  }

  void clearQueue() {
    _audioHandler.customAction("clearQueue");
  }

  void shuffleQueue() {
    _audioHandler.customAction("shuffleQueue");
  }

  Future<void> toggleShuffleMode() async {
    final shuffleModeEnabled = isShuffleModeEnabled.value;
    shuffleModeEnabled
        ? _audioHandler.setShuffleMode(AudioServiceShuffleMode.none)
        : _audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
    isShuffleModeEnabled.value = !shuffleModeEnabled;
    await Hive.box("AppPrefs").put("isShuffleModeEnabled", !shuffleModeEnabled);
    // restrict queue loop mode when shuffle mode is enabled
    if (isShuffleModeEnabled.isTrue && isQueueLoopModeEnabled.isFalse) {
      isQueueLoopModeEnabled.value = true;
    } else if (isShuffleModeEnabled.isFalse) {
      isQueueLoopModeEnabled.value =
          Hive.box("AppPrefs").get("queueLoopModeEnabled", defaultValue: false);
    }
  }

  void onReorder(int oldIndex, int newIndex) {
    _audioHandler.customAction(
        "reorderQueue", {"oldIndex": oldIndex, "newIndex": newIndex});
  }

  void onReorderStart(int index) {
    isQueueReorderingInProcess.value = true;
  }

  void onReorderEnd(int index) {
    isQueueReorderingInProcess.value = false;
  }

  void play() {
    _audioHandler.play();
  }

  void pause() {
    _audioHandler.pause();
  }

  void playPause() {
    if (initFlagForPlayer) return;
    _audioHandler.playbackState.value.playing ? pause() : play();
    // for gesture player
    if (Get.find<SettingsScreenController>().playerUi.value == 1) {
      gesturePlayerVisibleState.value =
          _audioHandler.playbackState.value.playing ? 0 : 1;
      gesturePlayerStateAnimationController?.reset();
      gesturePlayerStateAnimationController?.forward();
    }
  }

  void prev() {
    _audioHandler.skipToPrevious();
  }

  Future<void> next() async {
    await _audioHandler.skipToNext();
  }

  void seek(Duration position) {
    _audioHandler.seek(position);
    videoSeekSignal.value++;
  }

  /// True when the currently playing item is a podcast episode (from the
  /// Podcasts section) — drives the podcast player transport.
  bool get isCurrentSongPodcast {
    final s = currentSong.value;
    if (s == null) return false;
    return (s.extras?['isPodcast'] == true) ||
        s.id.startsWith('podcast_');
  }

  /// True when the current item is a YouTube *video* (not a YTM song).
  /// Drives the in-player 16:9 video surface and video-only actions.
  bool get isCurrentSongVideo {
    final s = currentSong.value;
    if (s == null) return false;
    return s.isYoutubeVideo;
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
    _audioHandler.customAction("playByIndex", {"index": index});
  }

  void toggleSkipSilence(bool enable) {
    _audioHandler.customAction("toggleSkipSilence", {"enable": enable});
  }

  void setSpeedAndPitch({required double speed, required double pitch}) {
    _audioHandler
        .customAction("setSpeedAndPitch", {"speed": speed, "pitch": pitch});
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
    await Hive.box("AppPrefs")
        .put("isLoopModeEnabled", isLoopModeEnabled.value);
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
    await Hive.box("AppPrefs")
        .put("queueLoopModeEnabled", isQueueLoopModeEnabled.value);
  }

  Future<void> setVolume(int value) async {
    _audioHandler.customAction("setVolume", {"value": value});
    volume.value = value;
    await Hive.box("AppPrefs").put("volume", value);
  }

  Future<void> mute() async {
    int? vol;
    if (volume.value != 0) {
      vol = 0;
    } else {
      vol = await Hive.box("AppPrefs").get("volume", defaultValue: 10);
      if (vol == 0) {
        vol = 10;
        await Hive.box("AppPrefs").put("volume", vol);
      }
    }
    _audioHandler.customAction("setVolume", {"value": vol!});
    volume.value = vol;
  }

  Future<void> _checkFav() async {
    isCurrentSongFav.value =
        (await Hive.openBox("LIBFAV")).containsKey(currentSong.value!.id);
  }

  Future<void> toggleFavourite() async {
    final currMediaItem = currentSong.value!;
    final box = await Hive.openBox("LIBFAV");
    final adding = isCurrentSongFav.isFalse;
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
    isCurrentSongFav.value = !isCurrentSongFav.value;
    if (Get.isRegistered<DiscoveryService>()) {
      Get.find<DiscoveryService>()
          .onFavorite(currMediaItem, add: adding);
    }
    if (Get.find<SettingsScreenController>()
            .autoDownloadFavoriteSongEnabled
            .isTrue &&
        isCurrentSongFav.isTrue) {
      Get.find<Downloader>().download(currMediaItem);
    }
  }

  /// Insert ~5 similar tracks after the current song (sideways exploration).
  Future<void> moreLikeThisPlayNext([MediaItem? seed]) async {
    final song = seed ?? currentSong.value;
    if (song == null || !Get.isRegistered<DiscoveryService>()) return;
    final list =
        await Get.find<DiscoveryService>().moreLikeThisPlayNext(song, limit: 5);
    // Insert in reverse so first similar ends up right after current.
    for (final s in list.reversed) {
      playNext(s);
    }
  }

  // ignore: prefer_typing_uninitialized_variables
  var recentItem;

  /// This function is used to add a mediaItem/Song to Recently played playlist
  Future<void> _addToRP(MediaItem mediaItem) async {
    if (recentItem != mediaItem) {
      final box = await Hive.openBox("LIBRP");
      String? removedSongId;
      if (box.keys.length >= 30) {
        removedSongId = box.getAt(0)['videoId'];
        box.deleteAt(0);
      }
      final valuesCopy = box.values.toList();
      for (int i = valuesCopy.length - 1; i >= 0; i--) {
        if (valuesCopy[i]['videoId'] == mediaItem.id) {
          box.deleteAt(i);
        }
      }
      box.add(MediaItemBuilder.toJson(mediaItem));
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
    if ((lyrics["synced"].isEmpty && lyrics['plainLyrics'].isEmpty) &&
        showLyricsflag.value) {
      isLyricsLoading.value = true;
      try {
        final Map<String, dynamic>? lyricsR =
            await SyncedLyricsService.getSyncedLyrics(
                currentSong.value!, progressBarStatus.value.total.inSeconds);
        if (lyricsR != null) {
          lyrics.value = lyricsR;
          isLyricsLoading.value = false;
          return;
        }
        final related = await _musicServices.getWatchPlaylist(
            videoId: currentSong.value!.id, onlyRelated: true);
        final relatedLyricsId = related['lyrics'];
        if (relatedLyricsId != null) {
          final lyrics_ = await _musicServices.getLyrics(relatedLyricsId);
          lyrics.value = {"synced": "", "plainLyrics": lyrics_};
        } else {
          lyrics.value = {"synced": "", "plainLyrics": "NA"};
        }
      } catch (e) {
        lyrics.value = {"synced": "", "plainLyrics": "NA"};
      }
      isLyricsLoading.value = false;
    }
  }

  void changeLyricsMode(int? val) {
    Hive.box("AppPrefs").put("lyricsMode", val);
    lyricsMode.value = val!;
  }

  void sleepEndOfSong() {
    isSleepTimerActive.value = true;
    isSleepEndOfSongActive.value = true;
  }

  void startSleepTimer(int minutes) {
    timerDuration = minutes * 60;
    isSleepTimerActive.value = true;
    if ((sleepTimer != null && !sleepTimer!.isActive) || sleepTimer == null) {
      sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (timer.tick == timerDuration) {
          sleepTimer?.cancel();
          pause();
          isSleepTimerActive.value = false;
          timerDuration = 0;
          timerDurationLeft.value = 0;
        } else {
          timerDurationLeft.value = timerDuration - timer.tick;
        }
      });
    }
  }

  void addFiveMinutes() {
    timerDuration += 300;
  }

  void cancelSleepTimer() {
    if (isSleepEndOfSongActive.isTrue) {
      isSleepEndOfSongActive.value = false;
    }
    sleepTimer?.cancel();
    isSleepTimerActive.value = false;
    timerDuration = 0;
    timerDurationLeft.value = 0;
  }

  Future<void> openEqualizer() async {
    await _audioHandler.customAction("openEqualizer");
  }

  /// Called from audio handler in case audio is not playable
  /// or returned streamInfo null due to network error
  void notifyPlayError(String message) {
    ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
        Get.context!, message == "networkError" ? message.tr : message,
        size: SanckBarSize.MEDIUM));
  }

  @override
  void dispose() {
    _audioHandler.customAction('dispose');
    keyboardSubscription.cancel();
    scrollController.dispose();
    gesturePlayerStateAnimationController?.dispose();
    sleepTimer?.cancel();
    if (GetPlatform.isWindows) {
      Get.delete<WindowsAudioService>();
    }
    // ensure wakelock disabled when player controller disposed
    try {
      _setWakelock(false);
    } catch (e) {
      printERROR(e);
    }
    super.dispose();
  }
}

enum PlayButtonState { paused, playing, loading }
