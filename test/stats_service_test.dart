import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/stats_service.dart';
import 'package:hive/hive.dart';

void main() {
  test('skip under 30 percent increments skips not seconds of full duration', () {
    final next = applyListenEnd(
      {'plays': 1, 'seconds': 0, 'skips': 0},
      listenedMs: 20 * 1000,
      totalMs: 200 * 1000,
      source: DiscoverySource.search,
      title: 'Song',
      artist: 'A',
    );
    expect(next['skips'], 1);
    expect(next['partials'], 0);
    expect(next['completes'], 0);
    expect(next['seconds'], 20);
    expect(next['lastSource'], 'search');
    expect(next['lastFraction'], closeTo(0.10, 0.001));
  });

  test('partial listen 40 percent is a partial not a skip', () {
    final next = applyListenEnd(
      const {},
      listenedMs: 80 * 1000,
      totalMs: 200 * 1000,
      source: DiscoverySource.album,
    );
    expect(next['skips'], 0);
    expect(next['partials'], 1);
    expect(next['completes'], 0);
    expect(next['seconds'], 80);
  });

  test('full listen 90 percent is a complete', () {
    final next = applyListenEnd(
      const {},
      listenedMs: 180 * 1000,
      totalMs: 200 * 1000,
      source: DiscoverySource.radio,
    );
    expect(next['completes'], 1);
    expect(next['skips'], 0);
    expect(next['lastSource'], 'radio');
  });

  test('unknown duration under 10s is a quick skip', () {
    final next = applyListenEnd(
      const {},
      listenedMs: 4000,
      totalMs: 0,
      source: DiscoverySource.home,
    );
    expect(next['skips'], 1);
    expect(next['seconds'], 4);
    expect(next['lastFraction'], isNull);
  });

  test('listenEndWasSkip compares counts, a missing count is zero', () {
    expect(listenEndWasSkip(const {}, const {'skips': 0}), isFalse);
    expect(listenEndWasSkip(const {}, const {'skips': 1}), isTrue);
    expect(listenEndWasSkip(const {'skips': 2}, const {'skips': 2}), isFalse);
  });

  group('daily stats (Hive)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_stats_');
      Hive.init(tmp.path);
      await Hive.openBox('SongStats');
      await Hive.openBox('DailyStats');
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    const song = MediaItem(id: 'v1', title: 'Song', artist: 'A');
    Map today() => Map.from(StatsService.lastDays(1).single);

    test("a song's first full listen is not counted as a skip", () async {
      await StatsService.recordPlay(song);
      await StatsService.recordListenEnd(song,
          listenedMs: 190 * 1000, totalMs: 200 * 1000);
      expect(today()['plays'], 1);
      expect(today()['skips'], 0);
      expect(today()['seconds'], 190);

      await StatsService.recordPlay(song);
      await StatsService.recordListenEnd(song,
          listenedMs: 5 * 1000, totalMs: 200 * 1000);
      expect(today()['skips'], 1);
    });

    test('counts stored as doubles (synced / older data) do not throw',
        () async {
      await Hive.box('SongStats')
          .put('v1', {'plays': 3.0, 'lastPlayed': 1.0, 'artist': 7});
      await StatsService.recordPlay(song);
      expect(Hive.box('SongStats').get('v1')['plays'], 4);
      expect(StatsService.mostRecentSong()?.id, 'v1');
      expect(StatsService.uniqueArtists, 1);
    });
  });
}
