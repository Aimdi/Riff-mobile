import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/downloader.dart';
import 'package:harmonymusic/ui/widgets/add_to_playlist.dart';
import 'package:harmonymusic/ui/widgets/image_widget.dart';
import 'package:hive/hive.dart';

class _FakeDownloader extends GetxService implements Downloader {
  List<MediaItem>? got;

  @override
  Future<void> download(MediaItem? song,
          {List<MediaItem>? songList, bool signal = true}) async =>
      got = songList;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(Get.reset);

  test('a downloaded playlist stays whole when songs join it', () {
    final downloaded = {'a', 'b', 'x'};
    bool isDownloaded(String id) => downloaded.contains(id);
    const c = MediaItem(id: 'c', title: 'C');
    const x = MediaItem(id: 'x', title: 'X');
    final before = [
      {'videoId': 'a'},
      {'videoId': 'b'},
    ];
    expect(
        songsToKeepDownloaded(before, const [c, x], isDownloaded: isDownloaded)
            .map((s) => s.id),
        ['c']);
    // A song in it isn't downloaded: it isn't a downloaded playlist.
    expect(
        songsToKeepDownloaded([
          ...before,
          {'videoId': 'd'}
        ], const [
          c
        ], isDownloaded: isDownloaded),
        isEmpty);
    // A new, empty playlist: nothing to keep.
    expect(
        songsToKeepDownloaded(const [], const [c], isDownloaded: isDownloaded),
        isEmpty);
  });

  test('the songs go to the downloader', () {
    final downloader =
        Get.put<Downloader>(_FakeDownloader()) as _FakeDownloader;
    keepPlaylistDownloaded(const [MediaItem(id: 'c', title: 'C')]);
    expect(downloader.got?.map((s) => s.id), ['c']);
    downloader.got = null;
    keepPlaylistDownloaded(const []);
    expect(downloader.got, isNull);
  });

  test('playlist add copy matches the outcome', () {
    expect(
      playlistAddMessageKey(PlaylistAddOutcome.added),
      'songAddedToPlaylistAlert',
    );
    expect(
      playlistAddMessageKey(PlaylistAddOutcome.alreadyIn),
      'songAlreadyExists',
    );
    expect(
      playlistAddMessageKey(PlaylistAddOutcome.failed),
      'operationFailed',
    );
  });

  test('several songs (an album, a playlist) are spoken of as such', () {
    expect(playlistAddMessageKey(PlaylistAddOutcome.added, songs: 12),
        'songsAddedToPlaylistAlert');
    expect(playlistAddMessageKey(PlaylistAddOutcome.alreadyIn, songs: 12),
        'songsAlreadyInPlaylist');
    expect(playlistAddMessageKey(PlaylistAddOutcome.failed, songs: 12),
        'operationFailed');
  });

  group('songs written to your playlist', () {
    late Box box;
    setUp(() async {
      box = await Hive.openBox('PLmine', bytes: Uint8List(0));
      await box.add({'videoId': 'a', 'title': 'A'});
      await box.add({'videoId': 'b', 'title': 'B'});
    });
    tearDown(() => box.close());

    test('only the ones it lacks, each once, in their order', () async {
      final added = await addNewSongsToPlaylistBox(box, const [
        MediaItem(id: 'b', title: 'B'),
        MediaItem(id: 'c', title: 'C'),
        MediaItem(id: 'd', title: 'D'),
        // On the album or playlist twice: in once.
        MediaItem(id: 'c', title: 'C'),
      ]);
      expect(added.map((s) => s.id), ['c', 'd']);
      expect(
          box.values.map((e) => (e as Map)['videoId']), ['a', 'b', 'c', 'd']);
    });

    test('all there already: nothing', () async {
      final added = await addNewSongsToPlaylistBox(
          box, const [MediaItem(id: 'a', title: 'A')]);
      expect(added, isEmpty);
      expect(box.length, 2);
    });
  });

  test('a playlist has the songs only when it has every one of them', () {
    final entries = [
      {'videoId': 'a', 'title': 'A'},
      {'videoId': 'b', 'title': 'B'},
      'junk',
    ];
    expect(playlistHasAll(entries, {'a'}), isTrue);
    expect(playlistHasAll(entries, {'a', 'b'}), isTrue);
    expect(playlistHasAll(entries, {'a', 'c'}), isFalse);
    expect(playlistHasAll(entries, const {}), isFalse);
  });

  test('system library ids include Liked Songs and recents', () {
    expect(isSystemLibraryPlaylistId('LIBFAV'), isTrue);
    expect(isSystemLibraryPlaylistId('LIBRP'), isTrue);
    expect(isSystemLibraryPlaylistId('SongsCache'), isTrue);
    expect(isSystemLibraryPlaylistId('SongDownloads'), isTrue);
    expect(isSystemLibraryPlaylistId('LIB123'), isFalse);
  });

  test('user playlists drop pinned system rows', () {
    final filtered = userPlaylistsForAddSheet(fromLibrary: [
      Playlist(
        title: 'Favorites',
        playlistId: 'LIBFAV',
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false,
      ),
      Playlist(
        title: 'Recently played',
        playlistId: 'LIBRP',
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false,
      ),
      Playlist(
        title: 'Late night',
        playlistId: 'LIB999',
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false,
      ),
    ]);
    expect(filtered.map((p) => p.playlistId), ['LIB999']);
  });

  testWidgets('sheet pins Liked Songs then New playlist then user lists',
      (tester) async {
    // The sheet looks in your playlists for the song; this one is empty.
    await tester.runAsync(() => Hive.openBox('LIB999', bytes: Uint8List(0)));
    addTearDown(() => tester.runAsync(Hive.close));
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: AddToPlaylistSheet(
            songItems: const [MediaItem(id: 'song-1', title: 'Track')],
            playlistsOverride: [
              Playlist(
                title: 'Late night',
                playlistId: 'LIB999',
                thumbnailUrl: Playlist.thumbPlaceholderUrl,
                isCloudPlaylist: false,
              ),
              Playlist(
                title: 'Favorites',
                playlistId: 'LIBFAV',
                thumbnailUrl: Playlist.thumbPlaceholderUrl,
                isCloudPlaylist: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('favorites'), findsOneWidget);
    expect(find.text('CreateNewPlaylist'), findsOneWidget);
    expect(find.text('Late night'), findsOneWidget);
    expect(find.text('Favorites'), findsNothing);

    final fav = tester.getTopLeft(find.text('favorites'));
    final create = tester.getTopLeft(find.text('CreateNewPlaylist'));
    final user = tester.getTopLeft(find.text('Late night'));
    expect(fav.dy, lessThan(create.dy));
    expect(create.dy, lessThan(user.dy));

    // Your playlist shows its cover, as Spotify lists them.
    final row = find.ancestor(
        of: find.text('Late night'), matching: find.byType(ListTile));
    final cover = tester.widget<ImageWidget>(
        find.descendant(of: row, matching: find.byType(ImageWidget)));
    expect(cover.playlist?.playlistId, 'LIB999');
  });

  testWidgets('showAddToPlaylistSheet opens a modal', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddToPlaylistSheet(
              context,
              const [MediaItem(id: 'song-1', title: 'Track')],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AddToPlaylistSheet), findsOneWidget);
    expect(find.text('addToPlaylist'), findsOneWidget);
  });

  testWidgets('a check on Favorites and the playlists that have the song',
      (tester) async {
    await tester.runAsync(() async {
      await Hive.openBox('LIBFAV', bytes: Uint8List(0));
      await Hive.box('LIBFAV').put('song-1', {'videoId': 'song-1'});
      await Hive.openBox('LIB1', bytes: Uint8List(0));
      await Hive.box('LIB1').add({'videoId': 'song-1', 'title': 'Track'});
      await Hive.openBox('LIB2', bytes: Uint8List(0));
      await Hive.box('LIB2').add({'videoId': 'other', 'title': 'Other'});
    });
    addTearDown(() => tester.runAsync(Hive.close));
    Playlist mine(String id, String title) => Playlist(
          title: title,
          playlistId: id,
          thumbnailUrl: Playlist.thumbPlaceholderUrl,
          isCloudPlaylist: false,
        );
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: AddToPlaylistSheet(
            songItems: const [MediaItem(id: 'song-1', title: 'Track')],
            playlistsOverride: [
              mine('LIB1', 'Has it'),
              mine('LIB2', 'Not yet')
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    Finder checkIn(String title) => find.descendant(
        of: find.widgetWithText(ListTile, title),
        matching: find.byIcon(Icons.check_circle_rounded));
    expect(checkIn('favorites'), findsOneWidget);
    expect(checkIn('Has it'), findsOneWidget);
    expect(checkIn('Not yet'), findsNothing);
    expect(checkIn('CreateNewPlaylist'), findsNothing);
  });
}
