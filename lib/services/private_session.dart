/// Spotify's Private session (YouTube Music's Pause history): for six hours,
/// or until turned off, what you play isn't recorded: not in Recently
/// played, your stats and Rewind, the taste your mixes learn from, the
/// Library's Recently played sort, or ListenBrainz.
library;

import 'dart:async';

import 'package:get/get.dart';
import 'package:hive/hive.dart';

class PrivateSession {
  PrivateSession._();

  /// AppPrefs key of when the session ends (ms since the epoch).
  static const key = 'privateSessionUntil';

  static const length = Duration(hours: 6);

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// For the Settings switch: on while a session lasts.
  static final active = RxBool(_end() != null);

  static Timer? _timer;

  /// When the session ends; null when there is none.
  static DateTime? get endsAt => _end();

  static DateTime? _end() {
    final raw = _prefs?.get(key);
    if (raw is! int) return null;
    final end = DateTime.fromMillisecondsSinceEpoch(raw);
    return end.isAfter(DateTime.now()) ? end : null;
  }

  /// Whether what plays now is private. A session that ran out (also while
  /// the app was closed) is over.
  static bool get isActive {
    final on = _end() != null;
    if (active.value != on) active.value = on;
    if (on) _armEnd();
    return on;
  }

  static Future<void> start() async {
    await _prefs?.put(key, DateTime.now().add(length).millisecondsSinceEpoch);
    active.value = true;
    _timer?.cancel();
    _timer = null;
    _armEnd();
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _prefs?.delete(key);
    active.value = false;
  }

  /// Turns the switch off on time while the app is open.
  static void _armEnd() {
    final end = _end();
    if (end == null || _timer != null) return;
    _timer = Timer(end.difference(DateTime.now()), () {
      _timer = null;
      isActive;
    });
  }
}
