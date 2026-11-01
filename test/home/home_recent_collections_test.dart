import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/collection_recents.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_data.dart';
import 'package:hive/hive.dart';

void main() {
  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    await Hive.openBox('LibraryPlaylists', bytes: Uint8List(0));
    await Hive.openBox('LibraryAlbums', bytes: Uint8List(0));
  });
  tearDown(() async => Hive.close());

  Future<void> played(String id, int minute,
          {String? type, String? name, String? art, String? by}) =>
      CollectionRecents.markPlayed(id,
          at: DateTime(2026, 10, 31, 9, minute),
          type: type,
          name: name,
          art: art,
          by: by);

  test('what is known of a collection is kept with when it was played',
      () async {
    await played('MPREb_coast', 1,
        type: 'album',
        name: 'Coastlines',
        art: 'https://example.com/coast.jpg',
        by: 'Nova Hart');
    await played('PLchill', 2, type: 'playlist', name: 'Chill evening');
    final recent = CollectionRecents.recent();
    expect(recent.map((r) => r.id), ['PLchill', 'MPREb_coast']);
    final coast = recent.last;
    expect(coast.type, 'album');
    expect(coast.name, 'Coastlines');
    expect(coast.art, 'https://example.com/coast.jpg');
    expect(coast.by, 'Nova Hart');
    // The Library's sort still reads the times alone.
    expect(CollectionRecents.lastPlayed('PLchill'), isNotNull);
  });

  test('Home lists them latest first, as albums and playlists', () async {
    await played('MPREb_coast', 1,
        type: 'album', name: 'Coastlines', by: 'Nova Hart');
    await played('PLchill', 2,
        type: 'playlist',
        name: 'Chill evening',
        art: 'https://example.com/chill.jpg');
    // The Recently played list is songs, not somewhere played from.
    await played('LIBRP', 3, type: 'playlist', name: 'Recently played');
    // Played before Riff kept more, and not in the Library: nothing to show.
    await played('PLold', 4);
    final shelf = recentCollectionsShelf()!;
    expect(shelf.id, 'riff:recentCollections');
    expect(shelf.items.map((i) => i.key),
        ['playlist:PLchill', 'album:MPREb_coast']);
    final album = shelf.items.last.value as Album;
    expect(album.title, 'Coastlines');
    expect(album.artists!.single['name'], 'Nova Hart');
    final playlist = shelf.items.first.value as Playlist;
    expect(playlist.thumbnailUrl, 'https://example.com/chill.jpg');
  });

  test('your Library knows them even from before', () async {
    await Hive.box('LibraryPlaylists').put('local_road', {
      'title': 'Road Trip 2025',
      'playlistId': 'local_road',
      'isCloudPlaylist': false,
    });
    await played('local_road', 1);
    await played('LIBFAV', 2);
    final shelf = recentCollectionsShelf()!;
    expect(shelf.items.map((i) => i.key),
        ['playlist:LIBFAV', 'playlist:local_road']);
    final road = shelf.items.last;
    expect((road.value as Playlist).isCloudPlaylist, isFalse);
    // Its own cover is drawn for it: not "missing art".
    expect(road.hasArt, isTrue);
  });

  test('one is not a shelf', () async {
    expect(recentCollectionsShelf(), isNull);
    await played('PLchill', 1, type: 'playlist', name: 'Chill evening');
    expect(recentCollectionsShelf(), isNull);
  });

  test('no more than a shelf holds', () async {
    for (var i = 0; i < 20; i++) {
      await played('PL$i', i, type: 'playlist', name: 'Playlist $i');
    }
    final shelf = recentCollectionsShelf()!;
    expect(shelf.items.length, homeRecentCollectionsMax);
    expect(shelf.items.first.key, 'playlist:PL19');
  });

  test('your mixes stay on their own shelf, not here as well', () async {
    await played('RIFF_daily_1', 1, type: 'playlist', name: 'Daily Mix 1');
    await played('PLchill', 2, type: 'playlist', name: 'Chill evening');
    await played('MPREb_coast', 3, type: 'album', name: 'Coastlines');
    expect(recentCollectionsShelf()!.items.map((i) => i.key),
        ['album:MPREb_coast', 'playlist:PLchill']);
  });

  test('one of your playlists, deleted, is gone from here', () async {
    await Hive.box('LibraryPlaylists').put('LIB1699', {
      'title': 'Road trip',
      'playlistId': 'LIB1699',
      'isCloudPlaylist': false,
    });
    await played('LIB1699', 1, type: 'playlist', name: 'Road trip');
    await played('PLchill', 2, type: 'playlist', name: 'Chill evening');
    await played('MPREb_coast', 3, type: 'album', name: 'Coastlines');
    expect(recentCollectionsShelf()!.items.length, 3);
    // Deleted before Riff forgot deleted playlists: no longer in the
    // Library, so not rebuilt as a YouTube Music playlist that isn't there.
    await Hive.box('LibraryPlaylists').delete('LIB1699');
    expect(recentCollectionsShelf()!.items.map((i) => i.key),
        ['album:MPREb_coast', 'playlist:PLchill']);
    // And forgotten when deleted now.
    await CollectionRecents.forget('PLchill');
    expect(CollectionRecents.recent().map((r) => r.id),
        ['MPREb_coast', 'LIB1699']);
  });

  test('played again from where little is known: its cover and artist stay',
      () async {
    await played('MPREb_coast', 1,
        type: 'album',
        name: 'Coastlines',
        art: 'https://example.com/coast.jpg',
        by: 'Nova Hart');
    // A Speed dial pin or Home's long press: no artist, and the first
    // song's art only as a stand-in.
    await CollectionRecents.markPlayed('MPREb_coast',
        type: 'album',
        name: 'Coastlines',
        fallbackArt: 'https://example.com/song.jpg');
    final coast = CollectionRecents.recent().single;
    expect(coast.art, 'https://example.com/coast.jpg');
    expect(coast.by, 'Nova Hart');
    // With no cover known, the song's art stands in.
    await CollectionRecents.markPlayed('PLnew',
        type: 'playlist',
        name: 'New',
        fallbackArt: 'https://example.com/song.jpg');
    expect(
        CollectionRecents.recent().first.art, 'https://example.com/song.jpg');
  });

  test('a Piped playlist opens as one', () async {
    await CollectionRecents.markPlayed('3f2a-piped',
        type: 'playlist', name: 'From Piped', piped: true);
    await played('PLchill', 2, type: 'playlist', name: 'Chill evening');
    final piped = recentCollectionsShelf()!
        .items
        .firstWhere((i) => i.key == 'playlist:3f2a-piped')
        .value as Playlist;
    expect(piped.isPipedPlaylist, isTrue);
  });
}
