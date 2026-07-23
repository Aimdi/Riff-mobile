/// Maps live Home/Discovery observables through [buildHomeFeed].
library;

import 'package:audio_service/audio_service.dart';

import '../../../models/quick_picks.dart';
import '../../../services/discovery/discovery_math.dart';
import '../../../services/discovery/discovery_types.dart';
import '../../../services/discovery/home_feed_assembly.dart';

HomeFeedCandidateSection? candidateFromDailyMixSection(DiscoverySection? s) {
  if (s == null || s.tracks.isEmpty) return null;
  return HomeFeedCandidateSection(
    id: s.id,
    title: s.title,
    reason: '',
    surface: s.surface,
    candidates: [
      for (final t in s.tracks) HomeFeedTrack.fromMediaJson(t),
    ],
    minCount: kHomeFeedDailyMixMin,
    targetCount: kHomeFeedDailyMixTarget,
    maxPerArtist: 1,
  );
}

HomeFeedCandidateSection? candidateFromQuickPicks(QuickPicks qp) {
  if (qp.songList.isEmpty) return null;
  return HomeFeedCandidateSection(
    id: 'quick_picks',
    title: 'Quick picks',
    reason: '',
    surface: DiscoverySurface.home,
    candidates: [
      for (final m in qp.songList)
        HomeFeedTrack(
          id: m.id,
          artistKey: normalizeArtistKey(m.artist),
        ),
    ],
    minCount: kHomeFeedQuickPicksMin,
    targetCount: 24,
  );
}

HomeFeedCandidateSection candidateFromContextual(DiscoverySection s) {
  return HomeFeedCandidateSection(
    id: s.id,
    title: s.title,
    reason: '',
    surface: s.surface,
    candidates: [
      for (final t in s.tracks) HomeFeedTrack.fromMediaJson(t),
    ],
    minCount: kHomeFeedCarouselMin,
    targetCount: kHomeFeedCarouselTarget,
  );
}

/// Contextual priority: Because → Rediscover → Fresh finds.
List<HomeFeedCandidateSection> contextualCandidatesInPriority(
    List<DiscoverySection> personal) {
  DiscoverySection? because;
  DiscoverySection? rediscover;
  DiscoverySection? fresh;
  for (final s in personal) {
    if (s.id.startsWith('because_')) {
      because ??= s;
    } else if (s.id == 'rediscover') {
      rediscover = s;
    } else if (s.id == 'fresh_finds') {
      fresh = s;
    }
  }
  return [
    if (because != null) candidateFromContextual(because),
    if (rediscover != null) candidateFromContextual(rediscover),
    if (fresh != null) candidateFromContextual(fresh),
  ];
}

/// Map assembled Zone B back into widgets' expected shapes.
class HomeFeedViewModel {
  HomeFeedViewModel({
    this.dailyMixes,
    this.quickPicks,
    this.contextual,
    required this.seenIds,
    required this.seenArtists,
  });

  final DiscoverySection? dailyMixes;
  final QuickPicks? quickPicks;
  final DiscoverySection? contextual;
  final Set<String> seenIds;
  final Map<String, int> seenArtists;
}

HomeFeedViewModel assembleHomeFeedViewModel({
  required List<DiscoverySection> personalSections,
  required QuickPicks quickPicks,
}) {
  DiscoverySection? daily;
  for (final s in personalSections) {
    if (s.id == 'made_for_you') {
      daily = s;
      break;
    }
  }

  final byId = <String, MediaItem>{
    for (final m in quickPicks.songList) m.id: m,
  };

  final priority = zoneBPriorityOrder(
    dailyMixes: candidateFromDailyMixSection(daily),
    quickPicks: candidateFromQuickPicks(quickPicks),
    contextual: contextualCandidatesInPriority(personalSections),
  );

  final assembled = buildHomeFeed(priority);

  DiscoverySection? outDaily;
  QuickPicks? outQp;
  DiscoverySection? outContextual;

  for (final s in assembled.zoneB) {
    if (s.id == 'made_for_you') {
      outDaily = s.toDiscoverySection();
    } else if (s.id == 'quick_picks') {
      final songs = <MediaItem>[
        for (final t in s.tracks)
          if (byId.containsKey(t.id)) byId[t.id]!,
      ];
      outQp = QuickPicks(songs, title: s.title);
    } else {
      outContextual ??= s.toDiscoverySection();
    }
  }

  return HomeFeedViewModel(
    dailyMixes: outDaily,
    quickPicks: outQp,
    contextual: outContextual,
    seenIds: assembled.seenIds,
    seenArtists: assembled.seenArtists,
  );
}
