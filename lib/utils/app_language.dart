/// Riff's language: the one picked in Settings › Language, or, with
/// "System default", the phone's own, as Spotify, YouTube Music and
/// AntennaPod follow the phone. Until one is picked it's English: the
/// translations cover only part of Riff yet, so following the phone
/// unasked would mix languages.
library;

import 'dart:ui' show Locale;

import 'lang_mapping.dart';

/// Settings › Language's "System default".
const systemLanguage = 'system';

/// The language Riff shows for [choice] (Settings › Language's value; null
/// before one was picked, which is English, as it always was) on a phone
/// set to [deviceLocales], most preferred first.
String appLanguageCode(String? choice, Iterable<Locale> deviceLocales) =>
    switch (choice) {
      systemLanguage => languageForLocales(deviceLocales),
      null || '' => 'en',
      // Chinese as older versions kept it.
      'zh_Hant' => 'zh-TW',
      'zh_Hans' => 'zh-CN',
      _ => choice,
    };

/// The first of [locales] Riff has a translation for, else English.
String languageForLocales(Iterable<Locale> locales) {
  for (final locale in locales) {
    final code = _riffLanguage(locale);
    if (code != null) return code;
  }
  return 'en';
}

String? _riffLanguage(Locale locale) {
  final language = locale.languageCode.toLowerCase();
  final code = switch (language) {
    'zh' => _traditionalChinese(locale) ? 'zh-TW' : 'zh-CN',
    // Riff's Norwegian is Bokmål, which Nynorsk readers read too.
    'nb' || 'no' || 'nn' => 'nb_NO',
    'tl' => 'fil',
    // Java's old code for Indonesian.
    'in' => 'id',
    _ => language,
  };
  return langMap.containsKey(code) ? code : null;
}

/// Traditional characters: the Hant script, or, with no script given,
/// Taiwan, Hong Kong or Macau.
bool _traditionalChinese(Locale locale) {
  final script = locale.scriptCode?.toLowerCase();
  if (script != null) return script == 'hant';
  return const {'TW', 'HK', 'MO'}.contains(locale.countryCode?.toUpperCase());
}
