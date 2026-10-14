import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/ui/widgets/add_to_playlist.dart';
import 'package:hive/hive.dart';

void main() {
  tearDown(Get.reset);

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

  test('countNewPlaylistSongs only counts ids that are not already there', () {
    expect(
      countNewPlaylistSongs(
        existingIds: ['a', 'b'],
        incomingIds: ['b', 'c', 'd'],
      ),
      2,
    );
    expect(
      countNewPlaylistSongs(
        existingIds: ['a'],
        incomingIds: ['a'],
      ),
      0,
    );
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
