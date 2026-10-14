import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/player/play_queue_order.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:hive/hive.dart';

class _FakeMusic extends GetxService implements MusicServices {
  /// What a radio started from a song brings.
  List<MediaItem> radio = const [];

  @override
  Future<Map<String, dynamic>> getWatchPlaylist(
          {String videoId = "",
          String? playlistId,
          int limit = 25,
          bool radio = false,
          bool shuffle = false,
          dynamic additionalParamsNext,
          bool onlyRelated = false}) async =>
      {'tracks': this.radio, 'additionalParamsForNext': null};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Keeps the queue as the audio handler does, and tells the player.
class _QueueHandler extends BaseAudioHandler {
  late PlayerController player;
  var items = <MediaItem>[];

  List<String> get ids => [for (final m in items) m.id];

  void _tell() => player.currentQueue.assignAll(items);

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    items = List.of(queue);
    _tell();
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    items.add(mediaItem);
    _tell();
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    items.addAll(mediaItems);
    _tell();
  }

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'playByIndex':
        player.currentSongIndex.value = extras!['index'] as int;
        return true;
      case 'addPlayNextItem':
        items.insert(player.currentSongIndex.value + 1,
            extras!['mediaItem'] as MediaItem);
        _tell();
        return true;
    }
    return null;
  }
}

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');

void main() {
  test('the songs you queued that are still to play, in their order', () {
    final queue = [
      queuedByYou(_song('played0000a')),
      _song('now0000000a'),
      queuedByYou(_song('next000000a')),
      _song('album00000b'),
      queuedByYou(_song('later00000a')),
      queuedByYou(const MediaItem(
          id: 'podcast_ep1', title: 'Episode', extras: {'isPodcast': true})),
      queuedByYou(_song('heard00000a')),
    ];
    expect(stillQueuedByYou(queue, 1, heard: {'heard00000a'}).map((s) => s.id),
        ['next000000a', 'later00000a']);

    // Marked once, with what it carried kept.
    final marked = queuedByYou(const MediaItem(
        id: 'x', title: 'X', extras: {'discoverySource': 'search'}));
    expect(marked.extras, {'discoverySource': 'search', kQueuedByYou: true});
    expect(identical(queuedByYou(marked), marked), isTrue);
  });

  group('playing something else', () {
    late Directory tmp;

    setUp(() async {
      Get.reset();
      tmp = await Directory.systemTemp.createTemp('riff_queued_');
      Hive.init(tmp.path);
      await Hive.openBox('AppPrefs');
    });
    tearDown(() async {
      Get.reset();
      await Hive.close();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    testWidgets('keeps the songs you queued, next, as Spotify does',
        (tester) async {
      // playPlayListSong sizes the panel from the window (Get.size).
      await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
      final music = Get.put<MusicServices>(_FakeMusic()) as _FakeMusic;
      final handler = Get.put<AudioHandler>(_QueueHandler()) as _QueueHandler;
      final player = PlayerController()..initFlagForPlayer = false;
      handler.player = player;

      await tester.runAsync(() async {
        await player.playPlayListSong(
            [_song('album00000a'), _song('album00000b'), _song('album00000c')],
            0);
        // You queue two songs; Autoplay adds one.
        await player.playNext(_song('next000000a'));
        await player.enqueueSong(_song('queued0000a'));
        await player.enqueueSongList([_song('autoplay00a')]);
        expect(handler.ids, [
          'album00000a',
          'next000000a',
          'album00000b',
          'album00000c',
          'queued0000a',
          'autoplay00a',
        ]);

        // A playlist from its second song: yours play next in it.
        await player.playPlayListSong(
            [_song('list00000a'), _song('list00000b'), _song('list00000c')], 1);
        expect(handler.ids, [
          'list00000a',
          'list00000b',
          'next000000a',
          'queued0000a',
          'list00000c',
        ]);

        // One of them played: only the other is kept.
        player.currentSongIndex.value = 2;
        await player.playPlayListSong([_song('other00000a')], 0);
        expect(handler.ids, ['other00000a', 'queued0000a']);

        // A radio keeps it too.
        music.radio = [_song('radio00000a'), _song('radio00000b')];
        await player.startRadio(_song('radio00000a'));
        expect(handler.ids, ['radio00000a', 'queued0000a', 'radio00000b']);

        // An episode starts alone: music doesn't go into a podcast.
        await player.playPlayListSong([
          const MediaItem(
              id: 'podcast_ep1', title: 'Episode', extras: {'isPodcast': true})
        ], 0);
        expect(handler.ids, ['podcast_ep1']);

        // Let playPlayListSong's delayed Home refresh check run while the
        // prefs box is still open.
        await Future<void>.delayed(const Duration(milliseconds: 3200));
      });
    });
  });
}
