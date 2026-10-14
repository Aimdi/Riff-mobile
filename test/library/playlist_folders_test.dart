import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/playlist_folders.dart';
import 'package:harmonymusic/ui/navigator.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/screens/Library/playlist_folder_ui.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

Playlist _playlist(String id) => Playlist(
    title: 'Playlist $id',
    playlistId: id,
    thumbnailUrl: Playlist.thumbPlaceholderUrl,
    isCloudPlaylist: false);

class _Library extends GetxController implements LibraryPlaylistsController {
  _Library(List<Playlist> playlists) {
    libraryPlaylists = playlists.obs;
  }

  @override
  late RxList<Playlist> libraryPlaylists;

  @override
  List<Playlist> tempListContainer = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    PlaylistFolders.rev.value = 0;
  });
  tearDown(() async {
    Get.reset();
    await Hive.box('AppPrefs').close();
  });

  List<String> filed(String folderId) =>
      PlaylistFolders.byId(folderId)!.playlists;

  group('folders', () {
    test('made with a playlist in it, which moves from folder to folder',
        () async {
      final chill = await PlaylistFolders.create(' Chill ', playlistId: 'a');
      final work = await PlaylistFolders.create('Work');
      expect(PlaylistFolders.folders.map((f) => f.name), ['Chill', 'Work']);
      expect(filed(chill.id), ['a']);
      expect(PlaylistFolders.folderOf('a')?.id, chill.id);

      await PlaylistFolders.move('b', work.id);
      await PlaylistFolders.move('a', work.id);
      expect(filed(chill.id), isEmpty);
      expect(filed(work.id), ['b', 'a']);

      // Out of any folder.
      await PlaylistFolders.move('b', null);
      expect(filed(work.id), ['a']);
      expect(PlaylistFolders.folderOf('b'), isNull);
      // A playlist that leaves the Library leaves its folder.
      await PlaylistFolders.forget('a');
      expect(filed(work.id), isEmpty);
      expect(PlaylistFolders.rev.value, greaterThan(0));
    });

    test('renamed, but not to nothing', () async {
      final f = await PlaylistFolders.create('Gym');
      await PlaylistFolders.rename(f.id, '  Running ');
      expect(PlaylistFolders.byId(f.id)!.name, 'Running');
      await PlaylistFolders.rename(f.id, '   ');
      expect(PlaylistFolders.byId(f.id)!.name, 'Running');
    });

    test('deleted, and put back where it was (Undo)', () async {
      final one = await PlaylistFolders.create('One', playlistId: 'a');
      await PlaylistFolders.move('b', one.id);
      await PlaylistFolders.create('Two');
      final deleted = await PlaylistFolders.delete(one.id);
      expect(PlaylistFolders.folders.map((f) => f.name), ['Two']);
      expect(PlaylistFolders.folderOf('a'), isNull);

      // Meanwhile b went into another folder: it stays there.
      await PlaylistFolders.move('b', PlaylistFolders.folders.single.id);
      await PlaylistFolders.restore(deleted!.$1, deleted.$2);
      expect(PlaylistFolders.folders.map((f) => f.name), ['One', 'Two']);
      expect(filed(one.id), ['a']);
      expect(await PlaylistFolders.delete('nonsense'), isNull);
    });

    test("one that can't be read is left out", () async {
      await Hive.box('AppPrefs').put(PlaylistFolders.key, [
        'junk',
        {'id': '', 'name': 'No id'},
        {
          'id': 'f1',
          'name': 'Fine',
          'playlists': ['a']
        },
      ]);
      expect(PlaylistFolders.folders.map((f) => f.name), ['Fine']);
    });
  });

  group('Library › Playlists with folders', () {
    final own = _playlist('LIBFAV');
    final pinned = _playlist('PLpinned');
    final a = _playlist('PLa');
    final b = _playlist('PLb');
    final c = _playlist('PLc');
    bool leading(String id) => id == 'LIBFAV' || id == 'PLpinned';
    const folder =
        PlaylistFolder(id: 'f', name: 'Folder', playlists: ['PLb', 'PLpinned']);

    test('folders after the own and pinned ones, filed playlists inside', () {
      expect(
          libraryPlaylistItems([own, pinned, a, b, c], [folder],
              leading: leading),
          [own, pinned, folder, a, c]);
    });

    test('searching finds them all, folders aside', () {
      expect(
          libraryPlaylistItems([b, c], [folder],
              leading: leading, searching: true),
          [b, c]);
    });

    test('no folders: as before', () {
      expect(
          libraryPlaylistItems([own, a], const [], leading: leading), [own, a]);
    });

    test("a folder's playlists in its order, those still in the Library", () {
      expect(folderPlaylists(folder, [a, b, pinned]), [b, pinned]);
    });
  });

  Future<void> pumpTile(WidgetTester tester, PlaylistFolder folder,
      {int count = 0}) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: Navigator(
          key: Get.nestedKey(ScreenNavigationSetup.id),
          onGenerateRoute: (settings) => MaterialPageRoute(
            settings: settings,
            builder: (_) => PlaylistFolderTile(
                folder: folder, count: count, size: 120, asRow: true),
          ),
        ),
      ),
    ));
  }

  testWidgets("a folder's tile opens its page, with its playlists",
      (tester) async {
    late PlaylistFolder folder;
    await tester.runAsync(() async {
      folder = await PlaylistFolders.create('Chill', playlistId: 'PLa');
    });
    Get.put<LibraryPlaylistsController>(
        _Library([_playlist('PLa'), _playlist('PLb')]));
    await pumpTile(tester, folder, count: 1);
    expect(find.text('Chill'), findsOneWidget);
    expect(find.text('folderPlaylistsOne'), findsOneWidget);

    await tester.tap(find.text('Chill'));
    await tester.pumpAndSettle();
    // Its page: the folder's playlist, not the other.
    expect(find.text('Playlist PLa'), findsWidgets);
    expect(find.text('Playlist PLb'), findsNothing);
  });

  testWidgets('an empty folder says how to fill it', (tester) async {
    late PlaylistFolder folder;
    await tester.runAsync(() async {
      folder = await PlaylistFolders.create('Empty');
    });
    await pumpTile(tester, folder);
    await tester.tap(find.text('Empty'));
    await tester.pumpAndSettle();
    expect(find.text('folderEmptyDes'), findsOneWidget);
  });

  testWidgets('Move to folder › New folder makes one with the playlist in it',
      (tester) async {
    final playlist = _playlist('PLmine');
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMoveToFolderSheet(context, playlist),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('newFolder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Road trip');
    await tester.runAsync(() async {
      await tester.tap(find.text('create'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(PlaylistFolders.folders.single.name, 'Road trip');
    expect(PlaylistFolders.folderOf('PLmine')?.name, 'Road trip');
  });
}
