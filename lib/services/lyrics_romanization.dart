/// Romanized lyrics (Settings › Romanized lyrics): Korean, Cyrillic and
/// Greek lines get their Latin spelling under them, as in Metrolist and
/// YouTube Music, unless they're in the app language's own script.
library;

import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/utils/romanize.dart';

class LyricsRomanization {
  LyricsRomanization._();

  static const key = 'romanizeLyrics';

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// On unless turned off in Settings.
  static final enabled = (_prefs?.get(key) != false).obs;

  static Future<void> setEnabled(bool on) async {
    enabled.value = on;
    await _prefs?.put(key, on);
  }

  /// App languages written in each script: their speakers read it as is.
  static const _nativeLanguages = {
    RomanizedScript.korean: {'ko'},
    RomanizedScript.cyrillic: {
      'ru', 'uk', 'be', 'bg', 'sr', 'mk', 'kk', 'ky', 'mn', 'tg', //
    },
    RomanizedScript.greek: {'el'},
  };

  /// [line] in Latin letters, when romanization is on and [line] has a
  /// script that isn't [appLanguage]'s (the app's language by default);
  /// else null. Inside an Obx it follows the setting.
  static String? lineFor(String? line, {String? appLanguage}) {
    if (line == null || !enabled.value) return null;
    final scripts = romanizableScripts(line);
    if (scripts.isEmpty) return null;
    final language = appLanguage ?? Get.locale?.languageCode ?? 'en';
    if (scripts.every((s) => _nativeLanguages[s]!.contains(language))) {
      return null;
    }
    return romanize(line);
  }
}
