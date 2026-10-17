import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/normalization_level.dart';
import 'package:hive/hive.dart';

void main() {
  test('a loud song is brought down to the level chosen', () {
    // 5 dB over YouTube's reference.
    expect(normalizedVolume(5, NormalizationLevel.normal.targetDb),
        closeTo(0.3162, 1e-4));
    expect(normalizedVolume(5, NormalizationLevel.loud.targetDb),
        closeTo(0.5623, 1e-4));
    expect(normalizedVolume(5, NormalizationLevel.quiet.targetDb),
        closeTo(0.1778, 1e-4));
  });

  test('a quiet song plays at full volume, never above', () {
    expect(normalizedVolume(-8, NormalizationLevel.loud.targetDb), 1.0);
    expect(normalizedVolume(-5, NormalizationLevel.normal.targetDb), 1.0);
  });

  test('Normal is the level normalization always used', () {
    expect(NormalizationLevel.normal.targetDb, -5);
  });

  group('the setting', () {
    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    });
    tearDown(() async {
      await NormalizationLevel.set(NormalizationLevel.normal);
      await Hive.box('AppPrefs').close();
    });

    test('is Normal until chosen, then kept', () async {
      expect(NormalizationLevel.selected.value, NormalizationLevel.normal);
      await NormalizationLevel.set(NormalizationLevel.loud);
      expect(NormalizationLevel.selected.value, NormalizationLevel.loud);
      expect(Hive.box('AppPrefs').get(NormalizationLevel.key), 'loud');
    });
  });
}
