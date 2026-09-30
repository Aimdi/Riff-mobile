import 'dart:async';

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '/models/hm_streaming_data.dart';
import '/services/client_config_service.dart';
import '/services/stream_service.dart';
import '/services/utils.dart';
import '/services/video_stream_service.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '/utils/media_item_video.dart';
import 'mpv_video_engine.dart';
import 'player_controller.dart';
import 'video_engine.dart';
import 'video_handoff.dart';

/// Video mode: plays the current YouTube track as real video, the way a
/// video player does it — ONE engine is given the video-only stream plus
/// the same audio-only stream the music pipeline uses, and schedules video
/// frames against the audio clock. There is no app-level drift correction
/// because two engines never run at once, so nothing can drift.
///
/// The engine is ExoPlayer (`RiffVideoPlayer.kt`, NewPipe / WizeStream
/// style) by default, or mpv when chosen in Settings; if ExoPlayer can't
/// start a stream, mpv gets one try before giving up.
///
/// The audio pipeline (just_audio/ExoPlayer) is paused while video mode is
/// active and takes over again — at the video's position — when the pane
/// closes, the song changes, or the app goes to background (music keeps
/// playing with working notification controls).
class VideoModeController extends GetxController with WidgetsBindingObserver {
  /// Set at startup when the mpv library loaded. False in the lite
  /// (audio-only) APK, where the mpv engine is stripped.
  static bool engineAvailable = false;

  /// The native ExoPlayer engine ships in every Android build.
  static bool get nativeEngineAvailable => GetPlatform.isAndroid;

  /// The video pane is showing and an engine owns playback.
  final isActive = false.obs;
  final isLoading = false.obs;
  final isVideoPlaying = false.obs;

  /// Width/height of the loaded video (for aspect ratio); 16:9 fallback.
  final videoAspect = (16 / 9).obs;

  VideoEngine? _engine;
  String? _activeSongId;
  final List<StreamSubscription> _subs = [];
  Worker? _songWorker;

  /// Engine currently holding the video frames (null when inactive).
  VideoEngine? get engine => isActive.value ? _engine : null;

  PlayerController get _pc => Get.find<PlayerController>();

  SettingsScreenController? get _settings =>
      Get.isRegistered<SettingsScreenController>()
          ? Get.find<SettingsScreenController>()
          : null;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _songWorker = ever(_pc.currentSong, (MediaItem? song) {
      // The audio pipeline moved to another item under an active video —
      // close stale video; the surface widget re-enables for the new song.
      if (isActive.value && song != null && song.id != _activeSongId) {
        // Resume audio so a slow/failed re-enable cannot leave silence.
        disable(resume: true);
      }
    });
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _songWorker?.dispose();
    _unwire();
    _engine?.dispose();
    _engine = null;
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Screen off / app backgrounded → hand playback back to the audio
    // pipeline so music continues in background with a live notification.
    if (state == AppLifecycleState.paused && isActive.value) {
      disable();
    }
  }

  /// Video mode exists for YouTube videos (and YT-sourced podcast
  /// episodes) on Android.
  bool availableFor(MediaItem? song) {
    if (!engineAvailable && !nativeEngineAvailable) return false;
    if (song == null || !GetPlatform.isAndroid) return false;
    return song.canShowPlayerVideo;
  }

  String? get _preferredEngine => chooseVideoEngine(
        preference: _settings?.videoEngine.value,
        exoAvailable: nativeEngineAvailable,
        mpvAvailable: engineAvailable,
      );

  /// Reuse the engine of the right kind, or swap it for a fresh one.
  Future<VideoEngine> _engineFor(String id) async {
    final current = _engine;
    if (current != null && current.id == id) return current;
    _unwire();
    await current?.dispose();
    final created = id == 'mpv' ? MpvVideoEngine() : ExoVideoEngine();
    _engine = created;
    return created;
  }

  /// Switch the current track to video. Returns false when no video (or
  /// no audio url) could be resolved — the caller shows the error state.
  ///
  /// [wasPlayingBeforeHandoff] covers a prior `disable(resume: false)` that
  /// already paused a playing session — early failures must still resume.
  Future<bool> enable({bool wasPlayingBeforeHandoff = false}) async {
    final song = _pc.currentSong.value;
    if (isLoading.value) return false;
    if (!availableFor(song)) {
      _resumeAudioIfVideoEnableFailed(
        wasPlayingBeforeAttempt: wasPlayingBeforeHandoff,
      );
      return false;
    }
    if (isActive.value && song!.id == _activeSongId) return true;
    isLoading.value = true;
    final wasPlaying = wasPlayingBeforeHandoff ||
        _pc.buttonState.value == PlayButtonState.playing ||
        isVideoPlaying.value;
    try {
      final quality = _settings?.videoQuality.value ?? VideoQuality.high;
      final video =
          await VideoStreamService.resolve(song!.id, quality: quality);
      if (video == null) {
        _resumeAudioIfVideoEnableFailed(wasPlayingBeforeAttempt: wasPlaying);
        return false;
      }
      // Same audio stream the music pipeline plays — quality unchanged.
      final audioUrl = video.hasAudio ? null : await _audioUrlFor(song.id);
      if (!video.hasAudio && audioUrl == null) {
        _resumeAudioIfVideoEnableFailed(wasPlayingBeforeAttempt: wasPlaying);
        return false;
      }
      if (_pc.currentSong.value?.id != song.id) {
        _resumeAudioIfVideoEnableFailed(wasPlayingBeforeAttempt: wasPlaying);
        return false;
      }

      final preferred = _preferredEngine;
      if (preferred == null) {
        _resumeAudioIfVideoEnableFailed(wasPlayingBeforeAttempt: wasPlaying);
        return false;
      }
      final position = _pc.progressBarStatus.value.current;
      final speed = _settings?.playbackSpeed.value ?? 1.0;
      videoAspect.value = video.aspectRatio;
      VideoEngine engine;
      try {
        engine = await _engineFor(preferred);
        await engine.open(
          videoUrl: video.url,
          audioUrl: audioUrl,
          start: position,
          speed: speed,
        );
      } catch (e) {
        // ExoPlayer refused the stream: give mpv one try when it's bundled.
        if (preferred != 'exo' || !engineAvailable) rethrow;
        printERROR('Video mode: ExoPlayer failed ($e) — trying mpv');
        engine = await _engineFor('mpv');
        await engine.open(
          videoUrl: video.url,
          audioUrl: audioUrl,
          start: position,
          speed: speed,
        );
      }
      _wire(engine);
      _activeSongId = song.id;
      isActive.value = true;
      // Pause audio only now that video can take over — otherwise the
      // play button sits on a spinner in silence while the stream resolves.
      if (wasPlaying) {
        _pc.pause();
        await engine.play();
      }
      return true;
    } catch (e) {
      printERROR('Video mode enable failed: $e');
      await disable(resume: false);
      _resumeAudioIfVideoEnableFailed(wasPlayingBeforeAttempt: wasPlaying);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  void _resumeAudioIfVideoEnableFailed({
    required bool wasPlayingBeforeAttempt,
  }) {
    if (shouldResumeAudioAfterVideoEnableFailed(
      videoActive: isActive.value,
      wasPlayingBeforeAttempt: wasPlayingBeforeAttempt,
    )) {
      _pc.play();
    }
  }

  /// Close the pane. With [resume], the audio pipeline continues from the
  /// video's position (a single handoff seek — engines never overlap).
  Future<void> disable({bool resume = true}) async {
    if (!isActive.value) return;
    final e = _engine;
    var wasPlaying = false;
    var pos = Duration.zero;
    if (e != null) {
      wasPlaying = e.isPlaying;
      pos = e.position;
    }
    isActive.value = false; // before seek/play so transport routes to audio
    _unwire();
    _activeSongId = null;
    _setVideoPlaying(false);
    try {
      await e?.stop();
    } catch (err) {
      printERROR('Video mode stop failed: $err');
    }
    if (resume) {
      _pc.seek(pos);
      if (wasPlaying) {
        _pc.play();
      } else {
        _pc.buttonState.value = PlayButtonState.paused;
      }
    }
  }

  /// Close only if this [songId] owns the active session (used by the
  /// surface's dispose so a new song's surface isn't torn down).
  Future<void> disableIfActiveFor(String songId, {bool resume = true}) async {
    if (isActive.value && _activeSongId == songId) {
      await disable(resume: resume);
    }
  }

  /// Transport while video mode is active (routed from PlayerController).
  void playPauseVideo() {
    final e = _engine;
    if (e == null) return;
    e.isPlaying ? e.pause() : e.play();
  }

  void seekVideo(Duration position) => _engine?.seek(position);

  /// Keep the video at the same speed as the audio pipeline (podcasts at
  /// 1.5× shouldn't drop to 1× when video turns on).
  void setVideoSpeed(double speed) {
    if (isActive.value) _engine?.setSpeed(speed);
  }

  void _setVideoPlaying(bool playing) {
    isVideoPlaying.value = playing;
    // Watching video: keep the screen on. When it stops, leave the lock to
    // the "keep screen awake" setting (PlayerController) if that's on.
    try {
      if (playing) {
        WakelockPlus.enable();
      } else if (_settings?.keepScreenAwake.isTrue != true) {
        WakelockPlus.disable();
      }
    } catch (_) {}
  }

  void _wire(VideoEngine e) {
    _unwire();
    _subs.add(e.positionStream.listen((pos) {
      if (!isActive.value) return;
      _pc.progressBarStatus.update((val) {
        val!.current = pos;
      });
    }));
    _subs.add(e.bufferStream.listen((buf) {
      if (!isActive.value) return;
      _pc.progressBarStatus.update((val) {
        val!.buffered = buf;
      });
    }));
    _subs.add(e.playingStream.listen((playing) {
      if (!isActive.value) return;
      _setVideoPlaying(playing);
      _pc.buttonState.value =
          playing ? PlayButtonState.playing : PlayButtonState.paused;
    }));
    _subs.add(e.bufferingStream.listen((buffering) {
      if (!isActive.value) return;
      // Don't swap the transport to a spinner. Video streams rebuffer
      // often; the playing stream already drives play/pause.
      if (!buffering && isVideoPlaying.value) {
        _pc.buttonState.value = PlayButtonState.playing;
      }
    }));
    _subs.add(e.aspectStream.listen((aspect) {
      if (aspect > 0) videoAspect.value = aspect;
    }));
    _subs.add(e.completedStream.listen((_) async {
      if (!isActive.value) return;
      // Video finished — hand back and advance the queue naturally.
      await disable(resume: false);
      final ok = await _pc.next();
      if (!ok) _pc.notifyPlayError('streamPlaybackFailed');
    }));
    _subs.add(e.errorStream.listen((message) async {
      if (!isActive.value) return;
      printERROR('Video engine ${e.id} error: $message — back to audio');
      await disable(); // resumes the audio pipeline at the same position
    }));
  }

  void _unwire() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  /// The exact audio url the music pipeline would play right now: cached
  /// resolved stream if fresh, else a fresh resolve at the user's
  /// streaming-quality setting.
  Future<String?> _audioUrlFor(String songId) async {
    final quality = Hive.box('AppPrefs').get('streamingQuality') ?? 1;
    try {
      if (Hive.isBoxOpen('SongsUrlCache')) {
        final cached = Hive.box('SongsUrlCache').get(songId);
        if (cached is Map && cached['playable'] == true) {
          final data = HMStreamingData.fromJson(cached)
            ..setQualityIndex(quality is int ? quality : 1);
          final url = data.audio?.url;
          if (url != null && !isExpired(url: url)) return url;
        }
      }
    } catch (e) {
      printERROR('Video mode: url cache read failed: $e');
    }
    try {
      final res = await StreamProvider.fetch(songId,
          clientConfigJson: ClientConfigService.currentJson);
      if (res.playable) {
        return (quality == 0 ? res.lowQualityAudio : res.highestQualityAudio)
            ?.url;
      }
    } catch (e) {
      printERROR('Video mode: audio resolve failed: $e');
    }
    return null;
  }
}
