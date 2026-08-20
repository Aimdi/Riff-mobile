// Pure ranking helpers that consume listen-fraction / skip / source stats.
// No Flutter / Hive / GetX.

import 'discovery_types.dart';

/// How much a play source should boost later recommendations.
///
/// Favorites, downloads, playlists, and artist-page taps are high-signal.
/// Radio / home-noise / Auto are weak — they should not dominate Daily Mix
/// or similar-song ranking.
double sourceSignalWeight(DiscoverySource source) {
  switch (source) {
    case DiscoverySource.downloads:
    case DiscoverySource.playlist:
    case DiscoverySource.album:
    case DiscoverySource.artist:
      return 1.15;
    case DiscoverySource.userClick:
    case DiscoverySource.search:
    case DiscoverySource.home:
      return 1.0;
    case DiscoverySource.cloud:
    case DiscoverySource.podcast:
    case DiscoverySource.audiobook:
    case DiscoverySource.soulseek:
    case DiscoverySource.torrent:
      return 0.85;
    case DiscoverySource.dailyMix:
    case DiscoverySource.similar:
    case DiscoverySource.related:
      return 0.5;
    case DiscoverySource.queue:
      return 0.45;
    case DiscoverySource.radio:
    case DiscoverySource.discover:
    case DiscoverySource.freshFinds:
    case DiscoverySource.androidAuto:
    case DiscoverySource.shuffle:
    case DiscoverySource.smartShuffle:
    case DiscoverySource.unknown:
      return 0.3;
  }
}

/// Per-track listen quality: reward completes, penalize habitual skips.
double listenQualityAdjustment({
  double? meanFraction,
  required double skipRate,
  required int plays,
}) {
  var adj = 0.0;
  if (meanFraction != null) {
    if (meanFraction >= 0.85) {
      adj += 1.6 + (plays >= 3 ? 0.4 : 0);
    } else if (meanFraction >= 0.30) {
      adj += 0.35;
    } else if (plays >= 1) {
      adj -= 1.4;
    }
  }
  if (plays >= 2 && skipRate >= 0.5) {
    adj -= skipRate * 3.2;
  } else if (skipRate >= 0.4) {
    adj -= skipRate * 2.2;
  }
  return adj;
}

/// Additive bonus for [TasteModel.scoreCandidate] / mix ranking.
double statsRankingBonus({
  double? meanFraction,
  required double trackSkipRate,
  required int plays,
  DiscoverySource? lastSource,
}) {
  var bonus = listenQualityAdjustment(
    meanFraction: meanFraction,
    skipRate: trackSkipRate,
    plays: plays,
  );
  if (lastSource != null) {
    bonus += (sourceSignalWeight(lastSource) - 0.5) * 1.4;
  }
  return bonus;
}

/// Map a home/mix surface to the extras source stamped on play.
DiscoverySource sourceForSurface(String surface) {
  switch (surface) {
    case DiscoverySurface.dailyMix:
      return DiscoverySource.dailyMix;
    case DiscoverySurface.freshFinds:
      return DiscoverySource.freshFinds;
    case DiscoverySurface.similar:
    case DiscoverySurface.becauseYouLiked:
      return DiscoverySource.similar;
    case DiscoverySurface.radio:
      return DiscoverySource.radio;
    case DiscoverySurface.smartShuffle:
      return DiscoverySource.smartShuffle;
    case DiscoverySurface.home:
      return DiscoverySource.home;
    default:
      return DiscoverySource.discover;
  }
}
