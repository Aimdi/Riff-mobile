/// Download quality, as Spotify's and YouTube Music's: High, as before (the
/// best stream in the download format), or Low, about a third of the space
/// (the smallest: Opus about 50 kb/s, AAC 48 kb/s). High by default.
library;

import 'package:get/get.dart';
import 'package:hive/hive.dart';

class DownloadQuality {
  DownloadQuality._();

  /// AppPrefs key: "low", else high.
  static const key = 'downloadQuality';

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// For the Settings choice.
  static final low = RxBool(_prefs?.get(key) == 'low');

  static Future<void> set(bool isLow) async {
    low.value = isLow;
    await _prefs?.put(key, isLow ? 'low' : 'high');
  }
}
