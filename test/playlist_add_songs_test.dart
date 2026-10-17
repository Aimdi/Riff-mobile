import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';
import 'package:harmonymusic/ui/screens/Playlist/add_songs_sheet.dart';
import 'package:harmonymusic/ui/screens/Playlist/playlist_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

/// Songs without art: rows draw the placeholder, no network.
MediaItem _song(String id) =>
    MediaItem(id: id, title: 'Song $id', artist: 'Artist $id');

/// YouTube Music's song search: [found] for any words.
class _FakeMusic extends GetxService implements MusicServices {
  final asked = <String>[];
  List<MediaItem> found = const [];

  @override
  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) async {
    asked.add('$query/$filter');
    return {'Songs': found, 'Videos': <dynamic>[]};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The library's copy of the playlist, told when its cover follows its
/// first song.
class _FakeLibrary extends GetxController
    implements LibraryPlaylistsController {
  @override
  void updatePlaylistIntoDb(Playlist playlist) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeMusic music;
  late PlaylistScreenController c;

  setUp(() async {
    final box = await Hive.openBox('LIB1', bytes: Uint8List(0));
    await box.add(MediaItemBuilder.toJson(_song('a')));
    music = Get.put<MusicServices>(_FakeMusic()) as _FakeMusic;
    Get.put<LibraryPlaylistsController>(_FakeLibrary());
    // Not put: no onInit, only the song list and adding to it.
    c = PlaylistScreenController();
    c.playlist.value = Playlist(
        title: 'Mine',
        playlistId: 'LIB1',
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false);
    c.songList.value = [_song('a')];
  });
  tearDown(() async {
    Get.reset();
    await Hive.box('LIB1').close();
  });

  test('songs only, as YouTube Music finds them', () async {
    music.found = [_song('x')];
    final found = await searchSongsToAdd('daft punk');
    expect(found.map((s) => s.id), ['x']);
    expect(music.asked, ['daft punk/songs']);
  });

  testWidgets('search as you type; + adds a song, a check marks the ones in it',
      (tester) async {
    music.found = [_song('a'), _song('b')];
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAddSongsSheet(context, c),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Labels show their keys: no translations loaded here.
    expect(find.text('addSongsHint'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'song');
    await tester.pump();
    expect(music.asked, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(music.asked, ['song/songs']);
    expect(find.text('Song a'), findsOneWidget);
    expect(find.text('Song b'), findsOneWidget);
    // Already in the playlist: a check; the other: +.
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    expect(c.songList.map((s) => s.id), ['a', 'b']);
    expect([for (final v in Hive.box('LIB1').values) (v as Map)['videoId']],
        ['a', 'b']);
  });
}
