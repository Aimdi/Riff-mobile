import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/screens/Library/library_pins.dart';
import 'package:harmonymusic/ui/widgets/content_list_widget_item.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart';
import 'package:hive/hive.dart';

Playlist _pl(String id, [String? title]) => Playlist(
      title: title ?? id,
      playlistId: id,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    );

List<String> _ids(Iterable<Playlist> playlists) =>
    [for (final p in playlists) p.playlistId];

/// Pins go to the real store; the rest of the controller isn't needed.
class _FakeLibrary extends GetxController
    implements LibraryPlaylistsController {
  @override
  Future<bool> togglePin(Playlist playlist) =>
      LibraryPins.toggle(playlist.playlistId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const own = ['LIBRP', 'LIBFAV', 'SongsCache', 'SongDownloads'];

  group('orderLibraryPlaylists', () {
    final fixed = own.toSet();
    final list = [
      for (final id in [...own, 'a', 'b', 'c', 'd']) _pl(id)
    ];

    test("Riff's own first, then the pins in pin order, then the rest", () {
      expect(_ids(orderLibraryPlaylists(list, ['c', 'a'], fixed)),
          [...own, 'c', 'a', 'b', 'd']);
    });

    test("pins that aren't there, or of Riff's own, change nothing", () {
      expect(_ids(orderLibraryPlaylists(list, ['gone', 'LIBFAV'], fixed)),
          [...own, 'a', 'b', 'c', 'd']);
    });

    test('search results are ordered the same way', () {
      final found = [list[1], list[4], list[6]]; // LIBFAV, a, c
      expect(_ids(orderLibraryPlaylists(found, ['c'], fixed)),
          ['LIBFAV', 'c', 'a']);
    });
  });

  group('with prefs', () {
    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    });
    tearDown(() async {
      Get.reset();
      await Hive.box('AppPrefs').close();
    });

    test('pins go on top of the others; a second toggle unpins', () async {
      expect(await LibraryPins.toggle('a'), isTrue);
      expect(await LibraryPins.toggle('b'), isTrue);
      expect(LibraryPins.ids, ['b', 'a']);
      expect(await LibraryPins.toggle('a'), isTrue);
      expect(LibraryPins.ids, ['b']);
      expect(LibraryPins.isPinned('a'), isFalse);
    });

    test('four at most; pins of playlists gone from the library make room',
        () async {
      for (final id in ['a', 'b', 'c', 'd']) {
        await LibraryPins.toggle(id);
      }
      expect(await LibraryPins.toggle('e'), isFalse);
      expect(await LibraryPins.toggle('e', library: {'a', 'b', 'c', 'd', 'e'}),
          isFalse);
      // 'b' left the library some other way (a sync, another device).
      expect(
          await LibraryPins.toggle('e', library: {'a', 'c', 'd', 'e'}), isTrue);
      expect(LibraryPins.ids, ['e', 'd', 'c', 'a']);
    });

    test('forget drops a pin', () async {
      await LibraryPins.toggle('a');
      final rev = LibraryPins.rev.value;
      await LibraryPins.forget('b');
      expect(LibraryPins.rev.value, rev);
      await LibraryPins.forget('a');
      expect(LibraryPins.ids, isEmpty);
      expect(LibraryPins.rev.value, rev + 1);
    });

    test('pinned playlists stay on top through sorting and search', () async {
      // Not Get.put: onInit would load the library from disk.
      final library = LibraryPlaylistsController();
      library.libraryPlaylists.value = [
        ...LibraryPlaylistsController.initPlst,
        _pl('b', 'Bravo'),
        _pl('c', 'Charlie'),
        _pl('a', 'Alpha'),
      ];
      library.onSort(SortType.Name, true);
      expect(_ids(library.libraryPlaylists), [...own, 'a', 'b', 'c']);

      expect(await library.togglePin(_pl('c')), isTrue);
      expect(_ids(library.libraryPlaylists), [...own, 'c', 'a', 'b']);
      library.onSort(SortType.Name, false);
      expect(_ids(library.libraryPlaylists), [...own, 'c', 'b', 'a']);
      library.onSort(SortType.Name, true);
      expect(_ids(library.libraryPlaylists), [...own, 'c', 'a', 'b']);

      // Unpinned, it goes back to its place in the sort.
      expect(await library.togglePin(_pl('c')), isTrue);
      expect(_ids(library.libraryPlaylists), [...own, 'a', 'b', 'c']);

      // Pinned from search results: on top when the search closes.
      library.onSearchStart(null);
      library.onSearch('Charlie', null);
      expect(_ids(library.libraryPlaylists), ['c']);
      expect(await library.togglePin(_pl('c')), isTrue);
      library.onSearchClose(null);
      expect(_ids(library.libraryPlaylists), [...own, 'c', 'a', 'b']);
    });

    group('Library card', () {
      setUp(() {
        Get.put<LibraryPlaylistsController>(_FakeLibrary());
      });

      Future<void> pumpCard(WidgetTester tester, Playlist playlist,
          {bool isLibraryItem = true}) async {
        // A phone-sized screen, so the whole menu fits.
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(GetMaterialApp(
          home: Scaffold(
            body: ContentListItem(
                content: playlist, isLibraryItem: isLibraryItem),
          ),
        ));
      }

      Future<void> openMenu(WidgetTester tester) async {
        await tester.longPress(find.byType(ContentListItem));
        await tester.pumpAndSettle();
      }

      testWidgets('the menu pins and unpins; a pin marks the card',
          (tester) async {
        await pumpCard(tester, _pl('mix', 'Road trip'));
        expect(find.byIcon(Icons.push_pin_rounded), findsNothing);

        await openMenu(tester);
        await tester.tap(find.text('pinPlaylist'));
        await tester.pumpAndSettle();
        expect(LibraryPins.ids, ['mix']);
        expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
        expect(find.text('playlistPinned'), findsOneWidget);

        await openMenu(tester);
        await tester.tap(find.text('unpinPlaylist'));
        await tester.pumpAndSettle();
        expect(LibraryPins.ids, isEmpty);
        expect(find.byIcon(Icons.push_pin_rounded), findsNothing);
        expect(find.text('playlistUnpinned'), findsOneWidget);
      });

      testWidgets('says so when four are pinned already', (tester) async {
        for (final id in ['a', 'b', 'c', 'd']) {
          await LibraryPins.toggle(id);
        }
        await pumpCard(tester, _pl('mix', 'Road trip'));
        await openMenu(tester);
        await tester.tap(find.text('pinPlaylist'));
        await tester.pumpAndSettle();
        expect(LibraryPins.isPinned('mix'), isFalse);
        expect(find.text('pinPlaylistLimit'), findsOneWidget);
      });

      testWidgets("Riff's own playlists and cards elsewhere have no pin",
          (tester) async {
        await pumpCard(tester, _pl('LIBFAV', 'favorites'));
        await openMenu(tester);
        expect(find.text('viewAll'), findsOneWidget);
        expect(find.text('pinPlaylist'), findsNothing);
        await tester.tapAt(const Offset(10, 10)); // closes the menu
        await tester.pumpAndSettle();

        await pumpCard(tester, _pl('mix', 'Road trip'), isLibraryItem: false);
        await openMenu(tester);
        expect(find.text('viewAll'), findsOneWidget);
        expect(find.text('pinPlaylist'), findsNothing);
      });
    });
  });
}
