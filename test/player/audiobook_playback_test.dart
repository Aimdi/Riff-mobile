import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/audiobook_playback.dart';
import 'package:hive/hive.dart';

void main() {
  group('audiobookSpeedFrom', () {
    test('the books\' own speed wins', () {
      expect(audiobookSpeedFrom(stored: 1.5, appSpeed: 1.2), 1.5);
    });

    test('until set, books keep the app speed they played at', () {
      expect(audiobookSpeedFrom(appSpeed: 1.2), 1.2);
      expect(audiobookSpeedFrom(), 1.0);
    });

    test('unreadable values fall through', () {
      expect(audiobookSpeedFrom(stored: 'fast', appSpeed: 1.2), 1.2);
      expect(audiobookSpeedFrom(stored: 0, appSpeed: -1), 1.0);
      expect(audiobookSpeedFrom(stored: double.nan), 1.0);
      expect(audiobookSpeedFrom(stored: double.infinity), 1.0);
    });
  });

  group('nextAudiobookSpeed', () {
    test('steps up through the common speeds, then round again', () {
      expect(nextAudiobookSpeed(0.8), 1.0);
      expect(nextAudiobookSpeed(1.0), 1.2);
      expect(nextAudiobookSpeed(1.75), 2.0);
      expect(nextAudiobookSpeed(2.0), 0.8);
    });

    test('a speed between steps goes to the next one up', () {
      expect(nextAudiobookSpeed(1.1), 1.2);
      expect(nextAudiobookSpeed(0.5), 0.8);
      expect(nextAudiobookSpeed(3.0), 0.8);
    });
  });

  group('AudiobookPlayback (Hive)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_book_speed_');
      Hive.init(tmp.path);
      await Hive.openBox('AppPrefs');
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('books get their own speed; music keeps its own', () async {
      await Hive.box('AppPrefs').put('playbackSpeed', 1.2);
      expect(AudiobookPlayback.speed, 1.2);

      final rev = AudiobookPlayback.rev.value;
      await AudiobookPlayback.setSpeed(1.5);
      expect(AudiobookPlayback.speed, 1.5);
      expect(AudiobookPlayback.rev.value, rev + 1);
      expect(Hive.box('AppPrefs').get('playbackSpeed'), 1.2);

      // Changing music's speed no longer moves the books'.
      await Hive.box('AppPrefs').put('playbackSpeed', 0.8);
      expect(AudiobookPlayback.speed, 1.5);
    });
  });
}
