import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/discovery/candidate_sources.dart';
import 'package:harmonymusic/services/discovery/discovery_repository.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/discovery/mix_generator.dart';
import 'package:harmonymusic/services/discovery/taste_model.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:hive/hive.dart';

class _FakeMusic extends MusicServices {}

/// A Wednesday evening.
final _now = DateTime(2026, 10, 14, 19);

/// [id] played through [times] times, on as many days back from [daysAgo],
/// at [hour].
Future<void> _played(DiscoveryRepository repo, String id,
    {required int hour,
    int times = 1,
    int daysAgo = 1,
    DiscoveryEventKind kind = DiscoveryEventKind.playEnded}) async {
  for (var i = 0; i < times; i++) {
    final day = _now.subtract(Duration(days: daysAgo + i));
    await repo.appendEvent(DiscoveryEvent(
      videoId: id,
      artistKey: 'artist $id',
      ts: DateTime(day.year, day.month, day.day, hour).millisecondsSinceEpoch,
      source: DiscoverySource.search,
      event: kind,
      title: 'Song $id',
      artist: 'Artist $id',
    ));
  }
}

void main() {
  test('the parts of the day, and when each began', () {
    DayPart at(int hour) => DayPart.of(DateTime(2026, 10, 14, hour));
    expect(at(5), DayPart.morning);
    expect(at(11), DayPart.morning);
    expect(at(12), DayPart.afternoon);
    expect(at(16), DayPart.afternoon);
    expect(at(17), DayPart.evening);
    expect(at(20), DayPart.evening);
    expect(at(21), DayPart.night);
    expect(at(4), DayPart.night);

    expect(DayPart.startOf(DateTime(2026, 10, 14, 13, 30)),
        DateTime(2026, 10, 14, 12));
    expect(DayPart.startOf(DateTime(2026, 10, 14, 23)),
        DateTime(2026, 10, 14, 21));
    // The small hours belong to the night before, across a month too.
    expect(
        DayPart.startOf(DateTime(2026, 10, 14, 2)), DateTime(2026, 10, 13, 21));
    expect(
        DayPart.startOf(DateTime(2026, 10, 1, 3)), DateTime(2026, 9, 30, 21));
  });

  group('with your plays', () {
    late Directory tmp;
    late DiscoveryRepository repo;
    late MixGenerator mixes;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_daylist_');
      Hive.init(tmp.path);
      repo = DiscoveryRepository();
      await repo.open();
      mixes = MixGenerator(
          repo: repo,
          taste: TasteModel(repo),
          sources: CandidateSources(music: _FakeMusic(), repo: repo));
    });

    tearDown(() async {
      BanServiceSafe.setBanHook(null);
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('the songs you play at this time of day, those of it first', () async {
      // Too long ago (plays are kept in the order they happened).
      await _played(repo, 'old0000000a', hour: 19, times: 3, daysAgo: 40);
      // Played only in the evening.
      await _played(repo, 'evening000a', hour: 19, times: 3);
      // In the evening too, but mostly in the morning.
      await _played(repo, 'allday0000a', hour: 18, times: 3);
      await _played(repo, 'allday0000a', hour: 8, times: 9);
      await _played(repo, 'onceEve000a', hour: 20);
      await _played(repo, 'morning000a', hour: 7, times: 5);
      await _played(repo, 'podcast_1', hour: 19, times: 3);
      await _played(repo, 'skipped000a',
          hour: 19, times: 3, kind: DiscoveryEventKind.skip);

      expect(repo.daylistIds(now: _now), ['evening000a', 'allday0000a']);
      expect(repo.daylistIds(now: DateTime(2026, 10, 14, 9)),
          ['allday0000a', 'morning000a']);
    });

    test('named for the day and its part; made afresh as the day moves on',
        () async {
      for (var i = 0; i < 4; i++) {
        await _played(repo, 'song00000${i}a', hour: 19, times: 3);
      }
      expect((await mixes.ensureDaylist(now: _now)).tracks, isEmpty,
          reason: 'too few songs yet');

      await _played(repo, 'song000004a', hour: 18, times: 2);
      await _played(repo, 'night00000a', hour: 23, times: 6);
      // Kept for the rest of the evening ...
      final evening = DateTime(2026, 10, 14, 20, 30);
      expect((await mixes.ensureDaylist(now: evening)).tracks, isEmpty);

      // ... and made again at night, then kept into its small hours.
      final night = await mixes.ensureDaylist(now: DateTime(2026, 10, 14, 22));
      expect(night.kind, MixKind.daylist);
      expect(night.title, 'Your Wednesday night');
      expect(night.reason, 'What you play at night');
      expect(night.tracks, isEmpty, reason: 'one song played at night');
      final smallHours =
          await mixes.ensureDaylist(now: DateTime(2026, 10, 15, 2));
      expect(smallHours.generatedTs, night.generatedTs);

      // The next evening, with five songs of the evening.
      final next = await mixes.ensureDaylist(now: DateTime(2026, 10, 15, 19));
      expect(next.title, 'Your Thursday evening');
      expect(next.reason, 'What you play in the evening');
      final ids = next.tracks.map((t) => t['videoId']).toList();
      // Played only then, three times each; the one played twice last.
      expect(ids.take(4),
          unorderedEquals([for (var i = 0; i < 4; i++) 'song00000${i}a']));
      expect(ids.last, 'song000004a');
      expect(next.tracks.last['title'], 'Song song000004a');
      expect(repo.getMix('daylist')?.title, 'Your Thursday evening');
    });

    test("songs you said never to play stay out", () async {
      for (var i = 0; i < 6; i++) {
        await _played(repo, 'song00000${i}a', hour: 19, times: 2);
      }
      BanServiceSafe.setBanHook((id) => id == 'song000000a');
      final mix = await mixes.ensureDaylist(now: _now);
      expect(
          mix.tracks.map((t) => t['videoId']), isNot(contains('song000000a')));
      expect(mix.tracks, hasLength(5));
    });
  });
}
