import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/discovery/discovery_math.dart';

void main() {
  group('decayed', () {
    test('unchanged at t=0', () {
      expect(decayed(10, Duration.zero, affinityHalfLife), 10);
    });

    test('halves at half-life', () {
      final v = decayed(10, affinityHalfLife, affinityHalfLife);
      expect(v, closeTo(5.0, 0.01));
    });

    test('quarters at 2x half-life', () {
      final v = decayed(10, affinityHalfLife * 2, affinityHalfLife);
      expect(v, closeTo(2.5, 0.01));
    });

    test('zero stays zero', () {
      expect(decayed(0, const Duration(days: 100), affinityHalfLife), 0);
    });
  });

  group('normalizeArtistKey', () {
    test('strips feat.', () {
      expect(normalizeArtistKey('A feat. B'), 'a');
      expect(normalizeArtistKey('A ft. B'), 'a');
      expect(normalizeArtistKey('A (feat. B)'), 'a');
    });

    test('ampersand and punctuation', () {
      expect(normalizeArtistKey('A & B'), 'a b');
      expect(normalizeArtistKey('A, B'), 'a b');
    });

    test('lowercase and collapse space', () {
      expect(normalizeArtistKey('  The  Weeknd  '), 'the weeknd');
    });

    test('empty', () {
      expect(normalizeArtistKey(null), '');
      expect(normalizeArtistKey(''), '');
    });
  });

  group('normalizeTitleKey / trackDedupeKey', () {
    test('strips remaster suffix', () {
      expect(normalizeTitleKey('Song (Remastered 2011)'), 'song');
      expect(normalizeTitleKey('Song [Live]'), 'song');
    });

    test('dedupe key matches remaster twins', () {
      final a = trackDedupeKey('Hello (Remastered)', 'Adele');
      final b = trackDedupeKey('Hello', 'Adele');
      expect(a, b);
    });
  });

  group('classifyListen', () {
    test('thresholds', () {
      expect(classifyListen(0.9), ListenQuality.strongPositive);
      expect(classifyListen(0.85), ListenQuality.strongPositive);
      expect(classifyListen(0.5), ListenQuality.weakPositive);
      expect(classifyListen(0.3), ListenQuality.weakPositive);
      expect(classifyListen(0.1), ListenQuality.negative);
    });
  });

  group('greedyConstrainedPick', () {
    test('max 2 per artist and no back-to-back', () {
      final scored = <({double score, String artistKey, String item})>[
        (score: 10, artistKey: 'a', item: 'a1'),
        (score: 9, artistKey: 'a', item: 'a2'),
        (score: 8, artistKey: 'a', item: 'a3'),
        (score: 7, artistKey: 'b', item: 'b1'),
        (score: 6, artistKey: 'c', item: 'c1'),
        (score: 5, artistKey: 'b', item: 'b2'),
      ];
      final picked = greedyConstrainedPick(
        scored: scored,
        limit: 10,
        maxPerArtist: 2,
      );
      // a1, then cannot pick a2 back-to-back → b1, a2, c1, b2
      expect(picked.where((e) => e.startsWith('a')).length, 2);
      for (var i = 1; i < picked.length; i++) {
        final prev = scored.firstWhere((s) => s.item == picked[i - 1]).artistKey;
        final cur = scored.firstWhere((s) => s.item == picked[i]).artistKey;
        expect(prev == cur, isFalse, reason: 'back-to-back $prev');
      }
    });

    test('radio rolling window max 2 in 10', () {
      final scored = List.generate(
        20,
        (i) => (
          score: 20.0 - i,
          artistKey: i.isEven ? 'hot' : 'other$i',
          item: 't$i',
        ),
      );
      final picked = greedyConstrainedPick(
        scored: scored,
        limit: 10,
        maxPerArtist: 5,
        rollingWindow: 10,
        maxInRollingWindow: 2,
      );
      final hotInPick = picked.where((e) {
        final idx = int.parse(e.substring(1));
        return idx.isEven;
      }).length;
      expect(hotInPick, lessThanOrEqualTo(2));
    });
  });

  group('SeededRng', () {
    test('deterministic', () {
      final a = SeededRng(42);
      final b = SeededRng(42);
      expect(List.generate(5, (_) => a.nextDouble()),
          List.generate(5, (_) => b.nextDouble()));
    });
  });
}
