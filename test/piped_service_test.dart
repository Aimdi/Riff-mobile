import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/piped_service.dart';
import 'package:hive/hive.dart';

void main() {
  group('streamToMediaItem', () {
    test('a playlist entry becomes a MediaItem', () {
      final m = PipedServices.streamToMediaItem({
        'url': '/watch?v=abc123&list=PL1',
        'title': 'Song',
        'uploaderName': 'Artist',
        'duration': 215,
        'thumbnail': 'https://img.example/a.jpg',
      })!;
      expect(m.id, 'abc123');
      expect(m.title, 'Song');
      expect(m.artist, 'Artist');
      expect(m.duration, const Duration(seconds: 215));
      expect(m.artUri.toString(), 'https://img.example/a.jpg');
    });

    test('odd entries are skipped or tolerated, never thrown', () {
      // Each of these used to throw and lose the whole playlist.
      expect(PipedServices.streamToMediaItem({'url': '/channel/UC1'}), isNull);
      expect(PipedServices.streamToMediaItem(null), isNull);
      final noDuration = PipedServices.streamToMediaItem(
          {'url': '/watch?v=x1', 'title': 'Live'})!;
      expect(noDuration.duration, isNull);
      expect(noDuration.artUri, isNull);
    });
  });

  group('restored login', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_piped_');
      Hive.init(tmp.path);
      await Hive.openBox('AppPrefs');
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('a partial stored entry does not make the service throw', () async {
      await Hive.box('AppPrefs').put('piped', {'token': 't'});
      expect(PipedServices().isLoggedIn, isFalse);
      await Hive.box('AppPrefs').put('piped',
          {'isLoggedIn': true, 'token': 't', 'instApiUrl': 'https://p'});
      expect(PipedServices().isLoggedIn, isTrue);
    });
  });
}
