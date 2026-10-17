import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/pending_file_deletes.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/screens/Library/library_removal.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:hive/hive.dart';

class _FakeSettings extends GetxController implements SettingsScreenController {
  _FakeSettings(this.dir);
  final String dir;
  @override
  String get supportDirPath => dir;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  group('libraryFilesOf', () {
    test('download, listening cache and thumbnail', () {
      expect(
          libraryFilesOf(
              id: 'a',
              download: {'videoId': 'a', 'url': '/music/a.m4a'},
              cached: true,
              cacheDir: '/tmp',
              supportDir: '/support'),
          [
            '/music/a.m4a',
            '/tmp/cachedSongs/a.mp3',
            '/tmp/cachedSongs/a.mp3.mime',
            '/support/thumbnails/a.png',
          ]);
    });

    test('only files on the device', () {
      expect(
          libraryFilesOf(
              id: 'a',
              download: {'url': 'https://example.com/a'},
              cached: false,
              cacheDir: '/tmp',
              supportDir: '/support'),
          ['/support/thumbnails/a.png']);
      expect(
          libraryFilesOf(
              id: 'a',
              download: 'junk',
              cached: false,
              cacheDir: '/tmp',
              supportDir: '/support'),
          ['/support/thumbnails/a.png']);
    });
  });

  test('insertClamped puts it back, or at the end of a shorter list', () {
    final list = [1, 3];
    insertClamped(list, 1, 2);
    expect(list, [1, 2, 3]);
    final shorter = [1];
    insertClamped(shorter, 5, 2);
    expect(shorter, [1, 2]);
  });

  group('with Hive and files', () {
    late Directory tmp;
    late LibrarySongsController library;

    File file(String path) => File('${tmp.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    bool exists(String path) => File('${tmp.path}/$path').existsSync();
    Map pending() =>
        (Hive.box('AppPrefs').get(pendingFileDeletesKey) as Map?) ?? {};

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_lib_removal_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async => tmp.path);
      Hive.init('${tmp.path}/hive');
      await Hive.openBox('AppPrefs');
      await Hive.openBox('SongDownloads');
      await Hive.openBox('SongsCache');
      Get.put<SettingsScreenController>(_FakeSettings(tmp.path));
      // Not Get.put: onInit would scan the cache and start housekeeping.
      library = LibrarySongsController();
    });

    tearDown(() async {
      Get.reset();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('a song downloaded and cached too is listed once, as the download',
        () async {
      file('cachedSongs/a.mp3');
      file('cachedSongs/b.mp3');
      final download = file('music/a.m4a');
      await Hive.box('SongsCache').putAll({
        'a': {'videoId': 'a', 'title': 'A (cached)'},
        'b': {'videoId': 'b', 'title': 'B'},
      });
      await Hive.box('SongDownloads')
          .put('a', {'videoId': 'a', 'title': 'A', 'url': download.path});

      await library.init();
      expect(library.librarySongsList.map((s) => s.title), ['B', 'A']);
      // Its house keeping, done before the boxes close.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test('undo puts a cached song back where it was', () async {
      file('cachedSongs/b.mp3');
      await Hive.box('SongsCache').put('b', {'videoId': 'b', 'title': 'B'});
      const a = MediaItem(id: 'a', title: 'A');
      const b = MediaItem(id: 'b', title: 'B');
      const c = MediaItem(id: 'c', title: 'C');
      library.librarySongsList.value = [a, b, c];

      final removal = await library.takeOutOfLibrary(b);
      expect(removal, isNotNull);
      expect(library.librarySongsList.map((s) => s.id), ['a', 'c']);
      // Gone from the library, so it doesn't come back on the next start…
      expect(Hive.box('SongsCache').containsKey('b'), isFalse);
      // …but its file waits for Undo.
      expect(exists('cachedSongs/b.mp3'), isTrue);
      expect(pending().keys, ['b']);

      await library.undoRemoval(removal!);
      expect(library.librarySongsList.map((s) => s.id), ['a', 'b', 'c']);
      expect(Hive.box('SongsCache').get('b'), {'videoId': 'b', 'title': 'B'});
      expect(exists('cachedSongs/b.mp3'), isTrue);
      expect(pending(), isEmpty);
    });

    test('without undo, the download and its thumbnail are deleted', () async {
      final song = file('music/a.m4a');
      file('thumbnails/a.png');
      await Hive.box('SongDownloads')
          .put('a', {'videoId': 'a', 'title': 'A', 'url': song.path});
      const a = MediaItem(id: 'a', title: 'A');
      library.librarySongsList.value = [a];

      final removal = await library.takeOutOfLibrary(a);
      expect(Hive.box('SongDownloads').containsKey('a'), isFalse);
      expect(exists('music/a.m4a'), isTrue);

      await library.commitRemoval(removal!);
      expect(exists('music/a.m4a'), isFalse);
      expect(exists('thumbnails/a.png'), isFalse);
      expect(pending(), isEmpty);
    });

    test('a song back in the library meanwhile keeps its files', () async {
      file('cachedSongs/b.mp3');
      await Hive.box('SongsCache').put('b', {'videoId': 'b'});
      const b = MediaItem(id: 'b', title: 'B');
      library.librarySongsList.value = [b];

      final removal = await library.takeOutOfLibrary(b);
      // Played again before Undo timed out: cached afresh.
      await Hive.box('SongsCache').put('b', {'videoId': 'b'});
      await library.commitRemoval(removal!);
      expect(exists('cachedSongs/b.mp3'), isTrue);
    });

    test('a song not in the library is left alone', () async {
      expect(
          await library.takeOutOfLibrary(const MediaItem(id: 'x', title: 'X')),
          isNull);
    });

    test('files a closed app left behind go on the next start', () async {
      final left = file('cachedSongs/gone.mp3');
      final kept = file('cachedSongs/back.mp3');
      final prefs = Hive.box('AppPrefs');
      await markPendingFiles(prefs, 'gone', [left.path]);
      await markPendingFiles(prefs, 'back', [kept.path]);

      await purgePendingFiles(prefs, keep: (id) => id == 'back');
      expect(left.existsSync(), isFalse);
      expect(kept.existsSync(), isTrue);
      expect(pending(), isEmpty);
    });
  });
}
