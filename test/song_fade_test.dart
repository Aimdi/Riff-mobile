import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/song_fade.dart';
import 'package:hive/hive.dart';

void main() {
  group('how long a song fades', () {
    test('not at all when off', () {
      expect(songFadeMs(seconds: 0, lengthMs: 200000), 0);
    });

    test('for the length set', () {
      expect(songFadeMs(seconds: 5, lengthMs: 200000), 5000);
      expect(songFadeMs(seconds: 12, lengthMs: 200000), 12000);
    });

    test('songs shorter than three fades play as they are', () {
      expect(songFadeMs(seconds: 5, lengthMs: 14999), 0);
      expect(songFadeMs(seconds: 5, lengthMs: 15000), 5000);
    });
  });

  group('volume along the song', () {
    const length = 200000;

    test('full level in the middle, and with no fade', () {
      expect(
          songFadeFactor(
              posMs: 100000, lengthMs: length, inMs: 5000, outMs: 5000),
          isNull);
      expect(songFadeFactor(posMs: 199000, lengthMs: length), isNull);
    });

    test('fades out over the last seconds, to silence at the end', () {
      expect(
          songFadeFactor(posMs: 195000, lengthMs: length, outMs: 5000), isNull);
      expect(songFadeFactor(posMs: 197500, lengthMs: length, outMs: 5000), 0.5);
      expect(songFadeFactor(posMs: 200000, lengthMs: length, outMs: 5000), 0);
      // Past the end (the player's length runs over): still silent.
      expect(songFadeFactor(posMs: 200700, lengthMs: length, outMs: 5000), 0);
    });

    test('seeking back out of the fade gives the full level back', () {
      expect(songFadeFactor(posMs: 197500, lengthMs: length, outMs: 5000), 0.5);
      expect(
          songFadeFactor(posMs: 60000, lengthMs: length, outMs: 5000), isNull);
    });

    test('the song after fades in over its first seconds', () {
      expect(songFadeFactor(posMs: 0, lengthMs: length, inMs: 5000), 0);
      expect(songFadeFactor(posMs: 1000, lengthMs: length, inMs: 5000), 0.2);
      expect(songFadeFactor(posMs: 5000, lengthMs: length, inMs: 5000), isNull);
    });

    test('where both apply, the lower level wins', () {
      // In: 4000 / 5000; out: 6000 left of 8000.
      expect(
          songFadeFactor(posMs: 4000, lengthMs: 10000, inMs: 5000, outMs: 8000),
          0.75);
    });
  });

  group('the setting', () {
    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    });
    tearDown(() async {
      await Hive.box('AppPrefs').close();
    });

    test('is off until chosen', () {
      expect(SongFade.seconds, 0);
    });

    test('keeps a choice from the list; anything else is off', () async {
      await SongFade.set(8);
      expect(SongFade.seconds, 8);
      expect(SongFade.selected.value, 8);

      await Hive.box('AppPrefs').put(SongFade.key, 7);
      expect(SongFade.seconds, 0);

      await SongFade.set(7);
      expect(SongFade.seconds, 0);
      expect(SongFade.selected.value, 0);
    });
  });
}
