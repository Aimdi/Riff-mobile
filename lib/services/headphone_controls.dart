/// Headphone buttons, as Pocket Casts' Headphone controls set them: what a
/// headphone's (or a car stereo's) next and previous do in a podcast
/// episode, and a one-button headset's two and three presses: skip
/// forward and back (as the notification's buttons do), go to the next or
/// previous chapter, bookmark where you are, or go on to the next or
/// previous episode. Audiobooks and music keep theirs.
library;

import 'package:get/get.dart';
import 'package:hive/hive.dart';

enum HeadphoneAction { skip, chapter, bookmark, episode }

class HeadphoneControls {
  HeadphoneControls._();

  /// AppPrefs: the two buttons' actions, by name.
  static const nextKey = 'headphoneNext';
  static const previousKey = 'headphonePrevious';

  /// Bumps when one is changed.
  static final rev = 0.obs;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static HeadphoneAction _read(String key) {
    final name = _prefs?.get(key);
    return HeadphoneAction.values
        .firstWhere((a) => a.name == name, orElse: () => HeadphoneAction.skip);
  }

  /// What next does in an episode.
  static HeadphoneAction get next => _read(nextKey);

  /// What previous does in an episode.
  static HeadphoneAction get previous => _read(previousKey);

  static Future<void> set(HeadphoneAction action, {required bool next}) async {
    await _prefs?.put(next ? nextKey : previousKey, action.name);
    rev.value++;
  }
}
