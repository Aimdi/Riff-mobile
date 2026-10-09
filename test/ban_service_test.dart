import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/ban_service.dart';
import 'package:hive/hive.dart';

void main() {
  test('ban writes require an open Hive box', () {
    expect(BanService.canWriteBan(null), isFalse);
  });

  group('filterTracks with MediaItems', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_ban_items_');
      Hive.init(tmp.path);
      for (final b in ['BannedSongs', 'BannedArtists', 'BannedCollections']) {
        await Hive.openBox(b);
      }
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    MediaItem item(String id, {String artist = 'Good', String? albumId}) =>
        MediaItem(id: id, title: 'T $id', artist: artist, extras: {
          'artists': [
            {'name': artist}
          ],
          if (albumId != null) 'album': {'id': albumId, 'name': 'A'},
        });

    test('watch-playlist / home-shelf items honour every ban', () async {
      await BanService.banRaw('s1', 'Song', 'Someone');
      await BanService.banArtist('Bad Artist');
      await BanService.banCollection('MPREbad', 'Bad Album', 'album');
      final tracks = [
        item('s1'),
        item('s2', artist: 'Bad Artist'),
        item('s3', albumId: 'MPREbad'),
        item('s4'),
      ];
      expect(BanService.filterTracks(tracks).cast<MediaItem>().map((t) => t.id),
          ['s4']);
      // The song asked for explicitly stays.
      expect(
          BanService.filterTracks(tracks, keepVideoId: 's1')
              .cast<MediaItem>()
              .map((t) => t.id),
          ['s1', 's4']);
    });

    test('nothing banned: the list comes back untouched', () {
      final tracks = [item('a'), item('b')];
      expect(identical(BanService.filterTracks(tracks), tracks), isTrue);
    });
  });
}
