import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import 'package:harmonymusic/services/podcast_progress_service.dart';

/// Playing a downloaded episode swaps extras['url'] for a `file://` path
/// (audio_handler.checkNGetUrl) and writes it back onto the MediaItem, so the
/// saved progress record used to keep only the local path — dead as soon as the
/// download is deleted or after a data restore.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('podcast_progress_url_test');
    Hive.init(p.join(tmp.path, 'hive'));
    await Hive.openBox('PodcastProgress');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  MediaItem episode({required String url, String? remoteUrl}) => MediaItem(
        id: 'podcast_-123',
        title: 'Episode 1',
        artist: 'Show',
        duration: const Duration(minutes: 30),
        extras: {
          'url': url,
          if (remoteUrl != null) 'remoteUrl': remoteUrl,
          'isPodcast': true,
        },
      );

  test('storableUrl prefers the stashed remote URL over a local path', () {
    expect(
      PodcastProgressService.storableUrl(
        remoteUrl: 'https://example.com/ep.mp3',
        currentUrl: 'file:///data/user/0/pkg/files/podcast_-123.mp3',
      ),
      'https://example.com/ep.mp3',
    );
  });

  test('storableUrl never returns a local path', () {
    expect(
      PodcastProgressService.storableUrl(
          currentUrl: 'file:///data/user/0/pkg/files/podcast_-123.mp3'),
      isNull,
    );
    expect(
      PodcastProgressService.storableUrl(
          currentUrl: '/data/user/0/pkg/files/podcast_-123.mp3'),
      isNull,
    );
    expect(
      PodcastProgressService.storableUrl(
        currentUrl: 'file:///data/user/0/pkg/files/podcast_-123.mp3',
        previousUrl: 'https://example.com/ep.mp3',
      ),
      'https://example.com/ep.mp3',
    );
  });

  test('save keeps the remote enclosure URL for a downloaded episode', () {
    PodcastProgressService.save(
      episode(
        url: 'file:///data/user/0/pkg/files/podcast_downloads/podcast_-123.mp3',
        remoteUrl: 'https://example.com/ep.mp3',
      ),
      const Duration(minutes: 5),
      const Duration(minutes: 30),
      nowMs: 1000,
    );

    final record = Hive.box('PodcastProgress').get('podcast_-123') as Map;
    expect(record['url'], 'https://example.com/ep.mp3');

    // The Inbox "Continue" tile is rebuilt straight from this record.
    final rebuilt = PodcastProgressService.toMediaItem(
        Map<String, dynamic>.from(record));
    expect(rebuilt.extras!['url'], 'https://example.com/ep.mp3');
  });

  test('save falls back to the previously stored remote URL when the incoming '
      'item only carries a local path', () {
    // First pass: streamed, remote URL recorded.
    PodcastProgressService.save(
      episode(url: 'https://example.com/ep.mp3'),
      const Duration(minutes: 1),
      const Duration(minutes: 30),
      nowMs: 1000,
    );
    // Later pass: same episode, now played from the downloaded copy, and the
    // remote URL was never stashed on the item.
    PodcastProgressService.save(
      episode(
          url:
              'file:///data/user/0/pkg/files/podcast_downloads/podcast_-123.mp3'),
      const Duration(minutes: 5),
      const Duration(minutes: 30),
      nowMs: 2000,
    );

    final record = Hive.box('PodcastProgress').get('podcast_-123') as Map;
    expect(record['url'], 'https://example.com/ep.mp3');
    expect(record['positionMs'], const Duration(minutes: 5).inMilliseconds);
  });

  test('toMediaItem drops a legacy poisoned file:// URL', () {
    final rebuilt = PodcastProgressService.toMediaItem({
      'id': 'podcast_-123',
      'title': 'Episode 1',
      'url': 'file:///data/user/0/pkg/files/podcast_downloads/podcast_-123.mp3',
      'durationMs': 1800000,
    });
    expect(rebuilt.extras!['url'], isNull);
  });

  test('streamed episodes still persist their URL unchanged', () {
    PodcastProgressService.save(
      episode(url: 'https://example.com/ep.mp3'),
      const Duration(minutes: 5),
      const Duration(minutes: 30),
      nowMs: 1000,
    );
    final record = Hive.box('PodcastProgress').get('podcast_-123') as Map;
    expect(record['url'], 'https://example.com/ep.mp3');
  });
}
