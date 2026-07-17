import 'package:audio_service/audio_service.dart';

import '../../models/media_Item_builder.dart';
import 'candidate_sources.dart';
import 'discovery_math.dart';
import 'discovery_repository.dart';
import 'discovery_types.dart';
import 'mix_generator.dart';
import 'taste_model.dart';

/// Shared recommendation pipeline: candidates → score → constraints → impressions.
class DiscoveryEngine {
  DiscoveryEngine({
    required this.repo,
    required this.taste,
    required this.sources,
    MixGenerator? mixGenerator,
    this.exploration = 0.5,
  }) : mixGenerator = mixGenerator ??
            MixGenerator(repo: repo, taste: taste, sources: sources);

  final DiscoveryRepository repo;
  final TasteModel taste;
  final CandidateSources sources;
  final MixGenerator mixGenerator;

  /// 0.0 = familiar, 1.0 = adventurous.
  double exploration;

  // ─── Public API ───────────────────────────────────────────────────────

  Future<List<MediaItem>> similarSongs(MediaItem seed,
      {int limit = 25, bool unheardOnly = false}) async {
    final candidates = await _gatherForSeed(seed, widen: exploration > 0.6);
    final scored = _scoreAll(
      candidates,
      seedVideoId: seed.id,
      noveltyBonus: unheardOnly || exploration > 0.45,
      sourceConfidence: 1.0,
    );
    var picked = _constrain(scored, limit: limit, radioMode: false);
    if (unheardOnly) {
      picked = picked.where((c) => repo.isUnheard(c.videoId)).toList();
    }
    await repo.logImpressions(picked.map((c) => c.videoId), DiscoverySurface.similar);
    return _toMedia(picked, DiscoverySource.similar);
  }

  Future<List<MediaItem>> smartRadioBatch(
    MediaItem seed, {
    required double exploration,
    required List<MediaItem> sessionHistory,
    int limit = 24,
  }) async {
    this.exploration = exploration;
    final candidates =
        await _gatherForSeed(seed, widen: exploration > 0.55, radio: true);
    final sessionIds = sessionHistory.map((e) => e.id).toSet();
    final scored = _scoreAll(
      candidates,
      seedVideoId: seed.id,
      noveltyBonus: exploration > 0.4,
      sourceConfidence: 0.9,
      excludeIds: sessionIds,
    );
    // Drop played in last 7 days
    scored.removeWhere((c) {
      final ts = repo.lastPlayedTs(c.videoId);
      if (ts == null) return false;
      return DateTime.now().millisecondsSinceEpoch - ts <
          const Duration(days: 7).inMilliseconds;
    });
    final picked = _constrain(scored, limit: limit, radioMode: true);
    await repo.logImpressions(picked.map((c) => c.videoId), DiscoverySurface.radio);
    return _toMedia(picked, DiscoverySource.radio);
  }

  Future<List<GeneratedMix>> dailyMixes() async {
    return mixGenerator.ensureDailyMixes();
  }

  Future<List<MediaItem>> freshFinds({int limit = 30}) async {
    final mix = await mixGenerator.ensureFreshFinds(limit: limit);
    return _mixToMedia(mix, DiscoverySource.discover);
  }

  Future<List<MediaItem>> releaseRadar({int limit = 30}) async {
    final mix = await mixGenerator.ensureReleaseRadar(limit: limit);
    return _mixToMedia(mix, DiscoverySource.discover);
  }

  Future<List<MediaItem>> rediscover({int limit = 30}) async {
    final mix = await mixGenerator.ensureRediscover(limit: limit);
    return _mixToMedia(mix, DiscoverySource.discover);
  }

  Future<List<DiscoverySection>> homeSections() async {
    if (!taste.hasEnoughSignal) return [];

    final sections = <DiscoverySection>[];
    final mixes = await dailyMixes();
    if (mixes.isNotEmpty) {
      sections.add(DiscoverySection(
        id: 'made_for_you',
        title: 'Made for you',
        reason: 'Daily mixes from your listening',
        tracks: mixes.expand((m) => m.tracks.take(1)).toList(),
        surface: DiscoverySurface.home,
      ));
    }

    // Because you liked ⟨seed⟩ — 2–3 sections
    final seeds = _recentStrongSeeds(limit: 3);
    for (final seed in seeds) {
      final title = seed['title'] as String? ?? 'a track';
      final media = MediaItemBuilder.fromJson(seed);
      final similar = await similarSongs(media, limit: 12, unheardOnly: true);
      if (similar.isEmpty) continue;
      sections.add(DiscoverySection(
        id: 'because_${media.id}',
        title: 'Because you liked $title',
        reason: 'Mostly unheard, similar energy',
        tracks: similar.map(MediaItemBuilder.toJson).toList(),
        surface: DiscoverySurface.becauseYouLiked,
      ));
    }

    final red = await rediscover(limit: 15);
    if (red.isNotEmpty) {
      sections.add(DiscoverySection(
        id: 'rediscover',
        title: 'Rediscover',
        reason: 'Old favorites gone quiet',
        tracks: red.map(MediaItemBuilder.toJson).toList(),
        surface: DiscoverySurface.rediscover,
      ));
    }

    final fresh = await freshFinds(limit: 15);
    if (fresh.isNotEmpty) {
      sections.add(DiscoverySection(
        id: 'fresh_finds',
        title: 'Fresh Finds',
        reason: 'Strictly new to you',
        tracks: fresh.map(MediaItemBuilder.toJson).toList(),
        surface: DiscoverySurface.freshFinds,
      ));
    }

    final radar = await releaseRadar(limit: 15);
    if (radar.isNotEmpty) {
      sections.add(DiscoverySection(
        id: 'release_radar',
        title: 'Release Radar',
        reason: 'New from artists you follow',
        tracks: radar.map(MediaItemBuilder.toJson).toList(),
        surface: DiscoverySurface.releaseRadar,
      ));
    }

    // Fans of ⟨top artist⟩ also like
    final top = repo.topAffinities(limit: 1);
    if (top.isNotEmpty) {
      final artistName = top.keys.first;
      // Expand via charts + related of a top track
      if (seeds.isNotEmpty) {
        final media = MediaItemBuilder.fromJson(seeds.first);
        final similar =
            await similarSongs(media, limit: 12, unheardOnly: true);
        if (similar.isNotEmpty) {
          sections.add(DiscoverySection(
            id: 'fans_$artistName',
            title: 'Fans of $artistName also like',
            reason: 'Unheard picks near your top artist',
            tracks: similar.map(MediaItemBuilder.toJson).toList(),
            surface: DiscoverySurface.fansAlsoLike,
          ));
        }
      }
    }

    return sections;
  }

  /// Suggest tracks matching a playlist's aggregate profile.
  Future<List<MediaItem>> suggestForPlaylist(List<MediaItem> members,
      {int limit = 10}) async {
    if (members.isEmpty) return [];
    final artistScores = <String, double>{};
    for (final m in members) {
      final k = normalizeArtistKey(m.artist);
      artistScores[k] = (artistScores[k] ?? 0) + 1;
    }
    final candidates = <Map<String, dynamic>>[];
    final seed = members.first;
    candidates.addAll(await sources.relatedTracks(seed.id, limit: 30));
    for (final m in members.take(5)) {
      for (final n in sources.localNeighborIds(m.id, limit: 8)) {
        final ts = repo.lastPlayedTs(n);
        // neighbor ids only — try pull from related of seed
        if (ts != null) {
          // already known locally; skip adding bare id
        }
      }
      candidates.addAll(await sources.relatedTracks(m.id, limit: 10));
    }
    final memberIds = members.map((e) => e.id).toSet();
    final scored = _scoreAll(
      candidates,
      seedVideoId: seed.id,
      noveltyBonus: true,
      sourceConfidence: 0.8,
      excludeIds: memberIds,
    );
    final picked = _constrain(scored, limit: limit, radioMode: false);
    await repo.logImpressions(
        picked.map((c) => c.videoId), DiscoverySurface.playlistSuggest);
    return _toMedia(picked, DiscoverySource.discover);
  }

  // ─── Pipeline internals ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _gatherForSeed(MediaItem seed,
      {bool widen = false, bool radio = false}) async {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addAll(List<Map<String, dynamic>> list) {
      for (final m in list) {
        final id = m['videoId'] as String?;
        if (id == null || id == seed.id || seen.contains(id)) continue;
        seen.add(id);
        out.add(m);
      }
    }

    if (radio) {
      addAll(await sources.radioBatch(seed.id, limit: 30));
    }
    addAll(await sources.relatedTracks(seed.id, limit: 40));

    // Local graph
    for (final nid in sources.localNeighborIds(seed.id, limit: 25)) {
      if (seen.contains(nid)) continue;
      // Expand via related of neighbor when adventurous
      if (widen) {
        addAll(await sources.relatedTracks(nid, limit: 8));
      }
    }

    if (widen) {
      // Two-hop: related of first few related
      for (final m in List<Map<String, dynamic>>.from(out).take(4)) {
        final id = m['videoId'] as String?;
        if (id != null) addAll(await sources.relatedTracks(id, limit: 8));
      }
    }

    if (out.length < 10) {
      addAll(await sources.charts(limit: 20));
    }
    return out;
  }

  List<ScoredCandidate> _scoreAll(
    List<Map<String, dynamic>> candidates, {
    required String seedVideoId,
    required bool noveltyBonus,
    required double sourceConfidence,
    Set<String>? excludeIds,
  }) {
    final neighbors = repo.neighborsOf(seedVideoId);
    final scored = <ScoredCandidate>[];
    final dedupe = <String>{};

    for (final m in candidates) {
      final videoId = m['videoId'] as String? ?? '';
      if (videoId.isEmpty || videoId == seedVideoId) continue;
      if (excludeIds != null && excludeIds.contains(videoId)) continue;
      if (BanServiceSafe.isBanned(videoId)) continue;

      final title = m['title'] as String? ?? '';
      final artist = _artistOf(m);
      final dkey = trackDedupeKey(title, artist);
      if (dedupe.contains(dkey)) continue;
      dedupe.add(dkey);

      final artistKey = normalizeArtistKey(artist);
      final co = neighbors[videoId] ?? 0;
      final score = taste.scoreCandidate(
        videoId: videoId,
        artistKey: artistKey,
        sourceConfidence: sourceConfidence,
        cooccurrenceStrength: co,
        noveltyBonus: noveltyBonus,
        isBanned: false,
      );
      if (score.isInfinite && score.isNegative) continue;

      scored.add(ScoredCandidate(
        videoId: videoId,
        title: title,
        artist: artist,
        artistKey: artistKey,
        score: score,
        mediaJson: m,
        reason: co > 0
            ? 'Often played together'
            : (repo.isUnheard(videoId) ? 'New to you' : 'Similar taste'),
      ));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  List<ScoredCandidate> _constrain(List<ScoredCandidate> scored,
      {required int limit, required bool radioMode}) {
    final entries = scored
        .map((c) => (score: c.score, artistKey: c.artistKey, item: c))
        .toList();
    return greedyConstrainedPick<ScoredCandidate>(
      scored: entries,
      limit: limit,
      maxPerArtist: 2,
      rollingWindow: radioMode ? 10 : null,
      maxInRollingWindow: 2,
    );
  }

  List<MediaItem> _toMedia(
      List<ScoredCandidate> picked, DiscoverySource source) {
    return picked.map((c) {
      final item = MediaItemBuilder.fromJson(c.mediaJson);
      final extras = Map<String, dynamic>.from(item.extras ?? {});
      extras['discoverySource'] = source.wireName;
      extras['discoveryReason'] = c.reason;
      return item.copyWith(extras: extras);
    }).toList();
  }

  List<MediaItem> _mixToMedia(GeneratedMix? mix, DiscoverySource source) {
    if (mix == null) return [];
    return mix.tracks.map((m) {
      final item = MediaItemBuilder.fromJson(m);
      final extras = Map<String, dynamic>.from(item.extras ?? {});
      extras['discoverySource'] = source.wireName;
      return item.copyWith(extras: extras);
    }).toList();
  }

  String _artistOf(Map m) {
    if (m['artists'] is List) {
      return (m['artists'] as List)
          .map((e) => e is Map ? (e['name'] ?? '') : '$e')
          .join(', ');
    }
    return m['artist']?.toString() ?? '';
  }

  List<Map<String, dynamic>> _recentStrongSeeds({int limit = 3}) {
    final events = repo.recentEvents(limit: 200);
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final e in events.reversed) {
      if (e.event != DiscoveryEventKind.playEnded &&
          e.event != DiscoveryEventKind.favorite) {
        continue;
      }
      if (e.fraction != null && e.fraction! < 0.85) continue;
      if (seen.contains(e.videoId)) continue;
      seen.add(e.videoId);
      out.add({
        'videoId': e.videoId,
        'title': e.title ?? e.videoId,
        'artists': [
          {'name': e.artist ?? e.artistKey}
        ],
        'thumbnails': [
          {'url': ''}
        ],
      });
      if (out.length >= limit) break;
    }
    return out;
  }
}
