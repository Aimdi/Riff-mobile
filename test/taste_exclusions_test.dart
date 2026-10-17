import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/services/taste_exclusions.dart';
import 'package:hive/hive.dart';

void main() {
  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    TasteExclusions.rev.value = 0;
  });
  tearDown(() => Hive.box('AppPrefs').close());

  PlaylingFrom from(PlaylingFromType type, String id) =>
      PlaylingFrom(type: type, name: 'Sleep', id: id);

  test('a playlist left out, and let back in', () async {
    expect(TasteExclusions.excludes('PLsleep'), isFalse);

    await TasteExclusions.setExcluded('PLsleep', true);
    expect(TasteExclusions.excludes('PLsleep'), isTrue);
    expect(Hive.box('AppPrefs').get(TasteExclusions.key), ['PLsleep']);
    expect(TasteExclusions.rev.value, 1);

    // Already out: nothing changes.
    await TasteExclusions.setExcluded('PLsleep', true);
    expect(TasteExclusions.rev.value, 1);

    await TasteExclusions.setExcluded('PLsleep', false);
    expect(TasteExclusions.excludes('PLsleep'), isFalse);
    expect(TasteExclusions.rev.value, 2);
  });

  test("YouTube's page id (VL…) and the playlist's own are one", () async {
    await TasteExclusions.setExcluded('VLPLsleep', true);
    expect(TasteExclusions.excludes('PLsleep'), isTrue);
    expect(TasteExclusions.excludes('VLPLsleep'), isTrue);
    await TasteExclusions.setExcluded('PLsleep', false);
    expect(TasteExclusions.excludes('VLPLsleep'), isFalse);
  });

  test('only what plays from the playlist is left out', () async {
    await TasteExclusions.setExcluded('PLsleep', true);
    expect(
        TasteExclusions.excludesPlay(
            from(PlaylingFromType.PLAYLIST, 'VLPLsleep')),
        isTrue);
    expect(
        TasteExclusions.excludesPlay(
            from(PlaylingFromType.PLAYLIST, 'PLother')),
        isFalse);
    // An album or a pick of songs, whatever their id.
    expect(
        TasteExclusions.excludesPlay(from(PlaylingFromType.ALBUM, 'PLsleep')),
        isFalse);
    expect(
        TasteExclusions.excludesPlay(
            PlaylingFrom(type: PlaylingFromType.SELECTION)),
        isFalse);
    expect(TasteExclusions.excludes(''), isFalse);
  });
}
