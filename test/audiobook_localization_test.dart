import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/get_localization.dart';

/// `String.tr` returns the key itself when no entry matches, so a key that was
/// never added to the translations ships as a literal "listenOnAudible" on the
/// button instead of failing anywhere. These tests make that failure loud for
/// the whole Audiobooks section.

/// Pure helper: every `'someKey'.tr` literal in a chunk of Dart source.
///
/// Kept free of I/O so the matching itself is directly testable.
Set<String> extractTrKeys(String source) =>
    RegExp(r"'([A-Za-z0-9_]+)'\.tr\b")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

void main() {
  late Map<String, String> en;
  late Map<String, dynamic> enJson;
  late Set<String> audiobookKeys;

  setUpAll(() {
    en = Languages().keys['en']!;
    enJson = jsonDecode(File('localization/en.json').readAsStringSync())
        as Map<String, dynamic>;
    audiobookKeys = <String>{};
    final dir = Directory('lib/ui/screens/Audiobooks');
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      audiobookKeys.addAll(extractTrKeys(f.readAsStringSync()));
    }
  });

  test('extractTrKeys picks up literal .tr calls only', () {
    expect(
      extractTrKeys("Text('similarTitles'.tr), label: Text('upload'.tr)"),
      {'similarTitles', 'upload'},
    );
    // Not a translation lookup — must not be collected.
    expect(extractTrKeys('final x = book.author.trim();'), isEmpty);
  });

  test('the Audiobooks screens reference a non-trivial number of keys', () {
    // Guards against the scan silently matching nothing (renamed folder,
    // broken regex) and the assertions below passing vacuously.
    expect(audiobookKeys.length, greaterThan(30));
  });

  test('every .tr key used by lib/ui/screens/Audiobooks exists in "en"', () {
    final missing = audiobookKeys.where((k) => !en.containsKey(k)).toList()
      ..sort();
    expect(missing, isEmpty,
        reason: 'these render as their own key name in the UI');
  });

  test('no Audiobooks key resolves to an empty string', () {
    for (final k in audiobookKeys) {
      expect(en[k]?.trim().isNotEmpty, isTrue, reason: '$k is blank');
    }
  });

  /// The catalog/upload slice specifically — spelled out so a rename in the
  /// screens cannot quietly shrink the set the scan above protects.
  const catalogKeys = <String>[
    'listenOnAudible',
    'viewOnAppleBooks',
    'audiobookBrowseOnly',
    'noDescription',
    'similarTitles',
    'ratings',
    'searchAudiobooks',
    'noSavedAudiobooks',
    'saved',
    'author',
    'upload',
    'uploading',
    'uploadComplete',
    'uploadFailed',
    'uploadAudiobook',
    'absUploadForbidden',
    'chooseFiles',
    'noFilesSelected',
    'targetFolder',
    'titleRequired',
    'series',
  ];

  test('catalog and upload keys exist in "en"', () {
    final missing = catalogKeys.where((k) => !en.containsKey(k)).toList();
    expect(missing, isEmpty);
  });

  // The Dart file is generated from the JSON; if someone edits en.json and
  // forgets to re-run localization/generator.dart, the app ships the old text.
  test('generated translations are in sync with en.json', () {
    final drifted = audiobookKeys
        .where((k) => enJson[k] != null && enJson[k] != en[k])
        .toList()
      ..sort();
    expect(drifted, isEmpty,
        reason: 'run: dart run localization/generator.dart');
    final missingFromJson =
        catalogKeys.where((k) => !enJson.containsKey(k)).toList();
    expect(missingFromJson, isEmpty,
        reason: 'en.json is the source of truth for the generator');
  });
}
