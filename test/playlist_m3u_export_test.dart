import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/csv_playlist_import.dart';
import 'package:harmonymusic/services/m3u_playlist_import.dart';
import 'package:harmonymusic/ui/screens/Playlist/playlist_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/playlist_export_dialog.dart';
import 'package:harmonymusic/utils/get_localization.dart';

const _songs = [
  MediaItem(
      id: 'dQw4w9WgXcQ',
      title: 'Never Gonna Give You Up',
      artist: 'Rick Astley',
      duration: Duration(seconds: 213)),
  MediaItem(
      id: 'kJQP7kiw5Fk',
      title: 'Despacito\n(Remix)',
      artist: 'Luis Fonsi, Daddy Yankee'),
  MediaItem(
      id: 'device_42',
      title: 'Voice memo',
      extras: {'url': 'content://media/external/audio/media/42'}),
  MediaItem(id: 'cloud_7', title: 'Home song', artist: 'Me', extras: {
    'url': 'https://music.example.com/rest/stream.view?id=7&u=me&t=secret'
  }),
];

class _FakePlaylist extends GetxController implements PlaylistScreenController {
  final exported = <String>[];

  @override
  Future<void> exportPlaylistToM3u(BuildContext context) async =>
      exported.add('m3u');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a playlist as M3U: lengths, "Artist - Title", YouTube Music links', () {
    final m3u = playlistM3u('Road trip', _songs);
    expect(
        m3u,
        '#EXTM3U\n'
        '#PLAYLIST:Road trip\n'
        '#EXTINF:213,Rick Astley - Never Gonna Give You Up\n'
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ\n'
        '#EXTINF:-1,Luis Fonsi, Daddy Yankee - Despacito (Remix)\n'
        'https://music.youtube.com/watch?v=kJQP7kiw5Fk\n'
        '#EXTINF:-1,Voice memo\n'
        'content://media/external/audio/media/42\n'
        '#EXTINF:-1,Me - Home song\n'
        'cloud_7\n');
    // A song from your own server: never its link with the login in it.
    expect(m3u, isNot(contains('secret')));
  });

  test('Riff reads its own M3U back song for song', () {
    final p = parsePlaylistM3u(playlistM3u('Road trip', _songs.take(2)));
    expect(p.name, 'Road trip');
    expect(
        p.tracks.map((t) => (t.title, t.artists, t.youtubeId, t.durationMs)), [
      ('Never Gonna Give You Up', 'Rick Astley', 'dQw4w9WgXcQ', 213000),
      ('Despacito (Remix)', 'Luis Fonsi, Daddy Yankee', 'kJQP7kiw5Fk', null),
    ]);
  });

  test("Riff's own CSV export comes back exactly: its name, ids and lengths",
      () {
    const csv = 'PlaylistBrowseId,PlaylistName,MediaId,Title,Artists,Duration,'
        'ThumbnailUrl,AlbumId,AlbumTitle,ArtistIds\n'
        ',Road trip,dQw4w9WgXcQ,Never Gonna Give You Up,Rick Astley,03:33,'
        'https://i.ytimg.com/x.jpg,MPREb_1,Whenever,UC1\n'
        ',Road trip,kJQP7kiw5Fk,Despacito,"Luis Fonsi, Daddy Yankee",01:02:03,'
        ',,,"UC2,UC3"\n';
    final p = parsePlaylistCsv(csv);
    expect(p.name, 'Road trip');
    expect(
        p.tracks.map((t) => (t.title, t.artists, t.youtubeId, t.durationMs)), [
      ('Never Gonna Give You Up', 'Rick Astley', 'dQw4w9WgXcQ', 213000),
      ('Despacito', 'Luis Fonsi, Daddy Yankee', 'kJQP7kiw5Fk', 3723000),
    ]);
  });

  test('a CSV with YouTube links, and lengths in seconds or milliseconds', () {
    const csv = 'Title,Artist,Duration,URL\n'
        'Song,Band,215,https://youtu.be/dQw4w9WgXcQ\n'
        'Other,Band,215000,https://example.com/x\n'
        'Third,Band,,https://www.youtube.com/playlist?list=PL1\n';
    expect(parsePlaylistCsv(csv).tracks.map((t) => (t.durationMs, t.youtubeId)),
        [(215000, 'dQw4w9WgXcQ'), (215000, null), (null, null)]);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Export offers M3U, the dialog fitting a phone at ${scale}x',
        (tester) async {
      Get.addTranslations(Languages().keys);
      Get.locale = const Locale('en');
      addTearDown(Get.clearTranslations);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final playlist = _FakePlaylist();
      await tester.pumpWidget(GetMaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => PlaylistExportDialog(
                        controller: playlist, parentContext: context)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
          find.text('Opens in spreadsheets; imports here too'), findsOneWidget);
      await tester.ensureVisible(find.text('Close'));
      await tester.ensureVisible(find.text('Export playlist as M3U'));
      await tester.tap(find.text('Export playlist as M3U'));
      await tester.pumpAndSettle();
      expect(playlist.exported, ['m3u']);
    });
  }
}
