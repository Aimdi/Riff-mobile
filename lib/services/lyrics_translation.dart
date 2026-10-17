/// Lyrics translation (the player's ⋮ › Translate lyrics, or Settings), as
/// Apple Music, Spotify and YouTube Music offer for some songs: each line's
/// translation into the app's language under it. Off until switched on;
/// while on, a song's lyrics are sent to Google Translate.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/utils/helper.dart';

class LyricsTranslation {
  LyricsTranslation._();

  static const key = 'translateLyrics';

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static final enabled = (_prefs?.get(key) == true).obs;

  static Future<void> setEnabled(bool on) async {
    // Switching it on again retries lyrics that failed.
    if (on) _cache.clear();
    enabled.value = on;
    await _prefs?.put(key, on);
  }

  /// Bumped when a translation arrives, for Obx.
  static final rev = 0.obs;

  static final _cache = <String, List<String?>>{};
  static final _pending = <String>{};

  /// Each of [lines]' translation into [language] (the app's by default):
  /// null for lines that need none (blank, or already in it), and null
  /// altogether while switched off or still being fetched. Inside an Obx
  /// it follows the switch and the fetch.
  static List<String?>? linesFor(List<String> lines, {String? language}) {
    rev.value;
    if (!enabled.value || lines.every((l) => l.trim().isEmpty)) return null;
    final target = language ?? Get.locale?.languageCode ?? 'en';
    final cacheKey = '$target\n${lines.join('\n')}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    if (_pending.add(cacheKey)) {
      // Not from inside the build that asked.
      Future(() => _fetch(cacheKey, lines, target));
    }
    return null;
  }

  static Future<void> _fetch(
      String cacheKey, List<String> lines, String target) async {
    // A failure counts as "nothing to show" for the rest of the session
    // (switching it off and on again retries), so it isn't asked again
    // on every rebuild.
    var result = List<String?>.filled(lines.length, null);
    try {
      final translated = <String>[];
      String? source;
      for (final chunk in lyricsTranslationChunks(lines)) {
        final res = await _dio.post<dynamic>(
          'https://translate.googleapis.com/translate_a/single',
          queryParameters: {
            'client': 'gtx',
            'sl': 'auto',
            'tl': target,
            'dt': 't',
          },
          data: {'q': chunk.join('\n')},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
        final data = res.data is String ? jsonDecode(res.data) : res.data;
        final text = gtxTranslatedText(data);
        if (text == null) throw const FormatException('no translation');
        translated.addAll(text.split('\n'));
        source ??= gtxSourceLanguage(data);
      }
      // Lyrics already in the app's language need none.
      if (source != target) {
        result = alignLyricsTranslation(lines, translated);
      }
    } catch (e) {
      printERROR('Lyrics translation failed: $e');
    } finally {
      _cache[cacheKey] = result;
      _pending.remove(cacheKey);
      rev.value++;
    }
  }

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  @visibleForTesting
  static void debugCache(
      List<String> lines, String language, List<String?> translations) {
    _cache['$language\n${lines.join('\n')}'] = translations;
    rev.value++;
  }
}

/// [lines] in groups short enough for one request (about 4,000 characters),
/// whole lines only.
List<List<String>> lyricsTranslationChunks(List<String> lines,
    {int maxChars = 4000}) {
  final chunks = <List<String>>[];
  var current = <String>[];
  var size = 0;
  for (final line in lines) {
    if (current.isNotEmpty && size + line.length + 1 > maxChars) {
      chunks.add(current);
      current = <String>[];
      size = 0;
    }
    current.add(line);
    size += line.length + 1;
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

/// The translated text of a Google Translate (client=gtx) answer, or null.
String? gtxTranslatedText(dynamic data) {
  if (data is! List || data.isEmpty || data.first is! List) return null;
  final buffer = StringBuffer();
  for (final segment in data.first as List) {
    if (segment is List && segment.isNotEmpty && segment.first is String) {
      buffer.write(segment.first);
    }
  }
  return buffer.toString();
}

/// The language Google Translate found the text in, if it says.
String? gtxSourceLanguage(dynamic data) =>
    data is List && data.length > 2 && data[2] is String
        ? data[2] as String
        : null;

/// [translated] lines against the [lines] they translate: null for blank
/// lines and lines that come back the same; all null when the counts
/// don't match (a line could end up under the wrong one).
List<String?> alignLyricsTranslation(
    List<String> lines, List<String> translated) {
  if (translated.length != lines.length) {
    return List<String?>.filled(lines.length, null);
  }
  return [
    for (var i = 0; i < lines.length; i++)
      lines[i].trim().isEmpty ||
              translated[i].trim().isEmpty ||
              translated[i].trim().toLowerCase() ==
                  lines[i].trim().toLowerCase()
          ? null
          : translated[i].trim(),
  ];
}

/// What goes under a lyric line: its romanization, its translation, or
/// both on two lines; null for neither.
String? lyricsSecondLine(String? romanization, String? translation) {
  final parts = [romanization, translation]
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .toList();
  return parts.isEmpty ? null : parts.join('\n');
}
