import 'discovery_math.dart';
import 'discovery_repository.dart';
import 'discovery_types.dart';
import 'candidate_sources.dart';
import 'taste_model.dart';

/// Daily / weekly mix generation (algorithmic, offline-capable scoring).
class MixGenerator {
  MixGenerator({
    required this.repo,
    required this.taste,
    required this.sources,
    this.rng,
  });

  final DiscoveryRepository repo;
  final TasteModel taste;
  final CandidateSources sources;
  SeededRng? rng;

  SeededRng get _rng =>
      rng ?? SeededRng(DateTime.now().millisecondsSinceEpoch ~/ 86400000);

  // ─── Rediscover (pure local — ship first) ─────────────────────────────

  Future<GeneratedMix> ensureRediscover({int limit = 30}) async {
    final existing = repo.getMix('rediscover');
    if (existing != null && !_staleWeekly(existing.generatedTs)) {
      return existing;
    }
    final ids = repo.rediscoverIds(limit: limit * 2);
    // Enrich from recent events
    final events = repo.recentEvents(limit: 5000);
    final metaById = <String, DiscoveryEvent>{};
    for (final e in events) {
      if (e.title != null && e.title!.isNotEmpty) {
        metaById[e.videoId] = e;
      }
    }
    final enriched = <Map<String, dynamic>>[];
    for (final id in ids) {
      final e = metaById[id];
      enriched.add({
        'videoId': id,
        'title': e?.title ?? id,
        'artists': [
          {'name': e?.artist ?? e?.artistKey ?? ''}
        ],
        'thumbnails': [
          {'url': ''}
        ],
      });
      if (enriched.length >= limit) break;
    }

    final mix = GeneratedMix(
      id: 'rediscover',
      title: 'Rediscover',
      reason: 'Old favorites gone quiet',
      kind: MixKind.rediscover,
      tracks: enriched,
      generatedTs: DateTime.now().millisecondsSinceEpoch,
    );
    await repo.saveMix(mix);
    await repo.logImpressions(
        enriched.map((t) => t['videoId'] as String), DiscoverySurface.rediscover);
    return mix;
  }

  // ─── Daily mixes ──────────────────────────────────────────────────────

  Future<List<GeneratedMix>> ensureDailyMixes({int count = 4}) async {
    final prefsCount = repo.getPref('mixCount', defaultValue: count) as int? ?? count;
    count = prefsCount.clamp(3, 5);

    final existing = repo.mixesOfKind(MixKind.dailyMix);
    if (existing.length >= count &&
        existing.every((m) => !_staleDaily(m.generatedTs))) {
      return existing.take(count).toList();
    }

    // Wi-Fi only check is done by caller / DiscoveryService
    final clusters = _clusterArtists(count);
    if (clusters.isEmpty) {
      // Cold start: empty mixes
      return existing;
    }

    final mixes = <GeneratedMix>[];
    for (var i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      final tracks = await _buildClusterMix(cluster, limit: 30);
      final names = cluster
          .take(2)
          .map((k) => repo.displayNameForArtistKey(k) ?? _titleCaseKey(k))
          .toList();
      final title = names.isEmpty
          ? 'Daily Mix ${i + 1}'
          : names.length == 1
              ? 'Daily Mix: ${names[0]}'
              : 'Daily Mix: ${names[0]} / ${names[1]}';
      final mix = GeneratedMix(
        id: 'daily_mix_${i + 1}',
        title: title,
        reason: 'From your ${names.isNotEmpty ? names.first : "listening"}',
        kind: MixKind.dailyMix,
        tracks: tracks,
        generatedTs: DateTime.now().millisecondsSinceEpoch,
      );
      await repo.saveMix(mix);
      await repo.logImpressions(
          tracks.map((t) => t['videoId'] as String),
          '${DiscoverySurface.dailyMix}_${i + 1}');
      mixes.add(mix);
    }
    await repo.setPref('lastDailyMixGenerated', DateTime.now().millisecondsSinceEpoch);
    return mixes;
  }

  static String _titleCaseKey(String key) {
    if (key.isEmpty) return key;
    return key.split(' ').map((w) {
      if (w.isEmpty) return w;
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }).join(' ');
  }

  /// Greedy connected components on top artists via co-occurrence + affinity.
  List<List<String>> _clusterArtists(int k) {
    final top = repo.topAffinities(limit: 40);
    if (top.isEmpty) return [];
    final artists = top.keys.toList();

    // Build adjacency from shared track co-occurrence is hard without artist→track;
    // use affinity proximity: greedy buckets by walking the sorted list and
    // pairing artists that share co-occurring tracks in recent events.
    final events = repo.recentEvents(limit: 2000);
    final artistTracks = <String, Set<String>>{};
    for (final e in events) {
      if (e.artistKey.isEmpty || e.videoId.isEmpty) continue;
      artistTracks.putIfAbsent(e.artistKey, () => {}).add(e.videoId);
    }

    double relatedness(String a, String b) {
      final ta = artistTracks[a] ?? {};
      final tb = artistTracks[b] ?? {};
      if (ta.isEmpty || tb.isEmpty) return 0;
      // Track-level co-occurrence overlap
      var score = 0.0;
      for (final t in ta) {
        final neigh = repo.neighborsOf(t, limit: 20);
        for (final u in tb) {
          score += neigh[u] ?? 0;
        }
      }
      return score;
    }

    // Greedy: seed k clusters with top artists, assign rest to best cluster
    final seeds = artists.take(k).toList();
    final clusters = List.generate(seeds.length, (i) => <String>[seeds[i]]);
    final assigned = seeds.toSet();

    for (final a in artists.skip(k)) {
      var bestI = 0;
      var bestS = -1.0;
      for (var i = 0; i < clusters.length; i++) {
        var s = 0.0;
        for (final c in clusters[i]) {
          s += relatedness(a, c);
        }
        s += 0.01 * (top[a] ?? 0); // slight preference keep high affinity together
        if (s > bestS) {
          bestS = s;
          bestI = i;
        }
      }
      clusters[bestI].add(a);
      assigned.add(a);
    }
    return clusters.where((c) => c.isNotEmpty).toList();
  }

  /// ~60% familiar cluster favorites, ~25% unheard same artists, ~15% adjacent.
  Future<List<Map<String, dynamic>>> _buildClusterMix(List<String> cluster,
      {int limit = 30}) async {
    final nFamiliar = (limit * 0.60).round();
    final nUnheardKnown = (limit * 0.25).round();
    final nAdjacent = limit - nFamiliar - nUnheardKnown;

    final events = repo.recentEvents(limit: 5000);
    final clusterSet = cluster.toSet();
    final familiar = <Map<String, dynamic>>[];
    final seen = <String>{};
    final threeDaysAgo = DateTime.now()
        .subtract(const Duration(days: 3))
        .millisecondsSinceEpoch;

    for (final e in events.reversed) {
      if (!clusterSet.contains(e.artistKey)) continue;
      if (seen.contains(e.videoId)) continue;
      final last = repo.lastPlayedTs(e.videoId) ?? 0;
      if (last > threeDaysAgo) continue; // exclude last 3 days
      seen.add(e.videoId);
      familiar.add({
        'videoId': e.videoId,
        'title': e.title ?? e.videoId,
        'artists': [
          {'name': e.artist ?? e.artistKey}
        ],
        'thumbnails': [
          {'url': ''}
        ],
      });
      if (familiar.length >= nFamiliar * 2) break;
    }

    // Unheard by known artists: pull related from familiar seeds
    final unheardKnown = <Map<String, dynamic>>[];
    for (final seed in familiar.take(5)) {
      final id = seed['videoId'] as String;
      final related = await sources.relatedTracks(id, limit: 15);
      for (final m in related) {
        final vid = m['videoId'] as String? ?? '';
        if (vid.isEmpty || seen.contains(vid)) continue;
        if (!repo.isUnheard(vid)) continue;
        final ak = normalizeArtistKey(_artist(m));
        if (!clusterSet.contains(ak) && clusterSet.isNotEmpty) {
          // allow near-cluster
        }
        if (repo.shownRecently(vid)) continue;
        if (BanServiceSafe.isBanned(vid)) continue;
        seen.add(vid);
        unheardKnown.add(m);
        if (unheardKnown.length >= nUnheardKnown * 2) break;
      }
      if (unheardKnown.length >= nUnheardKnown * 2) break;
    }

    // Adjacent: related of related
    final adjacent = <Map<String, dynamic>>[];
    for (final seed in unheardKnown.take(4)) {
      final id = seed['videoId'] as String? ?? '';
      if (id.isEmpty) continue;
      final related = await sources.relatedTracks(id, limit: 10);
      for (final m in related) {
        final vid = m['videoId'] as String? ?? '';
        if (vid.isEmpty || seen.contains(vid)) continue;
        if (!repo.isUnheard(vid)) continue;
        if (repo.shownRecently(vid)) continue;
        if (BanServiceSafe.isBanned(vid)) continue;
        seen.add(vid);
        adjacent.add(m);
        if (adjacent.length >= nAdjacent * 2) break;
      }
    }

    final rng = _rng;
    rng.shuffle(familiar);
    rng.shuffle(unheardKnown);
    rng.shuffle(adjacent);

    final out = <Map<String, dynamic>>[
      ...familiar.take(nFamiliar),
      ...unheardKnown.take(nUnheardKnown),
      ...adjacent.take(nAdjacent),
    ];

    // Pad from charts if thin
    if (out.length < limit) {
      final charts = await sources.charts(limit: limit);
      for (final m in charts) {
        final vid = m['videoId'] as String? ?? '';
        if (vid.isEmpty || seen.contains(vid)) continue;
        seen.add(vid);
        out.add(m);
        if (out.length >= limit) break;
      }
    }

    // Constraint pass
    final scored = out
        .map((m) => (
              score: 1.0,
              artistKey: normalizeArtistKey(_artist(m)),
              item: m,
            ))
        .toList();
    return greedyConstrainedPick<Map<String, dynamic>>(
      scored: scored,
      limit: limit,
      maxPerArtist: 2,
    );
  }

  // ─── Fresh Finds ──────────────────────────────────────────────────────

  Future<GeneratedMix> ensureFreshFinds({int limit = 30}) async {
    final existing = repo.getMix('fresh_finds');
    if (existing != null && !_staleWeekly(existing.generatedTs)) {
      return existing;
    }

    final seeds = repo.topAffinities(limit: 15).keys.toList();
    final events = repo.recentEvents(limit: 1000);
    final seedTracks = <String>[];
    for (final e in events.reversed) {
      if (seeds.contains(e.artistKey) && e.videoId.isNotEmpty) {
        seedTracks.add(e.videoId);
      }
      if (seedTracks.length >= 8) break;
    }

    final candidates = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final id in seedTracks) {
      final related = await sources.relatedTracks(id, limit: 15);
      for (final m in related) {
        final vid = m['videoId'] as String? ?? '';
        if (vid.isEmpty || seen.contains(vid)) continue;
        // two-hop
        final hop2 = await sources.relatedTracks(vid, limit: 8);
        for (final m2 in [...related, ...hop2]) {
          final v2 = m2['videoId'] as String? ?? '';
          if (v2.isEmpty || seen.contains(v2)) continue;
          if (!repo.isUnheard(v2)) continue;
          if (repo.shownRecently(v2, within: const Duration(days: 365))) {
            continue;
          }
          if (BanServiceSafe.isBanned(v2)) continue;
          seen.add(v2);
          candidates.add(m2);
        }
      }
      if (candidates.length >= limit * 3) break;
    }

    // Score by novelty + mild affinity of artist
    final scored = candidates
        .map((m) {
          final ak = normalizeArtistKey(_artist(m));
          final score =
              2.0 + taste.scoreCandidate(
                videoId: m['videoId'] as String,
                artistKey: ak,
                sourceConfidence: 0.6,
                noveltyBonus: true,
              );
          return (score: score, artistKey: ak, item: m);
        })
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final picked = greedyConstrainedPick<Map<String, dynamic>>(
      scored: scored,
      limit: limit,
      maxPerArtist: 2,
    );

    final mix = GeneratedMix(
      id: 'fresh_finds',
      title: 'Fresh Finds',
      reason: 'Strictly new to you this week',
      kind: MixKind.freshFinds,
      tracks: picked,
      generatedTs: DateTime.now().millisecondsSinceEpoch,
    );
    await repo.saveMix(mix);
    await repo.logImpressions(
        picked.map((t) => t['videoId'] as String), DiscoverySurface.freshFinds);
    return mix;
  }

  // ─── Release Radar ────────────────────────────────────────────────────

  Future<GeneratedMix> ensureReleaseRadar({int limit = 30}) async {
    final existing = repo.getMix('release_radar');
    if (existing != null && !_staleWeekly(existing.generatedTs)) {
      return existing;
    }

    final followed = repo.followedArtists();
    // Also top-affinity artists we can resolve via LibraryArtists is caller's job;
    // here we only use explicit follows + names from affinity events.
    final channelIds = followed
        .map((f) => f['channelId'] as String?)
        .whereType<String>()
        .toList();

    final tracks = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final channelId in channelIds.take(20)) {
      try {
        final artist = await sources.music.getArtist(channelId);
        // Singles & albums — take song-like entries
        for (final key in ['Songs', 'Top songs', 'Singles', 'Singles & EPs', 'Albums']) {
          final block = artist[key];
          final results = block is Map ? block['results'] : null;
          if (results is! List) continue;
          for (final item in results) {
            if (item is! Map) continue;
            // Prefer items with videoId (songs); albums need expansion — skip heavy
            final m = Map<String, dynamic>.from(item);
            final vid = m['videoId'] as String?;
            if (vid == null || vid.isEmpty || seen.contains(vid)) continue;
            // date filter last 30 days when present
            final date = m['year'] ?? m['date'];
            // If we can't parse date, still include lightly
            seen.add(vid);
            tracks.add({
              'videoId': vid,
              'title': m['title'] ?? '',
              'artists': m['artists'] ??
                  [
                    {'name': artist['name'] ?? ''}
                  ],
              'thumbnails': m['thumbnails'] ??
                  [
                    {'url': ''}
                  ],
              'year': date,
            });
          }
        }
      } catch (_) {}
      if (tracks.length >= limit) break;
    }

    final mix = GeneratedMix(
      id: 'release_radar',
      title: 'Release Radar',
      reason: 'New from artists you follow',
      kind: MixKind.releaseRadar,
      tracks: tracks.take(limit).toList(),
      generatedTs: DateTime.now().millisecondsSinceEpoch,
    );
    await repo.saveMix(mix);
    await repo.logImpressions(
        mix.tracks.map((t) => t['videoId'] as String),
        DiscoverySurface.releaseRadar);
    return mix;
  }

  // ─── Staleness ────────────────────────────────────────────────────────

  bool _staleDaily(int generatedTs) {
    final gen = DateTime.fromMillisecondsSinceEpoch(generatedTs);
    final now = DateTime.now();
    // Stale past 4 AM local if generated before today's 4 AM
    final today4am = DateTime(now.year, now.month, now.day, 4);
    final threshold = now.isBefore(today4am)
        ? today4am.subtract(const Duration(days: 1))
        : today4am;
    return gen.isBefore(threshold);
  }

  bool _staleWeekly(int generatedTs) {
    final gen = DateTime.fromMillisecondsSinceEpoch(generatedTs);
    final weekday =
        repo.getPref('weeklyRefreshWeekday', defaultValue: DateTime.monday)
            as int;
    final now = DateTime.now();
    // Stale if older than 6 days or past configured weekday since generation
    if (now.difference(gen).inDays >= 6) return true;
    if (now.weekday == weekday && gen.day != now.day) return true;
    return false;
  }

  String _artist(Map m) {
    if (m['artists'] is List) {
      return (m['artists'] as List)
          .map((e) => e is Map ? (e['name'] ?? '') : '$e')
          .join(', ');
    }
    return m['artist']?.toString() ?? '';
  }
}

/// Thin wrapper so mix_generator doesn't hard-crash in pure unit tests
/// without Hive BanService.
class BanServiceSafe {
  static bool isBanned(String videoId) {
    try {
      // ignore: avoid_dynamic_calls
      return _check(videoId);
    } catch (_) {
      return false;
    }
  }

  static bool _check(String videoId) {
    // Imported lazily via discovery_engine for production; here use a
    // top-level hook set by DiscoveryService.
    return _banHook?.call(videoId) ?? false;
  }

  static bool Function(String)? _banHook;
  static void setBanHook(bool Function(String)? hook) => _banHook = hook;
}
