import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Audiobook playback settings. Books keep their own speed, apart from
/// music's, as in Audible, Spotify and Pocket Casts, and skip by the same
/// fixed lengths in the player, on the lock screen and from a headset.
class AudiobookPlayback {
  AudiobookPlayback._();

  static const speedKey = 'audiobookSpeed';
  static const skipBackSec = 10;
  static const skipForwardSec = 30;

  /// Bumped when the speed changes, for Obx.
  static final rev = 0.obs;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static double get speed => audiobookSpeedFrom(
      stored: _prefs?.get(speedKey), appSpeed: _prefs?.get('playbackSpeed'));

  static Future<void> setSpeed(double speed) async {
    await _prefs?.put(speedKey, speed);
    rev.value++;
  }
}

/// The speed books play at: their own once set; until then the app speed
/// they have played at so far, so updating changes nothing.
double audiobookSpeedFrom({Object? stored, Object? appSpeed}) {
  for (final v in [stored, appSpeed]) {
    if (v is num && v.isFinite && v > 0) return v.toDouble();
  }
  return 1.0;
}

/// What the speed pill steps through.
const audiobookSpeedSteps = [0.8, 1.0, 1.2, 1.5, 1.75, 2.0];

/// The next step up from [current], back to the slowest after the fastest.
double nextAudiobookSpeed(double current) {
  for (final s in audiobookSpeedSteps) {
    if (s > current + 0.01) return s;
  }
  return audiobookSpeedSteps.first;
}
