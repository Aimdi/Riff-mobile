/// Fade between songs (Spotify's and Apple Music's Crossfade): the end of
/// a song fades out and the song after it fades in. Riff plays one track
/// at a time, so the two don't overlap. Off by default; music only.
library;

import 'dart:math';

import 'package:get/get.dart';
import 'package:hive/hive.dart';

class SongFade {
  SongFade._();

  /// AppPrefs key: the fade in seconds, 0 for off.
  static const key = 'songFadeSeconds';

  /// What Settings offers.
  static const choices = [0, 3, 5, 8, 12];

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// For the Settings picker.
  static final selected = RxInt(seconds);

  static int get seconds {
    final raw = _prefs?.get(key);
    return raw is int && choices.contains(raw) ? raw : 0;
  }

  static Future<void> set(int seconds) async {
    final value = choices.contains(seconds) ? seconds : 0;
    await _prefs?.put(key, value);
    selected.value = value;
  }
}

/// How long a song [lengthMs] long fades for, with the fade set to
/// [seconds]; songs shorter than three fades don't fade.
int songFadeMs({required int seconds, required int lengthMs}) {
  if (seconds <= 0) return 0;
  final ms = seconds * 1000;
  return lengthMs >= 3 * ms ? ms : 0;
}

/// Volume factor (0–1) at [posMs] in a song [lengthMs] long that fades in
/// over its first [inMs] and out over its last [outMs]; null where it plays
/// at its full level.
double? songFadeFactor(
    {required int posMs, required int lengthMs, int inMs = 0, int outMs = 0}) {
  double? factor;
  if (inMs > 0 && posMs < inMs) factor = max(posMs, 0) / inMs;
  final left = lengthMs - posMs;
  if (outMs > 0 && left < outMs) {
    final out = max(left, 0) / outMs;
    factor = factor == null ? out : min(factor, out);
  }
  return factor;
}
