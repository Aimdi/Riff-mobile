import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Engine behind video mode. Both implementations play the video-only
/// stream together with the music pipeline's audio stream in ONE player,
/// so A/V sync is the engine's job.
abstract class VideoEngine {
  /// Short id stored in settings (`exo` / `mpv`).
  String get id;

  Future<void> open({
    required String videoUrl,
    String? audioUrl,
    required Duration start,
    required double speed,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> stop();
  Future<void> dispose();

  bool get isPlaying;
  Duration get position;

  Stream<Duration> get positionStream;
  Stream<Duration> get bufferStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<double> get aspectStream;
  Stream<void> get completedStream;

  /// Fatal playback errors (stream rejected, decoder failure).
  Stream<String> get errorStream;

  /// The video frames; only valid after [open].
  Widget buildView();
}

/// ExoPlayer (media3) engine in `RiffVideoPlayer.kt`: WizeStream / NewPipe
/// style playback with a YouTube-aware data source, rendered to a texture.
class ExoVideoEngine implements VideoEngine {
  ExoVideoEngine() {
    _subscribe();
  }

  void _subscribe() {
    _sub = _events.receiveBroadcastStream().listen(_onEvent, onError: (e) {
      _error.add('$e');
    });
  }

  static const _methods = MethodChannel('riff/video');
  static const _events = EventChannel('riff/video/events');

  StreamSubscription? _sub;
  int? _textureId;
  bool _playing = false;
  bool _ended = false;
  Duration _position = Duration.zero;

  final _positionCtl = StreamController<Duration>.broadcast();
  final _buffer = StreamController<Duration>.broadcast();
  final _playingCtl = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _aspect = StreamController<double>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _error = StreamController<String>.broadcast();

  @override
  String get id => 'exo';

  @override
  bool get isPlaying => _playing;

  @override
  Duration get position => _position;

  @override
  Stream<Duration> get positionStream => _positionCtl.stream;
  @override
  Stream<Duration> get bufferStream => _buffer.stream;
  @override
  Stream<bool> get playingStream => _playingCtl.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;
  @override
  Stream<double> get aspectStream => _aspect.stream;
  @override
  Stream<void> get completedStream => _completed.stream;
  @override
  Stream<String> get errorStream => _error.stream;

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    switch (raw['event']) {
      case 'position':
        _position = Duration(milliseconds: _int(raw['positionMs']));
        _positionCtl.add(_position);
        _buffer.add(Duration(milliseconds: _int(raw['bufferedMs'])));
      case 'state':
        final playing = raw['playing'] == true;
        if (playing != _playing) {
          _playing = playing;
          _playingCtl.add(playing);
        }
        _buffering.add(raw['buffering'] == true);
        final ended = raw['ended'] == true;
        if (ended && !_ended) _completed.add(null);
        _ended = ended;
      case 'size':
        final w = _int(raw['width']);
        final h = _int(raw['height']);
        final ratio = (raw['pixelRatio'] as num?)?.toDouble() ?? 1.0;
        if (w > 0 && h > 0) _aspect.add(w * ratio / h);
      case 'error':
        _error.add('${raw['code'] ?? ''} ${raw['message'] ?? ''}'.trim());
    }
  }

  static int _int(dynamic v) => v is num ? v.toInt() : 0;

  @override
  Future<void> open({
    required String videoUrl,
    String? audioUrl,
    required Duration start,
    required double speed,
  }) async {
    // Re-subscribe: when the activity is recreated the native player (and
    // its event handler) is new, and only a fresh listen reaches it.
    await _sub?.cancel();
    _subscribe();
    // Always ask: the native side recreates the texture if the activity
    // (and with it the player) was rebuilt.
    _textureId = await _methods.invokeMethod<int>('create');
    _ended = false;
    _position = start;
    await _methods.invokeMethod('load', {
      'videoUrl': videoUrl,
      'audioUrl': audioUrl,
      'startMs': start.inMilliseconds,
      'play': false,
      'speed': speed,
    });
  }

  /// Audio session of the native player (to bind audio effects to video
  /// mode), or null before [open].
  Future<int?> audioSessionId() =>
      _methods.invokeMethod<int>('audioSessionId');

  @override
  Future<void> play() => _methods.invokeMethod('play');

  @override
  Future<void> pause() => _methods.invokeMethod('pause');

  @override
  Future<void> seek(Duration position) {
    _position = position;
    return _methods
        .invokeMethod('seekTo', {'positionMs': position.inMilliseconds});
  }

  @override
  Future<void> setSpeed(double speed) =>
      _methods.invokeMethod('setSpeed', {'speed': speed});

  @override
  Future<void> stop() async {
    _playing = false;
    await _methods.invokeMethod('stop');
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _textureId = null;
    try {
      await _methods.invokeMethod('dispose');
    } catch (_) {}
    for (final c in [
      _positionCtl,
      _buffer,
      _playingCtl,
      _buffering,
      _aspect,
      _completed,
      _error,
    ]) {
      await c.close();
    }
  }

  @override
  Widget buildView() {
    final id = _textureId;
    if (id == null) return const SizedBox.shrink();
    return Texture(textureId: id, filterQuality: FilterQuality.medium);
  }
}

/// Which engine video mode should use: the saved [preference] when that
/// engine exists in this build, else whichever one does (null = none).
String? chooseVideoEngine({
  required String? preference,
  required bool exoAvailable,
  required bool mpvAvailable,
}) {
  if (preference == 'mpv' && mpvAvailable) return 'mpv';
  if (exoAvailable) return 'exo';
  if (mpvAvailable) return 'mpv';
  return null;
}
