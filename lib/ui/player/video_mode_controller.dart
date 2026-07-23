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
import '/utils/helper.dart';
import 'player_controller.dart';

/// Video mode: plays the current YouTube track as real video, the way a
/// video player does it — ONE mpv engine is given the video-only stream
/// plus the same audio-only stream the music pipeline uses, and schedules
/// video frames against the audio clock. There is no app-level "sync"
/// between two players, so nothing can drift.
///
/// The audio pipeline (just_audio/ExoPlayer) is paused while video mode is
/// active and takes over again — at the video's position — when the pane
/// is closed, the song changes, or the app goes to background (so music
/// keeps playing with working notification controls).
class VideoModeController extends GetxController with WidgetsBindingObserver {
  /// Set at startup when the mpv library loaded. False in the lite
  /// (audio-only) APK, where the engine is stripped — video mode's UI
  /// hides entirely.
  static bool engineAvailable = false;

  /// Video pane is showing and mpv owns playback.
  final isActive = false.obs;
  final isLoading = false.obs;
  final isVideoPlaying = false.obs;

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
      // close the pane rather than showing a stale video.
      if (isActive.value && song != null && song.id != _activeSongId) {
        disable(resume: false);
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
    // pipeline so music continues in background.
    if (state == AppLifecycleState.paused && isActive.value) {
      disable();
    }
  }

  /// Video mode exists for YouTube tracks only — podcasts, Audiobookshelf,
  /// Cloud (self-hosted) and RSS items have no YouTube video counterpart.
  bool availableFor(MediaItem? song) {
    if (!engineAvailable) return false;
    if (song == null || !GetPlatform.isAndroid) return false;
    final id = song.id;
    return !id.startsWith('podcast_') &&
        !id.startsWith('abs_') &&
        !id.startsWith('cloud_') &&
        song.extras?['isPodcast'] != true;
  }

  /// Switch the current track to video. Returns false when no video (or no
  /// audio url) could be resolved — the caller shows the error.
  Future<bool> enable() async {
    final song = _pc.currentSong.value;
    if (!availableFor(song) || isLoading.value || isActive.value) {
      return false;
    }
    isLoading.value = true;
    try {
      final video = await VideoStreamService.bestVideoOnly(song!.id);
      if (video == null) return false;
      // Same audio stream the music pipeline plays — quality unchanged.
      final audioUrl = await _audioUrlFor(song.id);
      if (audioUrl == null) return false;

      final wasPlaying = _pc.buttonState.value == PlayButtonState.playing;
      final position = _pc.progressBarStatus.value.current;
      _pc.pause();

      _player ??= Player(
          configuration: const PlayerConfiguration(title: 'Riff video'));
      videoController ??= VideoController(_player!);
      final p = _player!;
      await p.open(Media(video.url, start: position), play: false);
      // Attach the audio track to the SAME engine (mpv audio-add): this is
      // what makes A/V sync the engine's job instead of the app's.
      await p.setAudioTrack(AudioTrack.uri(audioUrl));
      _wire(p);
      _activeSongId = song.id;
      isActive.value = true;
      if (wasPlaying) {
        await p.play();
      }
      return true;
    } catch (e) {
      printERROR('Video mode enable failed: $e');
      await disable(resume: false);
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Close the pane. With [resume], the audio pipeline continues from the
  /// video's position (single handoff seek — the engines never run
  /// together).
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

  Future<void> toggle() async =>
      isActive.value ? await disable() : await enable();

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
      if (buffering) _pc.buttonState.value = PlayButtonState.loading;
    }));
    _subs.add(p.stream.completed.listen((done) async {
      if (!done || !isActive.value) return;
      // Video finished — hand back and advance the queue naturally.
      await disable(resume: false);
      _pc.next();
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
