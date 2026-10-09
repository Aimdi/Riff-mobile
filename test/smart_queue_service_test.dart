import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:harmonymusic/services/discovery/discovery_service.dart';
import 'package:harmonymusic/services/smart_queue_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';

MediaItem _song(String id) =>
    MediaItem(id: id, title: 'Song $id', extras: const {'url': ''});

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final currentQueue = <MediaItem>[].obs;
  @override
  final currentSongIndex = 0.obs;

  final enqueued = <List<MediaItem>>[];

  @override
  Future<bool> enqueueSongList(List<MediaItem> mediaItems) async {
    enqueued.add(mediaItems);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDiscovery extends GetxService implements DiscoveryService {
  @override
  Future<List<MediaItem>> moreLikeThisPlayNext(MediaItem seed,
          {int limit = 5}) async =>
      [for (var i = 0; i < 3; i++) _song('${seed.id}-sim$i')];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;

  setUp(() async {
    Get.reset();
    tmp = await Directory.systemTemp.createTemp('riff_smart_queue_');
    Hive.init(tmp.path);
    await Hive.openBox('AppPrefs');
    Get.put<DiscoveryService>(_FakeDiscovery());
  });

  tearDown(() async {
    Get.reset();
    await Hive.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('injects when a song near the end starts, with the index still stale',
      () async {
    final player = _FakePlayer();
    player.currentQueue
        .assignAll([for (final id in 'abcde'.split('')) _song(id)]);
    player.currentSong.value = player.currentQueue.first;
    player.currentSongIndex.value = 0;
    SmartQueueService().attach(player);

    // What the player's media-item listener does when the last song is
    // tapped: currentSong first, currentSongIndex only afterwards. The old
    // code read the stale index (0: four songs left) and never injected.
    player.currentSong.value = player.currentQueue.last;
    await pumpEventQueue();

    expect(player.enqueued, hasLength(1));
    expect(player.enqueued.single.map((s) => s.id),
        ['e-sim0', 'e-sim1', 'e-sim2']);
  });

  test('leaves a queue with more than two songs to go alone', () async {
    final player = _FakePlayer();
    player.currentQueue
        .assignAll([for (final id in 'abcde'.split('')) _song(id)]);
    player.currentSongIndex.value = 4; // stale: was on the last song
    SmartQueueService().attach(player);

    player.currentSong.value = player.currentQueue[1];
    await pumpEventQueue();

    expect(player.enqueued, isEmpty);
  });
}
