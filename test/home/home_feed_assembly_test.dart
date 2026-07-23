import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/discovery/home_feed_assembly.dart';

HomeFeedTrack _t(String id, String artist) => HomeFeedTrack(
      id: id,
      artistKey: artist,
      mediaJson: {
        'videoId': id,
        'title': id,
        'artists': [
          {'name': artist}
        ],
      },
    );

HomeFeedCandidateSection _section(
  String id,
  List<HomeFeedTrack> tracks, {
  int minCount = 6,
  int targetCount = 12,
  int? maxPerArtist,
}) =>
    HomeFeedCandidateSection(
      id: id,
      title: id,
      candidates: tracks,
      minCount: minCount,
      targetCount: targetCount,
      maxPerArtist: maxPerArtist,
    );

void main() {
  group('buildHomeFeed', () {
    test('drops duplicate media ids across sections', () {
      final shared = _t('same', 'a');
      final assembled = buildHomeFeed([
        _section('daily', [shared, _t('d2', 'b'), _t('d3', 'c')],
            minCount: 2, targetCount: 6, maxPerArtist: 1),
        _section('quick', [
          shared,
          _t('q1', 'd'),
          _t('q2', 'e'),
          _t('q3', 'f'),
          _t('q4', 'g'),
          _t('q5', 'h'),
          _t('q6', 'i'),
          _t('q7', 'j'),
          _t('q8', 'k'),
        ], minCount: 8, targetCount: 24),
      ]);

      final allIds = [
        for (final s in assembled.zoneB)
          for (final t in s.tracks) t.id
      ];
      expect(allIds.toSet().length, allIds.length);
      expect(allIds.where((id) => id == 'same').length, 1);
    });

    test('enforces max 2 per artist across the feed', () {
      final assembled = buildHomeFeed([
        _section('because', [
          _t('1', 'merlin'),
          _t('2', 'merlin'),
          _t('3', 'merlin'),
          _t('4', 'other'),
          _t('5', 'other2'),
          _t('6', 'other3'),
          _t('7', 'other4'),
          _t('8', 'other5'),
        ]),
      ]);

      expect(assembled.zoneB, hasLength(1));
      final artists = [
        for (final t in assembled.zoneB.first.tracks) t.artistKey
      ];
      expect(artists.where((a) => a == 'merlin').length, 2);
      expect(artists.contains('merlin'), isTrue);
    });

    test('omits sections below minCount after dedupe', () {
      final assembled = buildHomeFeed([
        _section('thin', [_t('a', 'x'), _t('b', 'y')], minCount: 6),
        _section('ok', [
          for (var i = 0; i < 8; i++) _t('ok$i', 'artist$i'),
        ], minCount: 6),
      ]);

      expect(assembled.zoneB.map((s) => s.id), ['ok']);
    });

    test('hard-caps Zone B at 3 sections', () {
      HomeFeedCandidateSection fat(String id) => _section(id, [
            for (var i = 0; i < 8; i++) _t('$id-$i', '$id-a$i'),
          ]);

      final assembled = buildHomeFeed([
        fat('s1'),
        fat('s2'),
        fat('s3'),
        fat('s4'),
      ]);

      expect(assembled.zoneB, hasLength(3));
      expect(assembled.zoneB.map((s) => s.id).toList(), ['s1', 's2', 's3']);
    });

    test('priority order keeps daily → quick → first qualifying contextual',
        () {
      final priority = zoneBPriorityOrder(
        dailyMixes: _section('made_for_you', [
          _t('m1', 'a'),
          _t('m2', 'b'),
        ], minCount: 2, targetCount: 6, maxPerArtist: 1),
        quickPicks: _section('quick_picks', [
          for (var i = 0; i < 10; i++) _t('q$i', 'qa$i'),
        ], minCount: 8, targetCount: 24),
        contextual: [
          _section('because_x', [
            for (var i = 0; i < 8; i++) _t('b$i', 'ba$i'),
          ]),
          _section('rediscover', [
            for (var i = 0; i < 8; i++) _t('r$i', 'ra$i'),
          ]),
        ],
      );

      final assembled = buildHomeFeed(priority);
      expect(assembled.zoneB.map((s) => s.id).toList(),
          ['made_for_you', 'quick_picks', 'because_x']);
    });
  });

  group('uniqueDailyMixLeads', () {
    GeneratedMix mix(String id, List<String> trackIds, {String artist = 'a'}) =>
        GeneratedMix(
          id: id,
          title: id,
          reason: '',
          kind: MixKind.dailyMix,
          generatedTs: 0,
          tracks: [
            for (final tid in trackIds)
              {
                'videoId': tid,
                'title': tid,
                'artists': [
                  {'name': artist}
                ],
              },
          ],
        );

    test('does not repeat the same lead across mixes', () {
      final mixes = [
        mix('daily_mix_1', ['pad', 'a1'], artist: 'charts'),
        mix('daily_mix_2', ['pad', 'b1'], artist: 'charts'),
        mix('daily_mix_3', ['pad', 'c1'], artist: 'charts'),
      ];
      final leads = uniqueDailyMixLeads(mixes);
      final ids = leads.map((e) => e['videoId']).toList();
      expect(ids.toSet().length, ids.length);
      // First mix may take the shared pad; later mixes walk past it.
      expect(ids, ['pad', 'b1', 'c1']);
    });

    test('prefers distinct artists for leads', () {
      final mixes = [
        mix('daily_mix_1', ['t1'], artist: 'merlin'),
        mix('daily_mix_2', ['t2'], artist: 'merlin'),
        mix('daily_mix_3', ['t3'], artist: 'other'),
      ];
      final leads = uniqueDailyMixLeads(mixes);
      // Second mix has only merlin — falls back after artist preference miss.
      expect(leads.map((e) => e['videoId']).toSet().length, 3);
    });
  });
}
