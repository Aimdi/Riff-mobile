import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('podcast_queue_test');
    Hive.init(p.join(tmp.path, 'hive'));
    await Hive.openBox('PodcastQueue');
    Get.reset();
    Get.put(PodcastQueueController());
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    Get.reset();
  });

  test('queue persistence keeps chapters and transcript extras', () async {
    final c = Get.find<PodcastQueueController>();
    c.add(MediaItem(
      id: 'podcast_ep1',
      title: 'Episode 1',
      artist: 'Show',
      extras: {
        'url': 'https://example.com/ep.mp3',
        'isPodcast': true,
        'chaptersUrl': 'https://example.com/chapters.json',
        'transcriptUrl': 'https://example.com/transcript.vtt',
        'transcriptType': 'application/x-subrip',
      },
    ));
    expect(c.queue, hasLength(1));

    // Reload from Hive the way a cold start would.
    Get.delete<PodcastQueueController>();
    Get.put(PodcastQueueController());
    final reloaded = Get.find<PodcastQueueController>().queue.single;
    expect(reloaded.extras?['chaptersUrl'],
        'https://example.com/chapters.json');
    expect(reloaded.extras?['transcriptUrl'],
        'https://example.com/transcript.vtt');
    expect(reloaded.extras?['transcriptType'], 'application/x-subrip');
  });
}
