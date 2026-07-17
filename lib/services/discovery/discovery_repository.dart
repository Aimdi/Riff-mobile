import 'package:hive/hive.dart';

import 'discovery_math.dart';
import 'discovery_types.dart';

/// Hive box names for discovery. All access goes through [DiscoveryRepository].
class DiscoveryBoxes {
  static const events = 'riff_events';
  static const artistAffinity = 'riff_artist_affinity';
  static const trackStats = 'riff_track_stats';
  static const cooccurrence = 'riff_cooccurrence';
  static const impressions = 'riff_impressions';
  static const apiCache = 'riff_api_cache';
  static const mixes = 'riff_mixes';
  static const follows = 'riff_follows'; // artist channelId → meta
  static const prefs = 'riff_discovery_prefs';

  static const all = [
    events,
    artistAffinity,
    trackStats,
    cooccurrence,
    impressions,
    apiCache,
    mixes,
    follows,
    prefs,
  ];
}

/// Repository wrapper — no raw Hive calls from controllers.
class DiscoveryRepository {
  DiscoveryRepository();

  bool _opened = false;

  Future<void> open() async {
    if (_opened) return;
    for (final name in DiscoveryBoxes.all) {
      await Hive.openBox(name);
    }
    _opened = true;
  }

  Box get _events => Hive.box(DiscoveryBoxes.events);
  Box get _affinity => Hive.box(DiscoveryBoxes.artistAffinity);
  Box get _trackStats => Hive.box(DiscoveryBoxes.trackStats);
  Box get _cooc => Hive.box(DiscoveryBoxes.cooccurrence);
  Box get _impressions => Hive.box(DiscoveryBoxes.impressions);
  Box get _apiCache => Hive.box(DiscoveryBoxes.apiCache);
  Box get _mixes => Hive.box(DiscoveryBoxes.mixes);
  Box get _follows => Hive.box(DiscoveryBoxes.follows);
  Box get _prefs => Hive.box(DiscoveryBoxes.prefs);

  // ─── Events ───────────────────────────────────────────────────────────

  static const int maxEvents = 20000;
  static const Duration maxEventAge = Duration(days: 365 * 2);

  Future<void> appendEvent(DiscoveryEvent e) async {
    await _events.add(e.toJson());
  }

  List<DiscoveryEvent> recentEvents({int limit = 500}) {
    final values = _events.values.toList();
    final start = values.length > limit ? values.length - limit : 0;
    return values
        .sublist(start)
        .map((e) => DiscoveryEvent.fromJson(Map.from(e as Map)))
        .toList();
  }

  Future<void> pruneEvents() async {
    final cutoff =
        DateTime.now().subtract(maxEventAge).millisecondsSinceEpoch;
    final keys = _events.keys.toList();
    final toDelete = <dynamic>[];
    for (final k in keys) {
      final v = _events.get(k);
      if (v is Map && ((v['ts'] as int?) ?? 0) < cutoff) {
        toDelete.add(k);
      }
    }
    // Also cap total count (drop oldest)
    final remaining = keys.length - toDelete.length;
    if (remaining > maxEvents) {
      final keepDrop = remaining - maxEvents;
      var dropped = 0;
      for (final k in keys) {
        if (toDelete.contains(k)) continue;
        toDelete.add(k);
        dropped++;
        if (dropped >= keepDrop) break;
      }
    }
    for (final k in toDelete) {
      await _events.delete(k);
    }
  }

  // ─── Artist affinity ──────────────────────────────────────────────────

  /// Apply [delta] to artist affinity, decaying existing score first.
  Future<void> bumpAffinity(String artistKey, double delta,
      {DateTime? now}) async {
    if (artistKey.isEmpty) return;
    final n = now ?? DateTime.now();
    final prev = _affinity.get(artistKey);
    double score = 0;
    int lastTs = n.millisecondsSinceEpoch;
    if (prev is Map) {
      score = (prev['score'] as num?)?.toDouble() ?? 0;
      lastTs = prev['lastUpdatedTs'] as int? ?? lastTs;
      final elapsed =
          Duration(milliseconds: n.millisecondsSinceEpoch - lastTs);
      score = decayed(score, elapsed, affinityHalfLife);
    }
    score += delta;
    await _affinity.put(artistKey, {
      'score': score,
      'lastUpdatedTs': n.millisecondsSinceEpoch,
      'skips': (prev is Map ? (prev['skips'] as int? ?? 0) : 0) +
          (delta < 0 ? 1 : 0),
      'listens': (prev is Map ? (prev['listens'] as int? ?? 0) : 0) +
          (delta > 0 ? 1 : 0),
    });
  }

  /// Affinity at [now] with lazy decay.
  double affinityOf(String artistKey, {DateTime? now}) {
    if (artistKey.isEmpty) return 0;
    final prev = _affinity.get(artistKey);
    if (prev is! Map) return 0;
    final score = (prev['score'] as num?)?.toDouble() ?? 0;
    final lastTs = prev['lastUpdatedTs'] as int? ?? 0;
    final n = now ?? DateTime.now();
    final elapsed =
        Duration(milliseconds: n.millisecondsSinceEpoch - lastTs);
    return decayed(score, elapsed, affinityHalfLife);
  }

  /// Skip rate estimate: skips / (listens + skips), or 0 if no data.
  double skipRateOf(String artistKey) {
    final prev = _affinity.get(artistKey);
    if (prev is! Map) return 0;
    final skips = prev['skips'] as int? ?? 0;
    final listens = prev['listens'] as int? ?? 0;
    final total = skips + listens;
    if (total == 0) return 0;
    return skips / total;
  }

  Map<String, double> topAffinities({int limit = 40, DateTime? now}) {
    final n = now ?? DateTime.now();
    final entries = <String, double>{};
    for (final k in _affinity.keys) {
      final key = k.toString();
      final s = affinityOf(key, now: n);
      if (s > 0) entries[key] = s;
    }
    final sorted = entries.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(limit));
  }

  Map<String, dynamic> affinityDebugSnapshot({int limit = 30}) {
    final top = topAffinities(limit: limit);
    return {
      'artists': top.entries
          .map((e) => {
                'key': e.key,
                'score': double.parse(e.value.toStringAsFixed(3)),
                'skipRate':
                    double.parse(skipRateOf(e.key).toStringAsFixed(3)),
              })
          .toList(),
      'eventCount': _events.length,
      'trackStatsCount': _trackStats.length,
      'coocEdges': _cooc.length,
      'impressions': _impressions.length,
    };
  }

  // ─── Track familiarity ────────────────────────────────────────────────

  Future<void> recordTrackPlay(String videoId,
      {DateTime? now, double weight = 1.0}) async {
    final n = now ?? DateTime.now();
    final prev = _trackStats.get(videoId);
    double decayedPlays = 0;
    int lifetime = 0;
    int lastTs = n.millisecondsSinceEpoch;
    if (prev is Map) {
      decayedPlays = (prev['decayedPlays'] as num?)?.toDouble() ?? 0;
      lifetime = prev['lifetimePlays'] as int? ?? 0;
      lastTs = prev['lastPlayedTs'] as int? ?? lastTs;
      final elapsed =
          Duration(milliseconds: n.millisecondsSinceEpoch - lastTs);
      decayedPlays = decayed(decayedPlays, elapsed, familiarityHalfLife);
    }
    decayedPlays += weight;
    lifetime += 1;
    await _trackStats.put(videoId, {
      'decayedPlays': decayedPlays,
      'lastPlayedTs': n.millisecondsSinceEpoch,
      'lifetimePlays': lifetime,
    });
  }

  double familiarityOf(String videoId, {DateTime? now}) {
    final prev = _trackStats.get(videoId);
    if (prev is! Map) return 0;
    final decayedPlays = (prev['decayedPlays'] as num?)?.toDouble() ?? 0;
    final lastTs = prev['lastPlayedTs'] as int? ?? 0;
    final n = now ?? DateTime.now();
    final elapsed =
        Duration(milliseconds: n.millisecondsSinceEpoch - lastTs);
    return decayed(decayedPlays, elapsed, familiarityHalfLife);
  }

  int? lastPlayedTs(String videoId) {
    final prev = _trackStats.get(videoId);
    if (prev is! Map) return null;
    return prev['lastPlayedTs'] as int?;
  }

  int lifetimePlays(String videoId) {
    final prev = _trackStats.get(videoId);
    if (prev is! Map) return 0;
    return prev['lifetimePlays'] as int? ?? 0;
  }

  bool isUnheard(String videoId) => !_trackStats.containsKey(videoId);

  /// Tracks with high lifetime familiarity but quiet for > [quietDays].
  List<String> rediscoverIds(
      {int quietDays = 90, double minLifetimePlays = 2.0, int limit = 40}) {
    final cutoff = DateTime.now()
        .subtract(Duration(days: quietDays))
        .millisecondsSinceEpoch;
    final candidates = <({String id, double score})>[];
    for (final k in _trackStats.keys) {
      final v = _trackStats.get(k);
      if (v is! Map) continue;
      final last = v['lastPlayedTs'] as int? ?? 0;
      final life = (v['lifetimePlays'] as int? ?? 0).toDouble();
      if (last > 0 && last < cutoff && life >= minLifetimePlays) {
        candidates.add((id: k.toString(), score: life));
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(limit).map((e) => e.id).toList();
  }

  // ─── Co-occurrence graph ──────────────────────────────────────────────

  static const int maxNeighbors = 150;

  String _edgeKey(String a, String b) {
    if (a.compareTo(b) <= 0) return '$a|$b';
    return '$b|$a';
  }

  Future<void> bumpCooccurrence(String a, String b, {double weight = 1.0}) async {
    if (a.isEmpty || b.isEmpty || a == b) return;
    final key = _edgeKey(a, b);
    final prev = (_cooc.get(key) as num?)?.toDouble() ?? 0;
    await _cooc.put(key, prev + weight);
    await _capNeighbors(a);
    await _capNeighbors(b);
  }

  Future<void> _capNeighbors(String id) async {
    final neighbors = neighborsOf(id);
    if (neighbors.length <= maxNeighbors) return;
    final sorted = neighbors.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final drop = sorted.take(neighbors.length - maxNeighbors);
    for (final e in drop) {
      await _cooc.delete(_edgeKey(id, e.key));
    }
  }

  Map<String, double> neighborsOf(String id, {int limit = 50}) {
    final out = <String, double>{};
    final prefix = '$id|';
    final suffix = '|$id';
    for (final k in _cooc.keys) {
      final key = k.toString();
      if (key.startsWith(prefix)) {
        out[key.substring(prefix.length)] =
            (_cooc.get(k) as num?)?.toDouble() ?? 0;
      } else if (key.endsWith(suffix)) {
        out[key.substring(0, key.length - suffix.length)] =
            (_cooc.get(k) as num?)?.toDouble() ?? 0;
      }
    }
    final sorted = out.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(limit));
  }

  // ─── Impressions ──────────────────────────────────────────────────────

  Future<void> logImpression(String videoId, String surface,
      {DateTime? now}) async {
    final n = now ?? DateTime.now();
    await _impressions.put('$videoId|$surface', n.millisecondsSinceEpoch);
    // Also a global last-shown for any surface
    await _impressions.put('$videoId|*', n.millisecondsSinceEpoch);
  }

  Future<void> logImpressions(Iterable<String> videoIds, String surface,
      {DateTime? now}) async {
    for (final id in videoIds) {
      await logImpression(id, surface, now: now);
    }
  }

  int? lastImpressionTs(String videoId, {String? surface}) {
    if (surface != null) {
      return _impressions.get('$videoId|$surface') as int?;
    }
    return _impressions.get('$videoId|*') as int?;
  }

  bool shownRecently(String videoId,
      {Duration within = const Duration(days: 14), String? surface}) {
    final ts = lastImpressionTs(videoId, surface: surface);
    if (ts == null) return false;
    return DateTime.now().millisecondsSinceEpoch - ts < within.inMilliseconds;
  }

  // ─── API cache ────────────────────────────────────────────────────────

  Future<void> putCache(String key, dynamic json, Duration ttl) async {
    await _apiCache.put(key, {
      'json': json,
      'expiresTs': DateTime.now().add(ttl).millisecondsSinceEpoch,
    });
  }

  dynamic getCache(String key) {
    final v = _apiCache.get(key);
    if (v is! Map) return null;
    final exp = v['expiresTs'] as int? ?? 0;
    if (DateTime.now().millisecondsSinceEpoch > exp) {
      _apiCache.delete(key);
      return null;
    }
    return v['json'];
  }

  // ─── Mixes ────────────────────────────────────────────────────────────

  Future<void> saveMix(GeneratedMix mix) async {
    await _mixes.put(mix.id, mix.toJson());
  }

  GeneratedMix? getMix(String id) {
    final v = _mixes.get(id);
    if (v is! Map) return null;
    return GeneratedMix.fromJson(Map.from(v));
  }

  List<GeneratedMix> mixesOfKind(String kind) {
    return _mixes.values
        .whereType<Map>()
        .map((e) => GeneratedMix.fromJson(Map.from(e)))
        .where((m) => m.kind == kind)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  List<GeneratedMix> allMixes() {
    return _mixes.values
        .whereType<Map>()
        .map((e) => GeneratedMix.fromJson(Map.from(e)))
        .toList();
  }

  Future<void> setPref(String key, dynamic value) => _prefs.put(key, value);
  dynamic getPref(String key, {dynamic defaultValue}) =>
      _prefs.get(key, defaultValue: defaultValue);

  // ─── Follows ──────────────────────────────────────────────────────────

  Future<void> followArtist(String channelId,
      {required String name, String? thumbnailUrl}) async {
    await _follows.put(channelId, {
      'name': name,
      'thumbnailUrl': thumbnailUrl ?? '',
      'followedTs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> unfollowArtist(String channelId) => _follows.delete(channelId);

  bool isFollowed(String channelId) => _follows.containsKey(channelId);

  List<Map<String, dynamic>> followedArtists() {
    return _follows.keys
        .map((k) {
          final v = Map<String, dynamic>.from(_follows.get(k) as Map);
          v['channelId'] = k.toString();
          return v;
        })
        .toList();
  }

  /// Drop derived taste data; keep history/stats elsewhere.
  Future<void> resetTasteModel() async {
    await _events.clear();
    await _affinity.clear();
    await _trackStats.clear();
    await _cooc.clear();
    await _impressions.clear();
    await _mixes.clear();
  }

  // ─── Backfill from existing SongStats / history ───────────────────────

  /// Seed familiarity + affinity from existing `SongStats` box entries.
  Future<int> backfillFromSongStats(Box songStatsBox) async {
    var count = 0;
    final now = DateTime.now();
    for (final k in songStatsBox.keys) {
      final v = songStatsBox.get(k);
      if (v is! Map) continue;
      final videoId = k.toString();
      final plays = v['plays'] as int? ?? 0;
      final artist = v['artist'] as String? ?? '';
      final lastPlayed = v['lastPlayed'] as int? ?? now.millisecondsSinceEpoch;
      if (plays <= 0) continue;

      // Don't overwrite richer existing data
      if (!_trackStats.containsKey(videoId)) {
        await _trackStats.put(videoId, {
          'decayedPlays': plays.toDouble(),
          'lastPlayedTs': lastPlayed,
          'lifetimePlays': plays,
          'title': v['title'],
          'artist': artist,
        });
      }

      final artistKey = normalizeArtistKey(artist);
      if (artistKey.isNotEmpty) {
        // Soft seed: plays * 0.5 so real-time events dominate quickly
        final existing = affinityOf(artistKey, now: now);
        if (existing < plays * 0.3) {
          await _affinity.put(artistKey, {
            'score': plays * 0.5,
            'lastUpdatedTs': lastPlayed,
            'skips': 0,
            'listens': plays,
          });
        }
      }
      count++;
    }
    await setPref('backfilledFromStats', true);
    return count;
  }

  Future<void> seedSessionCooccurrence(List<String> videoIdsInOrder) async {
    for (var i = 0; i < videoIdsInOrder.length; i++) {
      for (var j = i + 1; j < videoIdsInOrder.length && j < i + 6; j++) {
        await bumpCooccurrence(videoIdsInOrder[i], videoIdsInOrder[j],
            weight: 0.5);
      }
    }
  }
}
