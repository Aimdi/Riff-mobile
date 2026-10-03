import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_bookmarks.dart';
import 'package:hive/hive.dart';

MediaItem ep({String id = 'podcast_42', Map<String, dynamic>? extras}) =>
    MediaItem(
      id: id,
      title: 'The Episode',
      artist: 'The Show',
      artUri: Uri.parse('https://img/a.jpg'),
      duration: const Duration(minutes: 50),
      extras: extras ??
          {
            'isPodcast': true,
            'url': 'file:///data/ep.mp3',
            'remoteUrl': 'https://cdn/ep.mp3',
            'feedUrl': 'https://feed',
            'description': 'Very long notes…',
            'artists': [
              {'name': 'x'}
            ],
          },
    );

PodcastBookmark bm(int pos,
        {String quote = 'Hello', String? note, int created = 0}) =>
    PodcastBookmark(
      id: 'b$pos',
      episodeId: 'podcast_42',
      positionMs: pos,
      createdAt: created,
      quote: quote,
      note: note,
      episodeTitle: 'The Episode',
      showTitle: 'The Show',
    );

void main() {
  test('share text', () {
    expect(formatBookmarkShare(bm(754000, quote: 'Be curious')),
        '“Be curious” — The Show, The Episode @ 12:34');
    expect(formatBookmarkShare(bm(3909000, quote: '')),
        'The Show, The Episode @ 1:05:09');
    expect(
        formatBookmarkShare(const PodcastBookmark(
            id: 'x', episodeId: 'e', positionMs: 5000, createdAt: 0)),
        '@ 0:05');
  });

  test('snapshot keeps a playable episode, minus local paths and notes', () {
    final snap = episodeSnapshot(ep());
    final extras = snap['extras'] as Map;
    expect(extras['url'], 'https://cdn/ep.mp3');
    expect(extras.containsKey('description'), isFalse);
    expect(extras.containsKey('artists'), isFalse);
    final item = mediaItemFromSnapshot(snap)!;
    expect(item.id, 'podcast_42');
    expect(item.title, 'The Episode');
    expect(item.artist, 'The Show');
    expect(item.duration, const Duration(minutes: 50));
    expect(item.artUri.toString(), 'https://img/a.jpg');
    expect(item.extras!['isPodcast'], isTrue);
    expect(item.extras!['feedUrl'], 'https://feed');
    expect(mediaItemFromSnapshot(const {}), isNull);
  });

  test('a downloaded-only episode drops the dead file path', () {
    final snap = episodeSnapshot(ep(extras: {
      'isPodcast': true,
      'url': 'file:///data/ep.mp3',
    }));
    expect((snap['extras'] as Map).containsKey('url'), isFalse);
  });

  test('json round trip; old or broken entries never crash', () {
    final b = bm(1000, note: 'Great point', created: 7);
    final back = PodcastBookmark.fromJson(b.toJson())!;
    expect(back.id, b.id);
    expect(back.positionMs, 1000);
    expect(back.note, 'Great point');
    expect(back.createdAt, 7);
    expect(PodcastBookmark.fromJson({'id': 'x'}), isNull);
    expect(PodcastBookmark.fromJson(42), isNull);
    final minimal = PodcastBookmark.fromJson(
        {'id': 'x', 'episodeId': 'e', 'positionMs': -5, 'note': '  '})!;
    expect(minimal.positionMs, 0);
    expect(minimal.note, isNull);
    expect(minimal.episode, isEmpty);
  });

  test('sorting', () {
    final list = [bm(30, created: 1), bm(10, created: 3), bm(20, created: 2)];
    expect(sortBookmarksNewest(list).map((b) => b.positionMs), [10, 20, 30]);
    expect(sortBookmarksByPosition(list).map((b) => b.positionMs),
        [10, 20, 30]);
    expect(sortBookmarksNewest([bm(1, created: 1), bm(2, created: 5)])
        .first
        .positionMs, 2);
  });

  group('store (Hive)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_bookmarks_');
      Hive.init(tmp.path);
      await Hive.openBox(PodcastBookmarkStore.box);
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('add, note, remove, restore, per episode', () async {
      final a = (await PodcastBookmarkStore.add(
          ep(), const Duration(seconds: 90),
          quote: ' A quote ', now: DateTime(2026, 10, 3, 10)))!;
      await PodcastBookmarkStore.add(ep(), const Duration(seconds: 30),
          now: DateTime(2026, 10, 3, 11));
      await PodcastBookmarkStore.add(
          ep(id: 'podcast_other'), const Duration(seconds: 5),
          now: DateTime(2026, 10, 3, 12));
      expect(a.quote, 'A quote');
      expect(a.showTitle, 'The Show');
      expect(PodcastBookmarkStore.all.first.episodeId, 'podcast_other');
      expect(PodcastBookmarkStore.forEpisode('podcast_42')
          .map((b) => b.positionMs), [30000, 90000]);

      await PodcastBookmarkStore.setNote(a, '  remember  ');
      expect(PodcastBookmarkStore.forEpisode('podcast_42').last.note,
          'remember');
      await PodcastBookmarkStore.setNote(a, '');
      expect(PodcastBookmarkStore.forEpisode('podcast_42').last.note, isNull);

      await PodcastBookmarkStore.remove(a.id);
      expect(PodcastBookmarkStore.forEpisode('podcast_42'), hasLength(1));
      await PodcastBookmarkStore.restore(a);
      expect(PodcastBookmarkStore.forEpisode('podcast_42'), hasLength(2));
    });

    test('junk in the box is skipped', () async {
      await Hive.box(PodcastBookmarkStore.box).put('junk', 'nope');
      expect(PodcastBookmarkStore.all, isEmpty);
    });

    test('closed box: reads empty, add is a no-op', () async {
      await Hive.box(PodcastBookmarkStore.box).close();
      expect(PodcastBookmarkStore.all, isEmpty);
      expect(await PodcastBookmarkStore.add(ep(), Duration.zero), isNull);
    });
  });
}
