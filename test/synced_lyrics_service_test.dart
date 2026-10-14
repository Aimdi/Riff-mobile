import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/better_lyrics_service.dart';
import 'package:harmonymusic/services/synced_lyrics_service.dart';
import 'package:hive/hive.dart';

void main() {
  group('LRCLIB answer', () {
    test('a synced hit becomes the cache entry', () {
      expect(
          SyncedLyricsService.lrclibHit({
            'syncedLyrics': '[00:01.00]Hi',
            'plainLyrics': 'Hi',
          }),
          {
            'synced': '[00:01.00]Hi',
            'plainLyrics': 'Hi',
            'source': 'lrclib',
          });
    });

    test('anything else is a miss, never an exception', () {
      // A non-JSON body used to throw a TypeError past the DioException
      // catch, so KuGou was never tried.
      expect(SyncedLyricsService.lrclibHit('<html>busy</html>'), isNull);
      expect(SyncedLyricsService.lrclibHit(null), isNull);
      expect(SyncedLyricsService.lrclibHit({'syncedLyrics': null}), isNull);
      expect(SyncedLyricsService.lrclibHit({'syncedLyrics': ''}), isNull);
      expect(SyncedLyricsService.lrclibHit([1, 2]), isNull);
    });
  });

  group('plain lyrics, kept for offline', () {
    setUp(() async {
      await Hive.openBox('lyrics', bytes: Uint8List(0));
    });
    tearDown(() async {
      await Hive.close();
    });

    test('fetched ones are kept, and shown when fetching fails', () async {
      expect(await SyncedLyricsService.plainLyrics('s1', () async => 'La la'),
          'La la');
      expect(
          Hive.box('lyrics').get(SyncedLyricsService.plainKey('s1')), 'La la');
      // Offline: what was kept.
      expect(
          await SyncedLyricsService.plainLyrics(
              's1', () async => throw Exception('offline')),
          'La la');
      // Apart from the synced lyrics kept by the song's id.
      expect(Hive.box('lyrics').containsKey('s1'), isFalse);
    });

    test('a song without lyrics keeps nothing', () async {
      expect(await SyncedLyricsService.plainLyrics('s2', () async => null),
          isNull);
      expect(Hive.box('lyrics').containsKey(SyncedLyricsService.plainKey('s2')),
          isFalse);
      expect(
          await SyncedLyricsService.plainLyrics(
              's2', () async => throw Exception('offline')),
          isNull);
    });
  });

  test('TTML renderings agree with one shared parse', () {
    const ttml = '<tt><body><div>'
        '<p begin="00:01.000" end="00:02.000">One</p>'
        '<p begin="00:03.500">Two &amp; three</p>'
        '</div></body></tt>';
    expect(BetterLyricsService.ttmlToLrc(ttml),
        '[00:01.00]One\n[00:03.50]Two & three');
    expect(BetterLyricsService.ttmlToPlain(ttml), 'One\nTwo & three');
    expect(BetterLyricsService.ttmlToLrc('<tt></tt>'), isNull);
    expect(BetterLyricsService.ttmlToPlain('<tt></tt>'), isNull);
  });
}
