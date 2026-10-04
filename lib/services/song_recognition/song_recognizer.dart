import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:permission_handler/permission_handler.dart';

import 'shazam_client.dart';
import 'shazam_signature.dart';

enum RecognitionState { idle, listening, matched, noMatch, error, noPermission }

/// "What's playing?": listens through the mic and asks Shazam, the way
/// Audire does — a signature every few seconds while the clip grows, up to
/// [maxSeconds], stopping at the first confident match.
class SongRecognizer extends GetxController {
  SongRecognizer({ShazamClient? client}) : _client = client ?? ShazamClient();

  final ShazamClient _client;

  static const _mic = MethodChannel('riff/mic');
  static const _pcm = EventChannel('riff/mic/pcm');

  /// Seconds of audio at which to try (Audire tries from 2 s to 12 s).
  static const attemptsAt = [3, 5, 8, 12];
  static const maxSeconds = 12;
  static const _bytesPerSecond = ShazamSignature.sampleRate * 2;
  static const _historyKey = 'recognizedSongs';
  static const _historyMax = 30;

  final state = RecognitionState.idle.obs;
  final result = Rxn<RecognizedSong>();

  /// 0–1 microphone level, for the listening animation.
  final level = 0.0.obs;

  /// Seconds recorded so far.
  final seconds = 0.obs;
  final history = <RecognizedSong>[].obs;

  StreamSubscription<dynamic>? _sub;
  final _audio = BytesBuilder(copy: false);
  int _nextAttempt = 0;
  bool _busy = false;
  int _session = 0;

  @override
  void onInit() {
    super.onInit();
    history.assignAll(loadHistory());
  }

  @override
  void onClose() {
    stop();
    super.onClose();
  }

  static bool get supported => GetPlatform.isAndroid;

  Future<void> start() async {
    await stop();
    result.value = null;
    seconds.value = 0;
    level.value = 0;
    if (!supported) {
      state.value = RecognitionState.error;
      return;
    }
    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      state.value = RecognitionState.noPermission;
      return;
    }
    final session = ++_session;
    _nextAttempt = 0;
    state.value = RecognitionState.listening;
    _sub = _pcm.receiveBroadcastStream().listen(
      (chunk) {
        if (chunk is Uint8List) _onChunk(session, chunk);
      },
      onError: (_) => _finish(session, RecognitionState.error),
    );
    final ok = await _mic.invokeMethod<bool>('start') ?? false;
    if (!ok) await _finish(session, RecognitionState.error);
  }

  /// Stops listening; keeps the last result on screen.
  Future<void> stop() async {
    _session++;
    await _sub?.cancel();
    _sub = null;
    _audio.clear();
    _busy = false;
    if (supported) {
      try {
        await _mic.invokeMethod('stop');
      } catch (_) {}
    }
    if (state.value == RecognitionState.listening) {
      state.value = RecognitionState.idle;
    }
  }

  void _onChunk(int session, Uint8List chunk) {
    if (session != _session) return;
    _audio.add(chunk);
    level.value = _rms(chunk);
    final secs = _audio.length ~/ _bytesPerSecond;
    seconds.value = secs;
    if (_busy || _nextAttempt >= attemptsAt.length) return;
    if (secs >= attemptsAt[_nextAttempt]) {
      _nextAttempt++;
      _attempt(session, secs);
    }
  }

  Future<void> _attempt(int session, int secs) async {
    _busy = true;
    final bytes = _audio.toBytes();
    try {
      final uri = await Isolate.run(() => ShazamSignature.fromPcm16(
          Int16List.view(
              bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 2)));
      if (session != _session) return;
      final song = await _client.identify(uri, secs * 1000);
      if (session != _session) return;
      final last = _nextAttempt >= attemptsAt.length;
      // Like Audire: before the last try, only trust matches with an album
      // (obscure guesses tend to lack one).
      if (song != null && (last || (song.album ?? '').isNotEmpty)) {
        final found = song.copyWith(recognizedAt: DateTime.now());
        result.value = found;
        _remember(found);
        await _finish(session, RecognitionState.matched);
        return;
      }
      if (last) await _finish(session, RecognitionState.noMatch);
    } catch (_) {
      if (session == _session) await _finish(session, RecognitionState.error);
    } finally {
      if (session == _session) _busy = false;
    }
  }

  Future<void> _finish(int session, RecognitionState s) async {
    if (session != _session) return;
    await stop();
    state.value = s;
    if (s == RecognitionState.matched) {
      HapticFeedback.mediumImpact();
    }
  }

  static double _rms(Uint8List chunk) {
    final s = Int16List.view(
        chunk.buffer, chunk.offsetInBytes, chunk.lengthInBytes ~/ 2);
    if (s.isEmpty) return 0;
    var sum = 0.0;
    for (final v in s) {
      sum += v * v;
    }
    final rms = math.sqrt(sum / s.length) / 32768;
    return (rms * 4).clamp(0.0, 1.0);
  }

  // History ------------------------------------------------------------

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static List<RecognizedSong> loadHistory() {
    final raw = _prefs?.get(_historyKey);
    if (raw is! String) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          if (RecognizedSong.fromJson(j) != null) RecognizedSong.fromJson(j)!
      ];
    } catch (_) {
      return [];
    }
  }

  void _remember(RecognizedSong song) {
    final list = [
      song,
      ...history.where((h) => h.title != song.title || h.artist != song.artist),
    ].take(_historyMax).toList();
    history.assignAll(list);
    _prefs?.put(_historyKey, jsonEncode([for (final h in list) h.toJson()]));
  }

  void removeFromHistory(RecognizedSong song) {
    history.remove(song);
    _prefs?.put(_historyKey, jsonEncode([for (final h in history) h.toJson()]));
  }
}
