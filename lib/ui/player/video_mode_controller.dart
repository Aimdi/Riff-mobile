import 'dart:async';

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '/models/hm_streaming_data.dart';
import '/services/client_config_service.dart';
import '/services/stream_service.dart';
import '/services/utils.dart';
import '/services/video_stream_service.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '/utils/media_item_video.dart';
import 'player_controller.dart';
import 'video_handoff.dart';

/// Video mode: plays the current YouTube track as real video, the way a
/// video player does it — ONE mpv engine is given the video-only stream
/// plus the same audio-only stream the music pipeline uses, and schedules
/// video frames against the audio clock. There is no app-level drift
/// correction (rate nudges / periodic seeks) because two engines never run
/// at once, so nothing can drift.
///
/// The audio pipeline (just_audio/ExoPlayer) is paused while video mode is
/// active and takes over again — at the video's position — when the pane
/// closes, the song changes, or the app goes to background (music keeps
/// playing with working notification controls).
class VideoModeController extends GetxController with WidgetsBindingObserver {
  /// Set at startup when the mpv library loaded. False in the lite
  /// (audio-only) APK, where the engine is stripped — video mode's UI
  /// then hides entirely.
  static bool engineAvailable = false;

  /// The video pane is showing and mpv owns playback.
  final isActive = false.obs;
  final isLoading = false.obs;
  final isVideoPlaying = false.obs;

  /// Width/height of the loaded video (for aspect ratio); 16:9 fallback.
  final videoAspect = (16 / 9).obs;

  Player? _player;
  VideoController? videoController;
  String? _activeSongId;
  final List<StreamSubscription> _subs = [];
  Worker? _songWorker;

  PlayerController get _pc => Get.find<PlayerController>();

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
    _player?.dispose();
    _player = null;
    videoController = null;
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
  /// episodes) on Android builds that bundle the engine.
  bool availableFor(MediaItem? song) {
    if (!engineAvailable) return false;
    if (song == null || !GetPlatform.isAndroid) return false;
    return song.canShowPlayerVideo;
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
      final quality = Get.isRegistered<SettingsScreenController>()
          ? Get.find<SettingsScreenController>().videoQuality.value
          : VideoQuality.high;
      final video = await VideoStreamService.resolve(song!.id,
          quality: quality);
      if (video == null) {
        _resumeAudioIfVideoEnableFailed(wasPlayingBeforeAttempt: wasPlaying);
        return false;
      }
      // Same audio stream the music pipeline plays — quality unchanged.
      final audioUrl = await _audioUrlFor(song.id);
      if (audioUrl == null) {
        _resumeAudioIfVideoEnableFailed(wasPlayingBeforeAttempt: wasPlaying);
        return false;
      }
      if (_pc.currentSong.value?.id != song.id) {
        _resumeAudioIfVideoEnableFailed(wasPlayingBeforeAttempt: wasPlaying);
        return false;
      }

      final position = _pc.progressBarStatus.value.current;
      _player ??= Player(
          configuration: const PlayerConfiguration(title: 'Riff video'));
      videoController ??= VideoController(_player!);
      final p = _player!;
      videoAspect.value = video.aspectRatio;
      await p.open(Media(video.url, start: position), play: false);
      // Attach the audio track to the SAME engine (mpv audio-add): this is
      // what makes A/V sync the engine's job instead of the app's.
      await p.setAudioTrack(AudioTrack.uri(audioUrl));
      _wire(p);
      // Silence guard: the video-only stream carries NO audio of its own.
      // If the external track failed to attach, playback would "run"
      // silently — retry once, then hand back to the audio pipeline.
      _armSilenceGuard(p, song.id, audioUrl);
      _activeSongId = song.id;
      isActive.value = true;
      // Pause audio only now that video can take over — otherwise the
      // play button sits on a spinner in silence while the stream resolves.
      if (wasPlaying) {
        _pc.pause();
        await p.play();
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
    final p = _player;
    var wasPlaying = false;
    var pos = Duration.zero;
    if (p != null) {
      wasPlaying = p.state.playing;
      pos = p.state.position;
    }
    isActive.value = false; // before seek/play so transport routes to audio
    _unwire();
    _activeSongId = null;
    isVideoPlaying.value = false;
    try {
      await p?.pause();
      await p?.stop();
    } catch (e) {
      printERROR('Video mode stop failed: $e');
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

  /// The video-only stream has no audio track; if `audio-add` failed the
  /// engine would advance silently. Verify a real audio track exists once
  /// playback is underway; retry the attach once, then bail back to the
  /// audio pipeline so the user never sits in silent "playback".
  void _armSilenceGuard(Player p, String songId, String audioUrl,
      {bool retried = false}) {
    Future.delayed(const Duration(seconds: 3), () async {
      if (!isActive.value || _activeSongId != songId || _player != p) return;
      final hasRealAudio = p.state.tracks.audio
          .any((t) => t.id != 'auto' && t.id != 'no' && t.id.isNotEmpty);
      if (hasRealAudio) return;
      if (!retried) {
        printERROR('Video mode: audio track missing — retrying attach');
        try {
          await p.setAudioTrack(AudioTrack.uri(audioUrl));
        } catch (e) {
          printERROR('Video mode: audio re-attach failed: $e');
        }
        _armSilenceGuard(p, songId, audioUrl, retried: true);
        return;
      }
      printERROR(
          'Video mode: no audio track after retry — handing back to audio');
      await disable(); // resumes the audio pipeline at the same position
    });
  }

  /// Transport while video mode is active (routed from PlayerController).
  void playPauseVideo() => _player?.playOrPause();

  void seekVideo(Duration position) => _player?.seek(position);

  void _wire(Player p) {
    _unwire();
    _subs.add(p.stream.position.listen((pos) {
      if (!isActive.value) return;
      _pc.progressBarStatus.update((val) {
        val!.current = pos;
      });
    }));
    _subs.add(p.stream.buffer.listen((buf) {
      if (!isActive.value) return;
      _pc.progressBarStatus.update((val) {
        val!.buffered = buf;
      });
    }));
    _subs.add(p.stream.playing.listen((playing) {
      if (!isActive.value) return;
      isVideoPlaying.value = playing;
      _pc.buttonState.value =
          playing ? PlayButtonState.playing : PlayButtonState.paused;
    }));
    _subs.add(p.stream.buffering.listen((buffering) {
      if (!isActive.value) return;
      // Don't swap the transport to a spinner. Video streams rebuffer
      // often; the playing stream already drives play/pause.
      if (!buffering && isVideoPlaying.value) {
        _pc.buttonState.value = PlayButtonState.playing;
      }
    }));
    _subs.add(p.stream.videoParams.listen((params) {
      final w = params.dw ?? 0;
      final h = params.dh ?? 0;
      if (w > 0 && h > 0) videoAspect.value = w / h;
    }));
    _subs.add(p.stream.completed.listen((done) async {
      if (!done || !isActive.value) return;
      // Video finished — hand back and advance the queue naturally.
      await disable(resume: false);
      final ok = await _pc.next();
      if (!ok) _pc.notifyPlayError('streamPlaybackFailed');
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
