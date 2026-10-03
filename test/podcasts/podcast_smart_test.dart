import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';
import 'package:harmonymusic/services/podcast_inbox_cache.dart';
import 'package:harmonymusic/services/podcast_release_predictor.dart';
import 'package:harmonymusic/services/podcast_stats.dart';
import 'package:hive/hive.dart';

/// [n] weekly releases on the weekday of [first], newest first.
List<DateTime> weekly(DateTime first, int n) =>
    [for (var i = 0; i < n; i++) first.subtract(Duration(days: 7 * i))];

void main() {
  // Saturday 3 Oct 2026, 08:00 local.
  final now = DateTime(2026, 10, 3, 8);

  group('expected today', () {
    test('weekly show on today\'s weekday: median time, quarter hour', () {
      final dates = [
        DateTime(2026, 9, 26, 6, 0),
        DateTime(2026, 9, 19, 6, 10),
        DateTime(2026, 9, 12, 5, 55),
        DateTime(2026, 9, 5, 6, 40),
        DateTime(2026, 8, 29, 6, 5),
      ];
      expect(predictToday(dates, now),
          const ReleasePrediction(hour: 6, minute: 0));
    });

    test('needs at least 4 releases', () {
      expect(predictToday(weekly(DateTime(2026, 9, 26, 9), 3), now), isNull);
      expect(predictToday(weekly(DateTime(2026, 9, 26, 9), 4), now),
          isNotNull);
    });

    test('60% on today\'s weekday, not less', () {
      final sat = weekly(DateTime(2026, 9, 26, 9), 3); // 3 Saturdays
      final tue = weekly(DateTime(2026, 9, 29, 9), 2); // 2 Tuesdays
      expect(predictToday([...sat, ...tue], now), isNotNull); // 3/5
      final tue3 = weekly(DateTime(2026, 9, 29, 9), 3);
      expect(predictToday([...sat, ...tue3], now), isNull); // 3/6
    });

    test('already out today: no guess', () {
      final dates = [now.subtract(const Duration(hours: 2)),
        ...weekly(DateTime(2026, 9, 26, 6), 6)];
      expect(predictToday(dates, now), isNull);
    });

    test('daily show, any weekday it has run on', () {
      final daily = [
        for (var i = 1; i <= 10; i++)
          DateTime(2026, 10, 3 - i, 17, 30 + (i.isEven ? 10 : -10))
      ];
      final p = predictToday(daily, now)!;
      expect(p.hour, 17);
      expect(p.minute, anyOf(15, 30));
    });

    test('weekdays-only show is not due on a Saturday', () {
      final weekdays = <DateTime>[];
      var d = DateTime(2026, 10, 2, 7);
      while (weekdays.length < 10) {
        if (d.weekday <= 5) weekdays.add(d);
        d = d.subtract(const Duration(days: 1));
      }
      expect(predictToday(weekdays, now), isNull);
      // ...but is on a Monday.
      expect(predictToday(weekdays, DateTime(2026, 10, 5, 6)), isNotNull);
    });

    test('a show that went quiet gets no guess', () {
      expect(predictToday(weekly(DateTime(2026, 6, 6, 9), 8), now), isNull);
    });

    test('only the newest 10 count', () {
      final old = weekly(DateTime(2025, 1, 4, 9), 20); // Saturdays, long ago
      final recent = weekly(DateTime(2026, 9, 29, 9), 10); // Tuesdays
      expect(predictToday([...old, ...recent], now), isNull);
    });
  });

  group('expected shows from the Inbox', () {
    MediaItem ep(String id, String feed, String show, DateTime? at) =>
        MediaItem(id: id, title: id, artist: show, extras: {
          'isPodcast': true,
          'feedUrl': feed,
          'pubDateMs': at?.millisecondsSinceEpoch ?? 0,
        });

    test('groups by show, skips undated, sorts by time', () {
      final merged = [
        for (final d in weekly(DateTime(2026, 9, 26, 18), 5))
          ep('late${d.day}', 'https://late', 'Late Show', d),
        for (final d in weekly(DateTime(2026, 9, 26, 6), 5))
          ep('early${d.day}', 'https://early', 'Early Show', d),
        for (var i = 0; i < 6; i++) ep('yt$i', '', 'YouTube Show', null),
        for (final d in weekly(DateTime(2026, 9, 29, 9), 5))
          ep('tue${d.day}', 'https://tue', 'Tuesday Show', d),
      ];
      final out = expectedShows(merged, now);
      expect(out.map((s) => s.title), ['Early Show', 'Late Show']);
      expect(out.first.prediction, const ReleasePrediction(hour: 6, minute: 0));
    });
  });

  group('inbox cache and tint', () {
    test('episode round trip; long notes trimmed; junk skipped', () {
      final e = MediaItem(
        id: 'podcast_9',
        title: 'T',
        artist: 'S',
        duration: const Duration(minutes: 3),
        artUri: Uri.parse('https://img/x.jpg'),
        extras: {
          'url': 'https://a/x.mp3',
          'pubDateMs': 5,
          'description': 'x' * 5000,
          'list': [1, 2],
        },
      );
      final back = inboxEpisodeFromJson(inboxEpisodeToJson(e))!;
      expect(back.id, 'podcast_9');
      expect(back.duration, const Duration(minutes: 3));
      expect(back.extras!['pubDateMs'], 5);
      expect(back.extras!['isPodcast'], isTrue);
      expect((back.extras!['description'] as String).length,
          inboxCacheNotesLimit);
      expect(back.extras!.containsKey('list'), isFalse);
      expect(inboxEpisodeFromJson({'title': 'no id'}), isNull);
      expect(inboxEpisodeFromJson(3), isNull);
    });

    test('player tint is dark and calm', () {
      for (final c in const [
        Color(0xFFFFEB3B),
        Color(0xFF00E5FF),
        Color(0xFF101010),
        Color(0xFFFFFFFF),
      ]) {
        final t = HSLColor.fromColor(podcastPlayerTint(c));
        expect(t.lightness, inInclusiveRange(0.05, 0.17)); // 8-bit rounding
        expect(t.saturation, lessThanOrEqualTo(0.57));
      }
    });
  });

  group('stats math', () {
    test('a tick counts wall time and episode time', () {
      expect(
          listenDelta(
              prevPosMs: 1000,
              posMs: 1150,
              prevWallMs: 0,
              wallMs: 100,
              playing: true),
          (wallMs: 100, contentMs: 150));
    });

    test('paused, first tick, seeks and sleeps do not count', () {
      ListenDelta? d({int? pp = 0, int p = 100, int? pw = 0, int w = 100,
              bool playing = true}) =>
          listenDelta(
              prevPosMs: pp,
              posMs: p,
              prevWallMs: pw,
              wallMs: w,
              playing: playing);
      expect(d(playing: false), isNull);
      expect(d(pp: null), isNull);
      expect(d(p: 60000), isNull); // seek forward
      expect(d(p: -100), isNull); // seek back
      expect(d(w: 9000, p: 9000), isNull); // app slept
    });

    test('streak counts back from today or yesterday', () {
      final today = DateTime(2026, 10, 3);
      final days = {'2026-10-01', '2026-10-02', '2026-10-03', '2026-09-29'};
      expect(listeningStreak(days, today), 3);
      expect(listeningStreak(days..remove('2026-10-03'), today), 2);
      expect(listeningStreak(const {}, today), 0);
      expect(listeningStreak({'2026-09-30'}, today), 0);
    });

    test('streak across a month end', () {
      expect(
          listeningStreak(
              {'2026-09-30', '2026-10-01'}, DateTime(2026, 10, 1)),
          2);
    });

    test('top shows', () {
      final out = topShows(const [
        ShowListening('a', 'A', 10),
        ShowListening('b', 'B', 30),
        ShowListening('c', 'C', 0),
        ShowListening('d', 'D', 20),
      ], limit: 2);
      expect(out.map((s) => s.key), ['b', 'd']);
    });
  });

  group('stats store (Hive)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_stats_');
      Hive.init(tmp.path);
      await Hive.openBox(PodcastStatsService.box);
      PodcastStatsService.resetSession();
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('inbox cache saves per subscription set', () async {
      await Hive.openBox(PodcastInboxCache.box);
      const e = MediaItem(id: 'a', title: 'A', extras: {'isPodcast': true});
      await PodcastInboxCache.save([e], 'subsA', now: DateTime(2026, 1, 1));
      expect(PodcastInboxCache.load('subsA')!.items.single.id, 'a');
      expect(PodcastInboxCache.load('subsA')!.at, DateTime(2026, 1, 1));
      expect(PodcastInboxCache.load('subsB'), isNull);
    });

    test('ticks add up; 1.5x saves time; flush persists', () {
      const ep = MediaItem(
          id: 'podcast_1',
          title: 'Ep',
          artist: 'Show',
          extras: {'isPodcast': true, 'feedUrl': 'https://a/feed'});
      var t = DateTime(2026, 10, 3, 9);
      var pos = 0;
      for (var i = 0; i < 21; i++) {
        PodcastStatsService.tick(ep, Duration(milliseconds: pos),
            playing: true, now: t);
        t = t.add(const Duration(milliseconds: 1000));
        pos += 1500;
      }
      PodcastStatsService.flush(now: t);
      expect(PodcastStatsService.listened, const Duration(seconds: 20));
      expect(PodcastStatsService.savedBySpeed, const Duration(seconds: 10));
      expect(PodcastStatsService.streak(today: t), 1);
      expect(PodcastStatsService.top().single.title, 'Show');
      expect(PodcastStatsService.top().single.ms, 20000);
    });

    test('junk in the box reads as zero', () async {
      await Hive.box(PodcastStatsService.box).put('listenWallMs', 'x');
      await Hive.box(PodcastStatsService.box).put('listenShows', 3);
      expect(PodcastStatsService.listened, Duration.zero);
      expect(PodcastStatsService.top(), isEmpty);
    });
  });
}
