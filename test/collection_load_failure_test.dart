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
import 'package:harmonymusic/ui/widgets/shimmer_widgets/song_list_shimmer.dart';
import 'package:harmonymusic/utils/get_localization.dart';
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

/// Waits (in real time) until [done] holds.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory tmp;
  late FakeMusicServices music;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('album_load');
    Hive.init(tmp.path);
    await Hive.openBox('SongDownloads');
    music = FakeMusicServices();
    Get.put<MusicServices>(music);
  });

  tearDown(() async {
    Get.reset();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('a failed album load ends the loading state', () async {
    music.error = Exception('offline');
    final c = AlbumScreenController();
    c.fetchAlbumDetails(null, 'MPREfail');
    await _until(() => c.isContentFetched.isTrue);
    expect(music.playlistCalls, 1);
    // Was: never set, so the track list shimmered forever.
    expect(c.isContentFetched.isTrue, isTrue);
    expect(c.songList, isEmpty);
  });

  testWidgets('the album page leaves the shimmer when the load fails',
      (tester) async {
    music.error = Exception('offline');
    Get.put<PlayerController>(_FakePlayer());
    Get.put<Downloader>(_FakeDownloader());
    await tester.runAsync(() async {
      await tester.pumpWidget(GetMaterialApp(
        translations: Languages(),
        locale: const Locale('en'),
        home: Builder(builder: (_) {
          // What the nested navigator passes as route arguments.
          Get.routing.args = (null, 'MPREfail');
          return const AlbumScreen(key: Key('MPREfail'));
        }),
      ));
      // Hive's box open and the failing request run on real time.
      await _until(() => Get.find<AlbumScreenController>(
              tag: const Key('MPREfail').hashCode.toString())
          .isContentFetched
          .isTrue);
    });
    await tester.pump();
    final c = Get.find<AlbumScreenController>(
        tag: const Key('MPREfail').hashCode.toString());
    expect(c.isContentFetched.isTrue, isTrue);
    expect(find.byType(SongListShimmer), findsNothing);
    expect(find.text('emptyPlaylist'.tr), findsOneWidget);
  });

  testWidgets('the playlist page leaves the shimmer when the load fails',
      (tester) async {
    music.error = Exception('offline');
    Get.put<PlayerController>(_FakePlayer());
    Get.put<Downloader>(_FakeDownloader());
    final tag = const Key('PLfail').hashCode.toString();
    await tester.runAsync(() async {
      await tester.pumpWidget(GetMaterialApp(
        translations: Languages(),
        locale: const Locale('en'),
        home: Builder(builder: (_) {
          Get.routing.args = [null, 'PLfail'];
          return const PlaylistScreen(key: Key('PLfail'));
        }),
      ));
      await _until(() =>
          Get.find<PlaylistScreenController>(tag: tag).isContentFetched.isTrue);
    });
    await tester.pump();
    expect(music.playlistCalls, 1);
    // Was: the list's Obx never read isContentFetched behind the empty
    // list, so it kept the shimmer after the failed load.
    expect(find.byType(SongListShimmer), findsNothing);
    expect(find.text('emptyPlaylist'.tr), findsOneWidget);
  });
}
