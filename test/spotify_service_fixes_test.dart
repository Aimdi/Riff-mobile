import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/spotify_api_service.dart';
import 'package:harmonymusic/services/spotify_auth_service.dart';
import 'package:harmonymusic/services/spotify_import_service.dart';
import 'package:harmonymusic/services/spotify_match_store.dart';
import 'package:harmonymusic/services/spotify_playback.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);
  final String body;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream,
          Future<void>? cancelFuture) async =>
      ResponseBody.fromString(body, 200);

  @override
  void close({bool force = false}) {}
}

/// Resolves every track to a song with the same id, after a moment.
class _FakeImporter extends GetxService implements SpotifyImportService {
  void Function()? onFirstResolve;

  MediaItem _item(SpotifyTrackRef t) =>
      MediaItem(id: 'yt_${t.id}', title: t.title);

  @override
  Future<MediaItem?> resolveTrack(SpotifyTrackRef t) async {
    onFirstResolve?.call();
    onFirstResolve = null;
    return _item(t);
  }

  @override
  Future<List<MediaItem?>> resolveTracksDetailed(List<SpotifyTrackRef> tracks,
          {void Function(int done, int total)? onProgress,
          int concurrency = 3}) async =>
      [for (final t in tracks) _item(t)];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentQueue = <MediaItem>[].obs;

  @override
  Future<bool> playPlayListSong(List<MediaItem> mediaItems, int index,
      {dynamic playfrom, dynamic source}) async {
    currentQueue.assignAll(mediaItems);
    return true;
  }

  @override
  Future<bool> enqueueSongList(List<MediaItem> mediaItems) async {
    currentQueue.addAll(mediaItems);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SpotifyTrackRef _ref(String id) =>
    SpotifyTrackRef(id: id, title: 'Song $id', artists: 'A');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('with storage', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('spotify_fixes');
      Hive.init(p.join(tmp.path, 'hive'));
    });
    tearDown(() async {
      await Hive.deleteFromDisk();
      tmp.deleteSync(recursive: true);
    });

    test('a picked match is used even before anything opened the store',
        () async {
      const picked = MediaItem(id: 'pickedVid', title: 'Right one', extras: {});
      await SpotifyMatchStore.putManual('sp1', picked);
      // A fresh launch: nothing has opened the box yet.
      await Hive.box(SpotifyMatchStore.box).close();

      // No MusicServices is registered, so a search would throw.
      final item = await SpotifyImportService().resolveTrack(_ref('sp1'));
      expect(item?.id, 'pickedVid');
    });

    test('stale cached answers are pruned, fresh ones kept', () async {
      final box = await Hive.openBox('spotify_cache_prune_test');
      final now = DateTime.now().millisecondsSinceEpoch;
      final old = now - SpotifyApiService.libraryTtl.inMilliseconds - 60 * 1000;
      await box.putAll({
        'fresh': {'at': now - 1000, 'body': '{}'},
        'old': {'at': old, 'body': '{}'},
        'broken': 'not a map',
        'noTime': {'body': '{}'},
      });
      expect(await SpotifyApiService.pruneCache(box, now), 3);
      expect(box.keys, ['fresh']);
    });
  });

  test('followed artists of an unexpected shape are skipped, not a crash',
      () async {
    final api = SpotifyApiService(
      auth: SpotifyAuthService(),
      dio: Dio()..httpClientAdapter = _Adapter(jsonEncode({'artists': []})),
      token: () async => 'tok',
      refresh: () async => false,
      useCache: false,
    );
    expect(await api.fetchFollowedArtists(), isEmpty);
  });

  group('playback', () {
    setUp(() {
      Get.reset();
      Get.put<PlayerController>(_FakePlayer());
    });
    tearDown(Get.reset);

    test('the caller changing its list while the queue fills is harmless',
        () async {
      final importer =
          Get.put<SpotifyImportService>(_FakeImporter()) as _FakeImporter;
      final list = [for (var i = 0; i < 20; i++) _ref('t$i')];
      // A new Spotify search clears its results while this still plays.
      importer.onFirstResolve = list.clear;

      final result = await SpotifyPlayback.play(list, from: 'Search');
      expect(result, SpotifyPlayResult.playing);
      final queue = Get.find<PlayerController>().currentQueue;
      expect(queue.map((m) => m.id), [for (var i = 0; i < 20; i++) 'yt_t$i']);
    });
  });
}
