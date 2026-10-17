import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart';
import 'package:hive/hive.dart';

Map<String, dynamic> _album(String id, String title, String artist) => Album(
      title: title,
      browseId: id,
      artists: [
        {'name': artist}
      ],
      thumbnailUrl: '',
    ).toJson();

/// The Library's sort comes back after a restart, as Spotify keeps Your
/// Library's.
void main() {
  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    await Hive.openBox('LibraryAlbums', bytes: Uint8List(0));
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  test('none chosen: none kept, the menu on Name as before', () {
    expect(SortChoice.load(LibrarySortTags.songs), isNull);
    final c = SortWidgetController(rememberAs: LibrarySortTags.songs);
    expect(c.sortType.value, SortType.Name);
    expect(c.isAscending.value, isTrue);
  });

  test('what a Library tab is sorted by is kept, and starts it next time',
      () async {
    final before = SortWidgetController(rememberAs: LibrarySortTags.albums);
    before.onSortByArtist((_, __) {});
    before.onAscendNDescend((_, __) {});
    await Future<void>.delayed(Duration.zero);

    // Riff started again.
    final after = SortWidgetController(rememberAs: LibrarySortTags.albums);
    expect(after.sortType.value, SortType.Artist);
    expect(after.isAscending.value, isFalse);
    // Each tab has its own.
    expect(SortChoice.load(LibrarySortTags.songs), isNull);
  });

  test('other lists\' sort (a playlist\'s, an album\'s) isn\'t kept', () async {
    final c = SortWidgetController();
    c.onSortByDuration((_, __) {});
    await Future<void>.delayed(Duration.zero);
    expect(Hive.box('AppPrefs').keys.where((k) => '$k'.startsWith('sort:')),
        isEmpty);
  });

  test('something unreadable kept counts as none', () async {
    await Hive.box('AppPrefs')
        .put('sort:${LibrarySortTags.albums}', {'type': 'Popularity'});
    expect(SortChoice.load(LibrarySortTags.albums), isNull);
  });

  test('Library › Albums loads sorted as last chosen', () async {
    // Stored in this order (Hive lists by key).
    await Hive.box('LibraryAlbums').putAll({
      'k1': _album('b', 'Second', 'Zed'),
      'k2': _album('a', 'First', 'Abba'),
      'k3': _album('c', 'Third', 'Moby'),
    });
    await SortChoice.save(LibrarySortTags.albums, SortType.Artist, true);
    final albums = LibraryAlbumsController()..onInit();
    while (albums.isContentFetched.isFalse) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(albums.libraryAlbums.map((a) => a.browseId), ['a', 'c', 'b']);

    // Never chosen: as stored.
    await Hive.box('AppPrefs').clear();
    final stored = LibraryAlbumsController()..onInit();
    while (stored.isContentFetched.isFalse) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(stored.libraryAlbums.map((a) => a.browseId), ['b', 'a', 'c']);
  });
}
