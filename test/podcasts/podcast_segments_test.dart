import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_segments.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:hive/hive.dart';

PodcastSegment seg(String id, double a, double b,
        {SegmentCategory c = SegmentCategory.sponsor,
        SegmentAction action = SegmentAction.autoSkip,
        SegmentSource source = SegmentSource.sponsorblock}) =>
    PodcastSegment(
        id: id, start: a, end: b, category: c, source: source, action: action);

void main() {
  group('actions', () {
    test('defaults: sponsor skips, self-promo and interaction get a pill', () {
      final a = parseSegmentActions(null);
      expect(a[SegmentCategory.sponsor], SegmentAction.autoSkip);
      expect(a[SegmentCategory.selfpromo], SegmentAction.pill);
      expect(a[SegmentCategory.interaction], SegmentAction.pill);
      for (final c in [
        SegmentCategory.intro,
        SegmentCategory.outro,
        SegmentCategory.preview,
        SegmentCategory.filler,
        SegmentCategory.musicOfftopic,
      ]) {
        expect(a[c], SegmentAction.ignore, reason: c.apiName);
      }
    });

    test('migration: the old ads switch off keeps sponsors manual', () {
      expect(parseSegmentActions(null, legacyAutoSkipAds: false)
          [SegmentCategory.sponsor], SegmentAction.pill);
      expect(parseSegmentActions(null, legacyAutoSkipAds: true)
          [SegmentCategory.sponsor], SegmentAction.autoSkip);
    });

    test('stored actions win; junk is ignored; round trip', () {
      final a = parseSegmentActions({
        'intro': 'autoSkip',
        'music_offtopic': 'mute',
        'nonsense': 'autoSkip',
        'outro': 'explode',
      }, legacyAutoSkipAds: false);
      expect(a[SegmentCategory.intro], SegmentAction.autoSkip);
      expect(a[SegmentCategory.musicOfftopic], SegmentAction.mute);
      expect(a[SegmentCategory.outro], SegmentAction.ignore);
      // Once actions are stored, the legacy switch no longer applies.
      expect(a[SegmentCategory.sponsor], SegmentAction.autoSkip);
      expect(parseSegmentActions(segmentActionsToJson(a)), a);
    });
  });

  group('resolve and merge', () {
    final actions = parseSegmentActions(null);

    test('ignored categories drop, the rest get their action', () {
      final out = resolveSegments([
        seg('a', 10, 20, action: SegmentAction.ignore),
        seg('b', 30, 40,
            c: SegmentCategory.intro, action: SegmentAction.ignore),
        seg('c', 50, 60,
            c: SegmentCategory.selfpromo, action: SegmentAction.ignore),
      ], actions);
      expect(out.map((s) => s.id), ['a', 'c']);
      expect(out[0].action, SegmentAction.autoSkip);
      expect(out[1].action, SegmentAction.pill);
    });

    test('show with skipping off only points segments out', () {
      final out = resolveSegments([seg('a', 10, 20)], actions,
          skippingOn: false);
      expect(out.single.action, SegmentAction.pill);
    });

    test('overlapping segments merge; the stronger action wins', () {
      final out = mergeSegments([
        seg('p', 10, 30,
            c: SegmentCategory.selfpromo, action: SegmentAction.pill),
        seg('s', 25, 50),
        seg('x', 80, 90, action: SegmentAction.pill),
      ]);
      expect(out.length, 2);
      expect(out[0].start, 10);
      expect(out[0].end, 50);
      expect(out[0].action, SegmentAction.autoSkip);
      expect(out[0].category, SegmentCategory.sponsor);
      expect(out[0].id, 'p');
      expect(out[1].id, 'x');
    });

    test('touching segments merge, unsorted input is fine', () {
      final out = mergeSegments([seg('b', 20, 30), seg('a', 10, 20)]);
      expect(out.single.start, 10);
      expect(out.single.end, 30);
    });

    test('tiny segments are dropped', () {
      expect(resolveSegments([seg('a', 10, 10.1)], actions), isEmpty);
    });
  });

  group('when to auto-skip', () {
    final s = seg('a', 100, 130);

    test('playback running into the segment from before its start', () {
      expect(enteredFromBefore(s, 99.8, 100.0), isTrue);
      expect(enteredFromBefore(s, 99.0, 101.5), isTrue);
    });

    test('a seek into the middle does not count', () {
      expect(enteredFromBefore(s, 40, 110), isFalse);
      expect(enteredFromBefore(s, 105, 105.2), isFalse);
    });

    test('outside the segment never counts', () {
      expect(enteredFromBefore(s, 99, 99.5), isFalse);
      expect(enteredFromBefore(s, 129.9, 130.1), isFalse);
    });

    test('segmentAt finds the covering segment', () {
      final list = [seg('a', 10, 20), seg('b', 30, 40)];
      expect(segmentAt(list, 15)?.id, 'a');
      expect(segmentAt(list, 25), isNull);
      expect(segmentAt(list, 39.9)?.id, 'b');
    });

    test('length label', () {
      expect(formatSegmentLength(42), '0:42');
      expect(formatSegmentLength(65.4), '1:05');
      expect(formatSegmentLength(3909), '1:05:09');
    });
  });

  group('sources', () {
    test('chapters: ads become sponsor, intro / outro keep their kind', () {
      final out = segmentsFromChapters([
        PodcastChapter(startSec: 0, title: 'Intro'),
        PodcastChapter(startSec: 30, title: 'The story'),
        PodcastChapter(startSec: 600, title: 'Sponsor: Acme'),
        PodcastChapter(startSec: 660, title: 'Part two'),
        PodcastChapter(startSec: 1200, title: 'Credits'),
      ], 1300);
      expect(out.map((s) => s.category.apiName), ['intro', 'sponsor', 'outro']);
      expect(out[1].start, 600);
      expect(out[1].end, 660);
      expect(out[2].end, 1300);
      expect(out.every((s) => s.source == SegmentSource.chapters), isTrue);
    });

    test('hash prefix is the first 4 hex digits of sha256', () {
      // Checked against Python's hashlib.sha256(b'dQw4w9WgXcQ').
      expect(sponsorBlockHashPrefix('dQw4w9WgXcQ'), '5f6b');
    });

    test('hash response: only our video, skip / mute only, junk dropped', () {
      final out = parseSponsorBlockHashResponse([
        {
          'videoID': 'otherVideo1',
          'segments': [
            {'segment': [1, 2], 'category': 'sponsor', 'actionType': 'skip'}
          ],
        },
        {
          'videoID': 'abcdefghijk',
          'segments': [
            {
              'segment': [50.5, 80],
              'category': 'selfpromo',
              'actionType': 'skip',
              'UUID': 'u2'
            },
            {
              'segment': [10, 40],
              'category': 'sponsor',
              'actionType': 'skip',
              'UUID': 'u1'
            },
            {'segment': [90, 95], 'category': 'sponsor', 'actionType': 'poi'},
            {'segment': [99, 98], 'category': 'sponsor'},
            {'segment': [100, 110], 'category': 'mystery'},
            {
              'segment': [120, 130],
              'category': 'music_offtopic',
              'actionType': 'mute'
            },
          ],
        },
      ], 'abcdefghijk');
      expect(out.map((s) => s.id), ['sb_u1', 'sb_u2', 'sb_120_130']);
      expect(out.first.category, SegmentCategory.sponsor);
      expect(out.last.category, SegmentCategory.musicOfftopic);
    });

    test('hash response as a JSON string, and garbage', () {
      expect(
          parseSponsorBlockHashResponse(
              '[{"videoID":"abcdefghijk","segments":[{"segment":[1,5],"category":"intro"}]}]',
              'abcdefghijk'),
          hasLength(1));
      expect(parseSponsorBlockHashResponse('nope', 'x'), isEmpty);
      expect(parseSponsorBlockHashResponse({'a': 1}, 'x'), isEmpty);
    });

    test('cache freshness is 24 h', () {
      final now = DateTime(2026, 10, 3, 12);
      final fresh = now.subtract(const Duration(hours: 23)).millisecondsSinceEpoch;
      final stale = now.subtract(const Duration(hours: 25)).millisecondsSinceEpoch;
      expect(segmentCacheFresh(fresh, now), isTrue);
      expect(segmentCacheFresh(stale, now), isFalse);
      expect(segmentCacheFresh(null, now), isFalse);
      expect(segmentCacheFresh(now.add(const Duration(hours: 1)).millisecondsSinceEpoch, now), isFalse);
    });

    test('YouTube video id shape', () {
      expect(looksLikeYoutubeVideoId('dQw4w9WgXcQ'), isTrue);
      expect(looksLikeYoutubeVideoId('podcast_123'), isFalse);
    });

    test('json round trip; bad entries return null', () {
      final s = seg('m1', 5, 9, source: SegmentSource.manual);
      final back = PodcastSegment.fromJson(s.toJson())!;
      expect(back.id, 'm1');
      expect(back.start, 5);
      expect(back.source, SegmentSource.manual);
      expect(PodcastSegment.fromJson({'start': 9, 'end': 5, 'category': 'sponsor'}),
          isNull);
      expect(PodcastSegment.fromJson('x'), isNull);
    });
  });

  group('PodcastSegmentStore (Hive)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_segments_');
      Hive.init(tmp.path);
      await Hive.openBox('AppPrefs');
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('actions persist; the legacy switch seeds sponsor', () async {
      await Hive.box('AppPrefs').put('podcastAutoSkipAds', false);
      expect(PodcastSegmentStore.actions[SegmentCategory.sponsor],
          SegmentAction.pill);
      await PodcastSegmentStore.setAction(
          SegmentCategory.intro, SegmentAction.autoSkip);
      final a = PodcastSegmentStore.actions;
      expect(a[SegmentCategory.intro], SegmentAction.autoSkip);
      expect(a[SegmentCategory.sponsor], SegmentAction.pill);
    });

    test('cache, manual segments and time saved', () async {
      final now = DateTime.now();
      expect(PodcastSegmentStore.cached('ep', now), isNull);
      await PodcastSegmentStore.putCache('ep', [seg('a', 1, 5)], now);
      expect(PodcastSegmentStore.cached('ep', now), hasLength(1));
      expect(
          PodcastSegmentStore.cached(
              'ep', now.add(const Duration(hours: 25))),
          isNull);

      await PodcastSegmentStore.addManual(
          'ep', seg('m', 10, 20, source: SegmentSource.manual));
      expect(PodcastSegmentStore.manual('ep').single.id, 'm');
      await PodcastSegmentStore.removeManual('ep', 'm');
      expect(PodcastSegmentStore.manual('ep'), isEmpty);

      await PodcastSegmentStore.addTimeSaved(const Duration(seconds: 30));
      await PodcastSegmentStore.addTimeSaved(const Duration(seconds: 12));
      expect(PodcastSegmentStore.timeSaved, const Duration(seconds: 42));
    });
  });
}
