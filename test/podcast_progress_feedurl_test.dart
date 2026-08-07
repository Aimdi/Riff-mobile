import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import 'package:harmonymusic/services/podcast_progress_service.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('podcast_progress_test');
    Hive.init(p.join(tmp.path, 'hive'));
    await Hive.openBox('PodcastProgress');
    await Hive.openBox('PodcastPlayed');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('save + toMediaItem keeps feedUrl', () {
    const item = MediaItem(
      id: 'podcast_ep1',
      title: 'Episode',
      artist: 'Show',
      duration: Duration(minutes: 30),
      extras: {
        'url': 'https://example.com/ep.mp3',
        'isPodcast': true,
        'feedUrl': 'https://example.com/feed.xml',
      },
    );
    PodcastProgressService.save(
      item,
      const Duration(minutes: 5),
      const Duration(minutes: 30),
      nowMs: 123,
    );
    final rows = PodcastProgressService.inProgress();
    expect(rows, hasLength(1));
    expect(rows.first['feedUrl'], 'https://example.com/feed.xml');
    final rebuilt = PodcastProgressService.toMediaItem(rows.first);
    expect(rebuilt.extras?['feedUrl'], 'https://example.com/feed.xml');
  });
}
