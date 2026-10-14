import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/audio_handler.dart' show MediaLibrary;
import 'package:harmonymusic/services/podcast_inbox_counts.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:hive/hive.dart';

MediaItem _ep(String id) =>
    MediaItem(id: id, title: 'Episode $id', artist: 'Show', extras: {
      'isPodcast': true,
      'feedUrl': 'https://a.example/feed',
      'url': 'https://a.example/$id.mp3',
    });

List<String> _ids(List<MediaItem> items) => items.map((m) => m.id).toList();

void main() {
  setUp(() async {
    for (final b in [
      'AppPrefs',
      'PodcastQueue',
      'PodcastPlayed',
      'PodcastProgress',
      'PodcastArchived',
      'PodcastSubs',
    ]) {
      await Hive.openBox(b, bytes: Uint8List(0));
    }
  });

  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  test('the queue and the Inbox come first under Podcasts', () async {
    final nodes = await MediaLibrary().getPodcastNodes();
    expect(_ids(nodes).take(3), [
      MediaLibrary.podcastQueueId,
      MediaLibrary.podcastInboxId,
      MediaLibrary.podcastProgressId,
    ]);
    expect(nodes.take(3).every((n) => n.playable == false), isTrue);
    // Played from the list the car browsed, like the others.
    expect(MediaLibrary.isBuiltList(MediaLibrary.podcastQueueId), isTrue);
    expect(MediaLibrary.isBuiltList(MediaLibrary.podcastInboxId), isTrue);
  });

  test('the queue, in its order', () async {
    final queue = Get.put(PodcastQueueController());
    queue.add(_ep('q1'));
    queue.add(_ep('q2'));
    final items =
        await MediaLibrary().browse(MediaLibrary.podcastQueueId, null);
    expect(_ids(items), ['q1', 'q2']);
    expect(items.every((m) => m.playable == true), isTrue);
    expect(items.first.extras?['libraryId'], MediaLibrary.podcastQueueId);
    expect(_ids(MediaLibrary.autoPodcastLists[MediaLibrary.podcastQueueId]!),
        ['q1', 'q2']);
  });

  test('no queue yet: an empty list', () async {
    expect(await MediaLibrary().browse(MediaLibrary.podcastQueueId, null),
        isEmpty);
  });

  test('the Inbox as the app lists it: no played or archived episodes',
      () async {
    PodcastInboxCounts.setInbox(
        [_ep('new'), _ep('played'), _ep('kept'), _ep('old')]);
    await Hive.box('PodcastPlayed').put('played', 1);
    await Hive.box('PodcastArchived').put('kept', {'at': 1, 'show': 'x'});
    final items =
        await MediaLibrary().browse(MediaLibrary.podcastInboxId, null);
    expect(_ids(items), ['new', 'old']);
  });
}
