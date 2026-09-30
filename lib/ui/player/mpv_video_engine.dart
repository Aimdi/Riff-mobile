import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '/utils/helper.dart';
import 'video_engine.dart';

/// Classic mpv (media_kit) engine: the video-only stream plays with the
/// audio stream attached via `audio-add`. Absent from the lite APK.
class MpvVideoEngine implements VideoEngine {
  MpvVideoEngine()
      : _player = Player(
            configuration: const PlayerConfiguration(title: 'Riff video')) {
    _controller = VideoController(_player);
  }

  final Player _player;
  late final VideoController _controller;
  final _aspect = StreamController<double>.broadcast();
  final _error = StreamController<String>.broadcast();
  final List<StreamSubscription> _subs = [];
  Timer? _silenceGuard;

  @override
  String get id => 'mpv';

  @override
  bool get isPlaying => _player.state.playing;

  @override
  Duration get position => _player.state.position;

  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration> get bufferStream => _player.stream.buffer;
  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;
  @override
  Stream<double> get aspectStream => _aspect.stream;
  @override
  Stream<void> get completedStream =>
      _player.stream.completed.where((done) => done).map((_) {});
  @override
  Stream<String> get errorStream => _error.stream;

  @override
  Future<void> open({
    required String videoUrl,
    String? audioUrl,
    required Duration start,
    required double speed,
  }) async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs
      ..clear()
      ..add(_player.stream.videoParams.listen((params) {
        final w = params.dw ?? 0;
        final h = params.dh ?? 0;
        if (w > 0 && h > 0) _aspect.add(w / h);
      }));
    await _player.open(Media(videoUrl, start: start), play: false);
    if (audioUrl != null) {
      // Attach the audio track to the SAME engine (mpv audio-add): this is
      // what makes A/V sync the engine's job instead of the app's.
      await _player.setAudioTrack(AudioTrack.uri(audioUrl));
      _armSilenceGuard(audioUrl);
    }
    await _player.setRate(speed);
  }

  /// The video-only stream has no audio of its own; if `audio-add` failed,
  /// playback would run silently. Retry once, then report an error so video
  /// mode hands back to the audio pipeline.
  void _armSilenceGuard(String audioUrl, {bool retried = false}) {
    _silenceGuard?.cancel();
    _silenceGuard = Timer(const Duration(seconds: 3), () async {
      final hasRealAudio = _player.state.tracks.audio
          .any((t) => t.id != 'auto' && t.id != 'no' && t.id.isNotEmpty);
      if (hasRealAudio) return;
      if (!retried) {
        printERROR('Video mode: audio track missing — retrying attach');
        try {
          await _player.setAudioTrack(AudioTrack.uri(audioUrl));
        } catch (e) {
          printERROR('Video mode: audio re-attach failed: $e');
        }
        _armSilenceGuard(audioUrl, retried: true);
        return;
      }
      _error.add('audio track missing');
    });
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setRate(speed);

  @override
  Future<void> stop() async {
    _silenceGuard?.cancel();
    await _player.pause();
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    _silenceGuard?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
    await _aspect.close();
    await _error.close();
  }

  @override
  Widget buildView() => Video(
        controller: _controller,
        controls: NoVideoControls,
        fill: Colors.black,
      );
}
