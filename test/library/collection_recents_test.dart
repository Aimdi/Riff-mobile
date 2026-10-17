import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/collection_recents.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:hive/hive.dart';

Playlist _pl(String id) => Playlist(
    title: 'Playlist $id',
    playlistId: id,
    thumbnailUrl: Playlist.thumbPlaceholderUrl,
    isCloudPlaylist: false);

Album _album(String id) =>
    Album(title: 'Album $id', browseId: id, artists: null, thumbnailUrl: '');

void main() {
  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
  });
  tearDown(() async {
    await Hive.box('AppPrefs').close();
  });

  Future<void> playedAt(String id, int minute) =>
      CollectionRecents.markPlayed(id, at: DateTime(2026, 1, 1, 0, minute));

  test('remembers when each was last played', () async {
    expect(CollectionRecents.lastPlayed('a'), isNull);
    await playedAt('a', 1);
    await playedAt('a', 5);
    expect(CollectionRecents.lastPlayed('a'),
        DateTime(2026, 1, 1, 0, 5).millisecondsSinceEpoch);
    await CollectionRecents.markPlayed('');
    expect(CollectionRecents.snapshot().keys, ['a']);
  });

  test('past the limit, the longest unplayed are forgotten', () async {
    for (var i = 0; i <= CollectionRecents.max; i++) {
      await CollectionRecents.markPlayed('p$i',
          at: DateTime(2026).add(Duration(minutes: i)));
    }
    final kept = CollectionRecents.snapshot();
    expect(kept.length, CollectionRecents.max);
    expect(kept.containsKey('p0'), isFalse);
    expect(kept.containsKey('p${CollectionRecents.max}'), isTrue);
  });

  test('playlists: latest played first, never played last by name', () async {
    await playedAt('a', 1);
    await playedAt('c', 3);
    await playedAt('d', 2);
    final list = [
      for (final id in ['e', 'a', 'b', 'c', 'd']) _pl(id)
    ];
    sortPlayLists(list, SortType.RecentlyPlayed, true);
    expect([for (final p in list) p.playlistId], ['c', 'd', 'a', 'b', 'e']);

    sortPlayLists(list, SortType.RecentlyPlayed, false);
    expect([for (final p in list) p.playlistId], ['e', 'b', 'a', 'd', 'c']);
  });

  test('albums too', () async {
    await playedAt('MPREb_2', 2);
    await playedAt('MPREb_1', 1);
    final list = [
      for (final id in ['MPREb_3', 'MPREb_1', 'MPREb_2']) _album(id)
    ];
    sortAlbumNSingles(list, SortType.RecentlyPlayed, true);
    expect(
        [for (final a in list) a.browseId], ['MPREb_2', 'MPREb_1', 'MPREb_3']);
  });
}
