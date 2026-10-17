/// What the time at the seek bar's right end shows: the length, or, once
/// tapped, the time left ("−2:31"), as in Apple Music and Pocket Casts.
/// Kept, for every player.
library;

import 'package:get/get.dart';
import 'package:hive/hive.dart';

class SeekTimeLabel {
  SeekTimeLabel._();

  static const key = 'seekBarShowsTimeLeft';

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static final showsTimeLeft = (_prefs?.get(key) == true).obs;

  static Future<void> toggle() async {
    showsTimeLeft.toggle();
    await _prefs?.put(key, showsTimeLeft.value);
  }
}
