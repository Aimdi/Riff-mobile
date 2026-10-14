import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/downloader.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/songinfo_bottom_sheet.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final playinfrom = PlaylingFrom(type: PlaylingFromType.SELECTION).obs;
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDownloader extends GetxService implements Downloader {
  @override
  MediaItem? currentSong;
  @override
  final songDownloadingProgress = 0.obs;
  @override
  final isJobRunning = false.obs;
  @override
  RxList<MediaItem> songQueue = <MediaItem>[].obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _song(String id) =>
    MediaItem(id: id, title: 'Song $id', artist: 'Band');

Playlist _playlist(String id,
        {String title = 'Road trip', bool cloud = false, bool piped = false}) =>
    Playlist(
        title: title,
        playlistId: id,
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: cloud,
        isPipedPlaylist: piped);

PlaylingFrom _from(Playlist playlist,
        {PlaylingFromType type = PlaylingFromType.PLAYLIST}) =>
    PlaylingFrom(
        type: type,
        name: playlist.title,
        id: playlist.playlistId,
        item: playlist);

/// A box kept in memory: what's written is there at once, with no disk
/// for the tests' fake time to wait on.
Future<Box> _box(String name) async => Hive.isBoxOpen(name)
    ? Hive.box(name)
    : await Hive.openBox(name, bytes: Uint8List(0));

/// [playlist] in the Library, with [songs] in it.
Future<void> _save(Playlist playlist, List<String> songs) async {
  await Hive.box('LibraryPlaylists')
      .put(playlist.playlistId, playlist.toJson());
  final box = await _box(playlist.playlistId);
  await box.putAll({
    for (final (i, id) in songs.indexed) i: MediaItemBuilder.toJson(_song(id))
  });
}

List<String> _ids(String playlistId) => Hive.box(playlistId)
    .values
    .map((v) => (v as Map)['videoId'] as String)
    .toList();

void main() {
  late Directory tmp;
  late _FakePlayer player;

  setUp(() async {
    Get.reset();
    tmp = await Directory.systemTemp.createTemp('riff_playing_playlist');
    Hive.init(p.join(tmp.path, 'hive'));
    for (final name in ['LibraryPlaylists', 'LIBFAV', 'SongDownloads']) {
      await _box(name);
    }
    player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    Get.put<Downloader>(_FakeDownloader());
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
    tmp.deleteSync(recursive: true);
  });

  test('yours: a playlist you made or imported, not the Library lists', () {
    expect(isYourPlaylist(_playlist('LIB1700000000000')), isTrue);
    expect(isYourPlaylist(_playlist('LIBSP1700000000000')), isTrue);
    // YouTube Music's, Piped's, a mix Riff makes.
    expect(isYourPlaylist(_playlist('PLabc', cloud: true)), isFalse);
    expect(isYourPlaylist(_playlist('abc', cloud: true, piped: true)), isFalse);
    expect(isYourPlaylist(_playlist('RIFF_daily1')), isFalse);
    // Favorites has the heart; the rest aren't playlists you edit.
    for (final id in ['LIBFAV', 'LIBRP', 'SongDownloads', 'SongsCache']) {
      expect(isYourPlaylist(_playlist(id)), isFalse, reason: id);
    }
  });

  test('the playlist playing, as the Library has it, when the song is in it',
      () async {
    final road = _playlist('LIB1');
    await _save(road, ['a', 'b']);
    // Renamed since it started.
    await Hive.box('LibraryPlaylists')
        .put('LIB1', _playlist('LIB1', title: 'Road trip 2026').toJson());

    final found = await yourPlaylistPlaying(_from(road), _song('b'));
    expect(found?.playlistId, 'LIB1');
    expect(found?.title, 'Road trip 2026');

    // A song you queued, not in it.
    expect(await yourPlaylistPlaying(_from(road), _song('x')), isNull);
    // An album or a selection playing.
    expect(
        await yourPlaylistPlaying(
            _from(road, type: PlaylingFromType.ALBUM), _song('b')),
        isNull);
    expect(
        await yourPlaylistPlaying(
            PlaylingFrom(type: PlaylingFromType.PLAYLIST, name: 'Liked'),
            _song('b')),
        isNull);
  });

  test('nothing to take out of a mix, a YouTube Music or a deleted playlist',
      () async {
    final mix = _playlist('RIFF_daily1');
    await _save(mix, ['a']);
    expect(await yourPlaylistPlaying(_from(mix), _song('a')), isNull);

    final yt = _playlist('PLabc', cloud: true);
    await _save(yt, ['a']);
    expect(await yourPlaylistPlaying(_from(yt), _song('a')), isNull);

    // Deleted while it plays: gone from the Library.
    final gone = _playlist('LIB2');
    await _save(gone, ['a']);
    await Hive.box('LibraryPlaylists').delete('LIB2');
    expect(await yourPlaylistPlaying(_from(gone), _song('a')), isNull);
  });

  group('the song menu', () {
    Future<void> open(WidgetTester tester, MediaItem song,
        {bool fromPlayer = false, bool fromQueue = false}) async {
      await tester.pumpWidget(GetMaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => SongInfoBottomSheet(song,
                    calledFromPlayer: fromPlayer, calledFromQueue: fromQueue),
              ).whenComplete(() => Get.delete<SongInfoController>()),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Finder removeTile() => find.ancestor(
        of: find.text('removeFromPlaylist'), matching: find.byType(InkWell));

    testWidgets('the player ⋮ takes the song out of your playlist playing',
        (tester) async {
      final road = _playlist('LIB1');
      await _save(road, ['a', 'b', 'c']);
      player.playinfrom.value = _from(road);
      player.currentSong.value = _song('b');

      await open(tester, _song('b'), fromPlayer: true);
      // `.tr` gives the key in tests; the playlist's name under it.
      expect(find.text('removeFromPlaylist'), findsOneWidget);
      expect(find.text('Road trip'), findsOneWidget);

      await tester.ensureVisible(removeTile());
      await tester.tap(removeTile());
      await tester.pumpAndSettle();
      expect(_ids('LIB1'), ['a', 'c']);
      expect(find.text('removedFromPlaylist'), findsOneWidget);

      // Undo puts it back where it was.
      await tester.tap(find.text('undo'));
      await tester.pumpAndSettle();
      expect(_ids('LIB1'), ['a', 'b', 'c']);
    });

    testWidgets('Up Next offers it too; not for a song not in the playlist',
        (tester) async {
      final road = _playlist('LIB1');
      await _save(road, ['a', 'b']);
      player.playinfrom.value = _from(road);

      await open(tester, _song('a'), fromQueue: true);
      expect(find.text('removeFromPlaylist'), findsOneWidget);
      Navigator.of(tester.element(find.text('removeFromPlaylist'))).pop();
      await tester.pumpAndSettle();

      // One you queued, not in the playlist.
      await open(tester, _song('x'), fromQueue: true);
      expect(find.text('removeFromPlaylist'), findsNothing);
    });

    testWidgets('a song opened anywhere else has no player removal',
        (tester) async {
      final road = _playlist('LIB1');
      await _save(road, ['a']);
      player.playinfrom.value = _from(road);

      // From search results, say: no playlist given, not the player's.
      await open(tester, _song('a'));
      expect(find.text('removeFromPlaylist'), findsNothing);
    });
  });
}
