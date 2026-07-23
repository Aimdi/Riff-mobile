import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Regression for v1.7.82 black screen:
/// Hive lowercases box names, so "AppPrefs" and "appPrefs" are the same box.
/// Opening the "legacy" name and calling deleteFromDisk() wipes real prefs.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('riff_hive_prefs_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('AppPrefs and appPrefs resolve to the same Hive box', () async {
    final prefs = await Hive.openBox('AppPrefs');
    await prefs.put('themeModeType', 2);

    expect(await Hive.boxExists('appPrefs'), isTrue);
    expect(Hive.isBoxOpen('appPrefs'), isTrue);

    final alias = Hive.box('appPrefs');
    expect(identical(prefs, alias) || alias.get('themeModeType') == 2, isTrue);
    expect(alias.get('themeModeType'), 2);
  });

  test('deleteFromDisk on appPrefs alias destroys AppPrefs data', () async {
    final prefs = await Hive.openBox('AppPrefs');
    await prefs.put('streamingQuality', 1);
    expect(prefs.get('streamingQuality'), 1);

    // This is the v1.7.82 bug path — do not reintroduce in main.dart.
    final alias = await Hive.openBox('appPrefs');
    await alias.deleteFromDisk();

    expect(Hive.isBoxOpen('AppPrefs'), isFalse);
    final reopened = await Hive.openBox('AppPrefs');
    expect(reopened.get('streamingQuality'), isNull);
  });
}
