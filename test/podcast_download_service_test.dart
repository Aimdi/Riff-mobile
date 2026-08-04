import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import 'package:harmonymusic/services/podcast_download_service.dart';

void main() {
  late Directory tmp;
  late Directory support;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('podcast_dl_test');
    support = Directory(p.join(tmp.path, 'support'))..createSync();
    Hive.init(p.join(tmp.path, 'hive'));
    await Hive.openBox('PodcastDownloads');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('legacy String path still resolves via localPath', () async {
    final file = File(p.join(support.path, 'ep.mp3'))..writeAsStringSync('x');
    await Hive.box('PodcastDownloads').put('podcast_legacy', file.path);
    // Warm path uses Hive; force cache reset by reading through service.
    expect(PodcastDownloadService.localPath('podcast_legacy'), file.path);
    expect(PodcastDownloadService.isDownloaded('podcast_legacy'), isTrue);
    final item = PodcastDownloadService.toMediaItem('podcast_legacy');
    expect(item, isNotNull);
    expect(item!.extras?['localPath'], file.path);
  });

  test('Map metadata round-trips to MediaItem', () async {
    final file = File(p.join(support.path, 'ep2.mp3'))..writeAsStringSync('y');
    await Hive.box('PodcastDownloads').put('podcast_meta', {
      'path': file.path,
      'id': 'podcast_meta',
      'title': 'Cool Episode',
      'artist': 'Cool Show',
      'artUri': 'https://example.com/art.jpg',
      'durationMs': 120000,
      'url': 'https://example.com/ep.mp3',
      'feedUrl': 'https://example.com/feed.xml',
      'isPodcast': true,
    });
    final item = PodcastDownloadService.toMediaItem('podcast_meta');
    expect(item, isNotNull);
    expect(item!.title, 'Cool Episode');
    expect(item.artist, 'Cool Show');
    expect(item.duration, const Duration(minutes: 2));
    expect(item.extras?['feedUrl'], 'https://example.com/feed.xml');
    expect(PodcastDownloadService.localPath('podcast_meta'), file.path);
  });

  test('downloadedItems lists playable metadata rows', () async {
    final file = File(p.join(support.path, 'ep3.mp3'))..writeAsStringSync('z');
    await Hive.box('PodcastDownloads').put('podcast_list', {
      'path': file.path,
      'title': 'Listed',
      'url': 'https://example.com/x.mp3',
    });
    final items = PodcastDownloadService.downloadedItems();
    expect(items.map((e) => e.id), contains('podcast_list'));
  });
}
