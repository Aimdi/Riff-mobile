// Pure feed-assembly rules for the Home tab.
// No Flutter / GetX — unit-testable in isolation.
//
// The feed has three jobs (resume / recommend / browse). Zone B is capped
// and globally de-duplicated so one seed track cannot appear five times.

import 'discovery_math.dart';
import 'discovery_types.dart';

/// Cross-feed artist cap (kills three-identical-Daily-Mix-lead cards).
const int kHomeFeedMaxPerArtist = 2;

/// Hard cap on personalised Zone B sections (daily mixes + QP + contextual).
const int kHomeFeedZoneBCap = 3;

/// Carousel floor — thinner than this → omit the section.
const int kHomeFeedCarouselMin = 6;

/// Quick picks floor.
const int kHomeFeedQuickPicksMin = 8;

/// Carousel target length after dedupe.
const int kHomeFeedCarouselTarget = 12;

/// Daily-mix lead cards (one card per mix) — lower floor; 3–5 mixes is normal.
const int kHomeFeedDailyMixMin = 2;
const int kHomeFeedDailyMixTarget = 6;

/// A track-shaped candidate for assembly (videoId + artist key).
class HomeFeedTrack {
  const HomeFeedTrack({
    required this.id,
    required this.artistKey,
    this.mediaJson,
  });

  final String id;
  final String artistKey;

  /// Original discovery JSON when the section is a [DiscoverySection].
  final Map<String, dynamic>? mediaJson;

  factory HomeFeedTrack.fromMediaJson(Map<String, dynamic> json) {
    final id = (json['videoId'] ?? json['id'] ?? '').toString();
    String artist = '';
    final artists = json['artists'];
    if (artists is List && artists.isNotEmpty) {
      artist = (artists.first['name'] ?? '').toString();
    } else {
      artist = (json['artist'] ?? '').toString();
    }
    return HomeFeedTrack(
      id: id,
      artistKey: normalizeArtistKey(artist),
      mediaJson: json,
    );
  }
}

/// Input slot before global dedupe / caps.
class HomeFeedCandidateSection {
  const HomeFeedCandidateSection({
    required this.id,
    required this.title,
    required this.candidates,
    required this.minCount,
    required this.targetCount,
    this.reason = '',
    this.surface = DiscoverySurface.home,
    this.maxPerArtist,
  });

  final String id;
  final String title;
  final String reason;
  final String surface;
  final List<HomeFeedTrack> candidates;
  final int minCount;
  final int targetCount;

  /// Override global artist cap for this section (e.g. 1 for daily-mix leads).
  final int? maxPerArtist;
}

/// A section that survived assembly.
class HomeFeedAssembledSection {
  const HomeFeedAssembledSection({
    required this.id,
    required this.title,
    required this.reason,
    required this.tracks,
    required this.surface,
  });

  final String id;
  final String title;
  final String reason;
  final String surface;
  final List<HomeFeedTrack> tracks;

  DiscoverySection toDiscoverySection() => DiscoverySection(
        id: id,
        title: title,
        reason: reason,
        surface: surface,
        tracks: [
          for (final t in tracks)
            if (t.mediaJson != null) Map<String, dynamic>.from(t.mediaJson!),
        ],
      );
}

/// Result of [buildHomeFeed].
class HomeFeedAssembly {
  const HomeFeedAssembly({
    required this.zoneB,
    required this.seenIds,
    required this.seenArtists,
  });

  /// Personalised sections in render order (≤ [kHomeFeedZoneBCap]).
  final List<HomeFeedAssembledSection> zoneB;

  /// Media IDs already shown — callers may continue deduping Zone C against this.
  final Set<String> seenIds;

  /// Artist → count across the assembled feed.
  final Map<String, int> seenArtists;
}

/// Zone B priority: daily mixes → quick picks → contextual rows.
///
/// Contextual order matches the redesign brief:
/// Because you liked → (optional followed) → Rediscover → Fresh finds.
List<HomeFeedCandidateSection> zoneBPriorityOrder({
  HomeFeedCandidateSection? dailyMixes,
  HomeFeedCandidateSection? quickPicks,
  List<HomeFeedCandidateSection> contextual = const [],
}) {
  return [
    if (dailyMixes != null) dailyMixes,
    if (quickPicks != null) quickPicks,
    ...contextual,
  ];
}

/// Build Zone B with global track/artist de-duplication and section caps.
///
/// A section that cannot fill [HomeFeedCandidateSection.minCount] unique items
/// is dropped entirely. Assembly stops once [kHomeFeedZoneBCap] sections pass.
HomeFeedAssembly buildHomeFeed(
  List<HomeFeedCandidateSection> priorityOrder, {
  int maxPerArtist = kHomeFeedMaxPerArtist,
  int zoneBCap = kHomeFeedZoneBCap,
}) {
  final seen = <String>{};
  final seenArtists = <String, int>{};
  final sections = <HomeFeedAssembledSection>[];

  for (final section in priorityOrder) {
    if (sections.length >= zoneBCap) break;

    final artistCap = section.maxPerArtist ?? maxPerArtist;
    final items = <HomeFeedTrack>[];
    // Local counts so artist caps apply inside the section too; only
    // committed to [seenArtists] when the section passes minCount.
    final localArtists = Map<String, int>.from(seenArtists);

    for (final item in section.candidates) {
      if (item.id.isEmpty) continue;
      if (seen.contains(item.id)) continue;
      final artistCount = localArtists[item.artistKey] ?? 0;
      if (item.artistKey.isNotEmpty && artistCount >= artistCap) continue;
      items.add(item);
      if (item.artistKey.isNotEmpty) {
        localArtists[item.artistKey] = artistCount + 1;
      }
      if (items.length >= section.targetCount) break;
    }

    if (items.length < section.minCount) continue;

    for (final item in items) {
      seen.add(item.id);
      if (item.artistKey.isNotEmpty) {
        seenArtists[item.artistKey] = (seenArtists[item.artistKey] ?? 0) + 1;
      }
    }

    sections.add(HomeFeedAssembledSection(
      id: section.id,
      title: section.title,
      reason: section.reason,
      surface: section.surface,
      tracks: items,
    ));
  }

  return HomeFeedAssembly(
    zoneB: sections,
    seenIds: seen,
    seenArtists: seenArtists,
  );
}

/// Filter a list of track JSON maps with an existing seen-set (Zone C / spill).
List<Map<String, dynamic>> takeUniqueTracks(
  Iterable<Map<String, dynamic>> candidates, {
  required Set<String> seenIds,
  required Map<String, int> seenArtists,
  int maxPerArtist = kHomeFeedMaxPerArtist,
  int targetCount = kHomeFeedCarouselTarget,
  int minCount = kHomeFeedCarouselMin,
}) {
  final out = <Map<String, dynamic>>[];
  for (final raw in candidates) {
    final t = HomeFeedTrack.fromMediaJson(Map<String, dynamic>.from(raw));
    if (t.id.isEmpty || seenIds.contains(t.id)) continue;
    final artistCount = seenArtists[t.artistKey] ?? 0;
    if (t.artistKey.isNotEmpty && artistCount >= maxPerArtist) continue;
    out.add(Map<String, dynamic>.from(raw));
    seenIds.add(t.id);
    if (t.artistKey.isNotEmpty) {
      seenArtists[t.artistKey] = artistCount + 1;
    }
    if (out.length >= targetCount) break;
  }
  if (out.length < minCount) return const [];
  return out;
}

/// Pick unique lead tracks for daily-mix cards (one per mix).
/// Walks each mix until a track that is not already used as a lead is found.
List<Map<String, dynamic>> uniqueDailyMixLeads(
  List<GeneratedMix> mixes, {
  int maxLeads = kHomeFeedDailyMixTarget,
}) {
  final seenIds = <String>{};
  final seenArtists = <String>{};
  final leads = <Map<String, dynamic>>[];

  for (final mix in mixes) {
    if (leads.length >= maxLeads) break;
    Map<String, dynamic>? chosen;
    for (final raw in mix.tracks) {
      final map = Map<String, dynamic>.from(raw);
      final t = HomeFeedTrack.fromMediaJson(map);
      if (t.id.isEmpty || seenIds.contains(t.id)) continue;
      // Prefer a fresh artist for the lead card so three mixes don't
      // all show the same pad-from-charts track / artist.
      if (t.artistKey.isNotEmpty && seenArtists.contains(t.artistKey)) {
        continue;
      }
      chosen = {
        ...map,
        // Stash mix identity so UI can open the full mix later.
        'dailyMixId': mix.id,
        'dailyMixTitle': mix.title,
      };
      break;
    }
    // Fallback: allow artist reuse if every remaining lead collides.
    if (chosen == null) {
      for (final raw in mix.tracks) {
        final map = Map<String, dynamic>.from(raw);
        final t = HomeFeedTrack.fromMediaJson(map);
        if (t.id.isEmpty || seenIds.contains(t.id)) continue;
        chosen = {
          ...map,
          'dailyMixId': mix.id,
          'dailyMixTitle': mix.title,
        };
        break;
      }
    }
    if (chosen == null) continue;
    final t = HomeFeedTrack.fromMediaJson(chosen);
    seenIds.add(t.id);
    if (t.artistKey.isNotEmpty) seenArtists.add(t.artistKey);
    leads.add(chosen);
  }
  return leads;
}
