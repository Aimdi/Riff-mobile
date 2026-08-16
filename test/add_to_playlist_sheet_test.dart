import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/ui/widgets/add_to_playlist.dart';

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
}
