import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/app_language.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:harmonymusic/utils/lang_mapping.dart';

void main() {
  test('a picked language stays; none picked is English, as before', () {
    expect(appLanguageCode('de', const [Locale('fr')]), 'de');
    expect(appLanguageCode(null, const [Locale('fr')]), 'en');
    expect(appLanguageCode('', const [Locale('fr')]), 'en');
    // Chinese as older versions kept it.
    expect(appLanguageCode('zh_Hant', const []), 'zh-TW');
    expect(appLanguageCode('zh_Hans', const []), 'zh-CN');
  });

  test("System default: the first of the phone's languages Riff has", () {
    expect(appLanguageCode(systemLanguage, const [Locale('de', 'AT')]), 'de');
    expect(
        appLanguageCode(
            systemLanguage, const [Locale('he', 'IL'), Locale('fr', 'CA')]),
        'fr');
    // None of them: English.
    expect(appLanguageCode(systemLanguage, const [Locale('he')]), 'en');
    expect(appLanguageCode(systemLanguage, const []), 'en');
  });

  test("the phone's codes as Riff's", () {
    expect(languageForLocales(const [Locale('zh', 'TW')]), 'zh-TW');
    expect(languageForLocales(const [Locale('zh', 'HK')]), 'zh-TW');
    expect(languageForLocales(const [Locale('zh', 'CN')]), 'zh-CN');
    expect(languageForLocales(const [Locale('zh')]), 'zh-CN');
    expect(
        languageForLocales(
            const [Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')]),
        'zh-TW');
    expect(
        languageForLocales(const [
          Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hans', countryCode: 'HK')
        ]),
        'zh-CN');
    for (final norwegian in const ['nb', 'no', 'nn']) {
      expect(languageForLocales([Locale(norwegian, 'NO')]), 'nb_NO');
    }
    expect(languageForLocales(const [Locale('tl', 'PH')]), 'fil');
    expect(languageForLocales(const [Locale('in', 'ID')]), 'id');
    expect(languageForLocales(const [Locale('pt', 'BR')]), 'pt');
  });

  test('every language in the picker can be followed, and is translated', () {
    final translated = Languages().keys.keys.toSet();
    for (final code in langMap.keys) {
      expect(translated, contains(code));
      if (code.contains('-') || code.contains('_')) continue;
      expect(languageForLocales([Locale(code)]), code);
    }
  });
}
