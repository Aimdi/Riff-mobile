/// Lyrics timing (the player's ⋮ › Lyrics timing): a song's synced lyrics
/// that run ahead of or behind the singing, as LRCLIB's sometimes do, can
/// be moved later or earlier for that song, as in Musixmatch and Poweramp.
library;

import 'package:get/get.dart';
import 'package:hive/hive.dart';

class LyricsTiming {
  LyricsTiming._();

  /// AppPrefs key: song id → how much later its lyrics show, in ms
  /// (negative: earlier). Songs moved back to 0 are dropped.
  static const key = 'lyricsDelayMs';

  /// One tap of Earlier / Later.
  static const stepMs = 500;
  static const maxMs = 10000;

  /// Songs remembered (the oldest change goes first).
  static const keep = 300;

  /// Bumped on every change, for Obx.
  static final rev = 0.obs;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// Read once per box: the lyrics ask on every position tick.
  static Map<String, int>? _cache;
  static Box? _cacheBox;

  static Map<String, int> _delays() {
    final box = _prefs;
    final cached = _cache;
    if (cached != null && identical(box, _cacheBox)) return cached;
    _cacheBox = box;
    final raw = box?.get(key);
    return _cache = {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String && e.value is int)
            e.key as String: e.value as int,
    };
  }

  /// How much later [songId]'s lyrics show, in ms. Inside an Obx it
  /// follows changes.
  static int delayMs(String? songId) {
    rev.value;
    if (songId == null) return 0;
    return _delays()[songId] ?? 0;
  }

  static Future<void> setDelay(String songId, int ms) async {
    final delay = ms.clamp(-maxMs, maxMs);
    final delays = _delays()..remove(songId);
    if (delay != 0) delays[songId] = delay;
    while (delays.length > keep) {
      delays.remove(delays.keys.first);
    }
    await _prefs?.put(key, delays);
    rev.value++;
  }

  /// Moves [songId]'s lyrics [steps] taps later (negative: earlier).
  static Future<void> nudge(String songId, int steps) =>
      setDelay(songId, delayMs(songId) + steps * stepMs);
}

/// Where the lyrics are when the song is at [songMs] and they show
/// [delayMs] later.
int lyricsPositionMs(int songMs, int delayMs) => songMs - delayMs;

/// Where the song is when a lyric timed at [lyricMs] shows (never before
/// the start).
int songPositionForLyricMs(int lyricMs, int delayMs) {
  final ms = lyricMs + delayMs;
  return ms < 0 ? 0 : ms;
}

/// [delayMs] as the seconds shown with Earlier / Later ("0.5", "1.0").
String lyricsDelaySeconds(int delayMs) =>
    (delayMs.abs() / 1000).toStringAsFixed(1);
