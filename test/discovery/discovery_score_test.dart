import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/discovery/discovery_score.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';

void main() {
  group('sourceSignalWeight', () {
    test('playlist download artist outrank radio and home noise', () {
      expect(sourceSignalWeight(DiscoverySource.downloads),
          greaterThan(sourceSignalWeight(DiscoverySource.radio)));
      expect(sourceSignalWeight(DiscoverySource.playlist),
          greaterThan(sourceSignalWeight(DiscoverySource.discover)));
      expect(sourceSignalWeight(DiscoverySource.artist),
          greaterThan(sourceSignalWeight(DiscoverySource.androidAuto)));
      expect(sourceSignalWeight(DiscoverySource.search),
          greaterThan(sourceSignalWeight(DiscoverySource.freshFinds)));
    });
  });

  group('listenQualityAdjustment', () {
    test('full listens are rewarded; habitual skips are penalized', () {
      final keeper = listenQualityAdjustment(
        meanFraction: 0.92,
        skipRate: 0.0,
        plays: 4,
      );
      final skipper = listenQualityAdjustment(
        meanFraction: 0.12,
        skipRate: 0.7,
        plays: 5,
      );
      expect(keeper, greaterThan(1.5));
      expect(skipper, lessThan(-2.5));
      expect(keeper, greaterThan(skipper));
    });

    test('unknown fraction with no plays is neutral', () {
      expect(
        listenQualityAdjustment(meanFraction: null, skipRate: 0, plays: 0),
        0,
      );
    });
  });

  group('statsRankingBonus', () {
    test('a kept download outranks a skipped radio play', () {
      final high = statsRankingBonus(
        meanFraction: 0.95,
        trackSkipRate: 0.0,
        plays: 3,
        lastSource: DiscoverySource.downloads,
      );
      final low = statsRankingBonus(
        meanFraction: 0.1,
        trackSkipRate: 0.8,
        plays: 4,
        lastSource: DiscoverySource.radio,
      );
      expect(high, greaterThan(low + 3));
    });
  });

  group('sourceForSurface', () {
    test('maps home shelves to play sources', () {
      expect(sourceForSurface(DiscoverySurface.freshFinds),
          DiscoverySource.freshFinds);
      expect(sourceForSurface(DiscoverySurface.dailyMix),
          DiscoverySource.dailyMix);
      expect(sourceForSurface(DiscoverySurface.becauseYouLiked),
          DiscoverySource.similar);
      expect(sourceForSurface(DiscoverySurface.home), DiscoverySource.home);
    });
  });
}
