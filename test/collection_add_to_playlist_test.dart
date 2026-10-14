import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/downloader.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Album/album_screen.dart';
import 'package:harmonymusic/ui/screens/Album/album_screen_controller.dart';
import 'package:harmonymusic/ui/screens/Playlist/playlist_screen.dart';
import 'package:harmonymusic/ui/screens/Playlist/playlist_screen_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/widgets/add_to_playlist.dart';
import 'package:hive/hive.dart';

import 'fakes/fake_music_services.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final buttonState = PlayButtonState.paused.obs;
  @override
  final playerPanelMinHeight = 0.0.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDownloader extends GetxService implements Downloader {
  @override
  RxMap<String, List<MediaItem>> playlistQueue =
      <String, List<MediaItem>>{}.obs;
  @override
  final currentPlaylistId = ''.obs;
  @override
  final playlistDownloadingProgress = 0.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final slidableActionEnabled = false.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A YouTube Music playlist or album of two songs.
class _Music extends FakeMusicServices {
  @override
  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs(
      {String? playlistId,
      String? albumId,
      int? limit,
      bool related = false,
      int suggestionsLimit = 0}) async {
    playlistCalls++;
    return {
      'title': 'Road trip',
      'tracks': const [
        MediaItem(id: 'aaaaaaaaaaa', title: 'First song'),
        MediaItem(id: 'bbbbbbbbbbb', title: 'Second song'),
      ],
    };
  }
}

/// Waits (in real time) until [done] holds.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('collection_add');
    Hive.init(tmp.path);
    await Hive.openBox('SongDownloads');
    Get.put<MusicServices>(_Music());
  });

  tearDown(() async {
    Get.reset();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  testWidgets("a playlist's ⋮ adds all its songs to a playlist",
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Get.put<PlayerController>(_FakePlayer());
    Get.put<Downloader>(_FakeDownloader());
    Get.put<SettingsScreenController>(_FakeSettings());
    final tag = const Key('PLroad').hashCode.toString();
    await tester.runAsync(() async {
      await tester.pumpWidget(GetMaterialApp(
        home: Builder(builder: (_) {
          Get.routing.args = [null, 'PLroad'];
          return const PlaylistScreen(key: Key('PLroad'));
        }),
      ));
      await _until(() =>
          Get.find<PlaylistScreenController>(tag: tag).isContentFetched.isTrue);
    });
    await tester.pump();
    expect(find.text('First song'), findsOneWidget);

    await tester.tap(find.byTooltip('more'));
    await tester.pumpAndSettle();
    // Someone else's playlist: Add to playlist (your own: to another one).
    await tester.tap(find.text('addToPlaylist'));
    await tester.pumpAndSettle();
    expect(find.byType(AddToPlaylistSheet), findsOneWidget);
    final sheet =
        tester.widget<AddToPlaylistSheet>(find.byType(AddToPlaylistSheet));
    expect(sheet.songItems.map((s) => s.id), ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
    expect(find.text('2 songs'), findsOneWidget);
  });

  testWidgets("an album's ⋮ adds the whole album to a playlist",
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Get.put<PlayerController>(_FakePlayer());
    Get.put<Downloader>(_FakeDownloader());
    Get.put<SettingsScreenController>(_FakeSettings());
    final tag = const Key('MPREroad').hashCode.toString();
    await tester.runAsync(() async {
      await tester.pumpWidget(GetMaterialApp(
        home: Builder(builder: (_) {
          Get.routing.args = (null, 'MPREroad');
          return const AlbumScreen(key: Key('MPREroad'));
        }),
      ));
      await _until(() =>
          Get.find<AlbumScreenController>(tag: tag).isContentFetched.isTrue);
    });
    await tester.pump();
    expect(find.text('Second song'), findsOneWidget);

    await tester.tap(find.byTooltip('more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('addToPlaylist'));
    await tester.pumpAndSettle();
    final sheet =
        tester.widget<AddToPlaylistSheet>(find.byType(AddToPlaylistSheet));
    expect(sheet.songItems.map((s) => s.id), ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
  });
}
