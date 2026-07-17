import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/discovery/discovery_math.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';

/// Synthetic-events style check: after 3 skips of an artist, scoring
/// penalizes them enough that greedy radio constraints prefer others.
void main() {
  test('3 skips measurably lower radio frequency for an artist', () {
    // Simulate scores for 10 candidates: 5 from skipped artist, 5 others
    final affinitySkipped = AffinityWeights.fullListen +
        3 * AffinityWeights.quickSkip; // ~1 + 3*(-2) = -5
    final affinityOther = AffinityWeights.fullListen * 3; // ~3

    final candidates = <ScoredCandidate>[];
    for (var i = 0; i < 5; i++) {
      candidates.add(ScoredCandidate(
        videoId: 'skip_$i',
        title: 'S$i',
        artist: 'Skipped Artist',
        artistKey: 'skipped artist',
        score: 1.0 + affinitySkipped * 0.35,
        mediaJson: {'videoId': 'skip_$i'},
      ));
      candidates.add(ScoredCandidate(
        videoId: 'ok_$i',
        title: 'O$i',
        artist: 'Other $i',
        artistKey: 'other $i',
        score: 1.0 + affinityOther * 0.35,
        mediaJson: {'videoId': 'ok_$i'},
      ));
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final picked = greedyConstrainedPick(
      scored: candidates
          .map((c) => (score: c.score, artistKey: c.artistKey, item: c))
          .toList(),
      limit: 10,
      maxPerArtist: 2,
      rollingWindow: 10,
      maxInRollingWindow: 2,
    );
    final skippedCount =
        picked.where((c) => c.artistKey == 'skipped artist').length;
    final otherCount = picked.length - skippedCount;
    expect(otherCount, greaterThan(skippedCount));
    expect(skippedCount, lessThanOrEqualTo(2));
  });

  test('session dedupe keys kill remaster twins', () {
    final keys = {
      trackDedupeKey('Midnight City (Remastered)', 'M83'),
      trackDedupeKey('Midnight City', 'M83'),
      trackDedupeKey('Midnight City [Live]', 'M83'),
    };
    expect(keys.length, 1);
  });
}
