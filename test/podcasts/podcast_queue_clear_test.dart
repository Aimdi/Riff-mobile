import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:hive/hive.dart';

MediaItem _episode(int n) => MediaItem(
      id: 'podcast_ep$n',
      title: 'Episode $n',
      extras: const {
        'isPodcast': true,
        'url': 'https://cdn.example/ep.mp3',
        'link': 'https://show.example/ep',
      },
    );

void main() {
  late PodcastQueueController queue;

  setUp(() async {
    await Hive.openBox('PodcastQueue', bytes: Uint8List(0));
    queue = PodcastQueueController()..onInit();
  });
  tearDown(() => Hive.box('PodcastQueue').close());

  List<String> ids() => [for (final e in queue.queue) e.id];

  test('clearing Up Next can be undone, keeping what was queued since', () {
    for (var i = 1; i <= 3; i++) {
      queue.add(_episode(i));
    }
    final undo = queue.clearUndoable();
    expect(queue.queue, isEmpty);
    expect(undo, isNotNull);

    queue.add(_episode(4));
    undo!();
    expect(ids(), ['podcast_ep1', 'podcast_ep2', 'podcast_ep3', 'podcast_ep4']);

    // Stored: a new controller reads it back, links and all.
    final again = PodcastQueueController()..onInit();
    expect([for (final e in again.queue) e.id], ids());
    expect(again.queue.first.extras?['link'], 'https://show.example/ep');
  });

  test('nothing to clear: nothing to undo', () {
    expect(queue.clearUndoable(), isNull);
  });
}
