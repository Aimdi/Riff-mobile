import 'discovery_math.dart';
import 'discovery_repository.dart';
import 'discovery_types.dart';

/// Local private taste model: event ingestion + derived scores.
/// Pure Dart logic over [DiscoveryRepository] — no Flutter widgets.
class TasteModel {
  TasteModel(this.repo);

  final DiscoveryRepository repo;

  /// In-memory sliding window of recent plays for session co-occurrence
  /// (30-minute sessions).
  final List<({String videoId, int ts})> _sessionPlays = [];
  static const Duration sessionWindow = Duration(minutes: 30);

  // ─── Event ingestion ──────────────────────────────────────────────────

  Future<void> logPlayStarted({
    required String videoId,
    required String? artist,
    required String? title,
    required DiscoverySource source,
    String? surface,
  }) async {
    final artistKey = normalizeArtistKey(artist);
    final now = DateTime.now();
    await repo.appendEvent(DiscoveryEvent(
      videoId: videoId,
      artistKey: artistKey,
      ts: now.millisecondsSinceEpoch,
      source: source,
      event: DiscoveryEventKind.playStarted,
      title: title,
      artist: artist,
      surface: surface,
    ));
    await repo.recordTrackPlay(videoId, now: now);

    // Session co-occurrence
    final cutoff = now.subtract(sessionWindow).millisecondsSinceEpoch;
    _sessionPlays.removeWhere((e) => e.ts < cutoff);
    for (final prev in _sessionPlays) {
      await repo.bumpCooccurrence(prev.videoId, videoId, weight: 1.0);
    }
    _sessionPlays.add((videoId: videoId, ts: now.millisecondsSinceEpoch));
  }

  /// Call when a track ends or is skipped. [listenedMs] and [totalMs]
  /// determine fraction / quick-skip.
  Future<void> logPlayEnded({
    required String videoId,
    required String? artist,
    required String? title,
    required DiscoverySource source,
    required int listenedMs,
    required int totalMs,
    String? surface,
  }) async {
    final artistKey = normalizeArtistKey(artist);
    final now = DateTime.now();
    final fraction =
        totalMs > 0 ? (listenedMs / totalMs).clamp(0.0, 1.0) : 0.0;
    final isQuickSkip = listenedMs < 10000 && fraction < 0.30;

    DiscoveryEventKind kind;
    double affinityDelta;

    if (isQuickSkip) {
      kind = DiscoveryEventKind.quickSkip;
      affinityDelta = AffinityWeights.quickSkip;
    } else {
      final quality = classifyListen(fraction);
      switch (quality) {
        case ListenQuality.strongPositive:
          kind = DiscoveryEventKind.playEnded;
          affinityDelta = source == DiscoverySource.userClick ||
                  source == DiscoverySource.queue
              ? AffinityWeights.fullListenUserInitiated
              : AffinityWeights.fullListen;
          break;
        case ListenQuality.weakPositive:
          kind = DiscoveryEventKind.playEnded;
          affinityDelta = AffinityWeights.weakListen;
          break;
        case ListenQuality.negative:
          kind = DiscoveryEventKind.skip;
          affinityDelta = AffinityWeights.skip;
          break;
      }
    }

    await repo.appendEvent(DiscoveryEvent(
      videoId: videoId,
      artistKey: artistKey,
      ts: now.millisecondsSinceEpoch,
      source: source,
      event: kind,
      fraction: fraction,
      title: title,
      artist: artist,
      surface: surface,
    ));
    await repo.bumpAffinity(artistKey, affinityDelta,
        now: now, displayName: artist);
  }

  Future<void> logFavorite(String videoId, String? artist, String? title,
      {bool add = true}) async {
    final artistKey = normalizeArtistKey(artist);
    await repo.appendEvent(DiscoveryEvent(
      videoId: videoId,
      artistKey: artistKey,
      ts: DateTime.now().millisecondsSinceEpoch,
      source: DiscoverySource.userClick,
      event: add
          ? DiscoveryEventKind.favorite
          : DiscoveryEventKind.unfavorite,
      title: title,
      artist: artist,
    ));
    await repo.bumpAffinity(artistKey,
        add ? AffinityWeights.favorite : -AffinityWeights.favorite,
        displayName: artist);
  }

  Future<void> logPlaylistAdd(
      String videoId, String? artist, String? title) async {
    final artistKey = normalizeArtistKey(artist);
    await repo.appendEvent(DiscoveryEvent(
      videoId: videoId,
      artistKey: artistKey,
      ts: DateTime.now().millisecondsSinceEpoch,
      source: DiscoverySource.userClick,
      event: DiscoveryEventKind.playlistAdd,
      title: title,
      artist: artist,
    ));
    await repo.bumpAffinity(artistKey, AffinityWeights.playlistAdd,
        displayName: artist);
  }

  Future<void> logDownload(
      String videoId, String? artist, String? title) async {
    final artistKey = normalizeArtistKey(artist);
    await repo.appendEvent(DiscoveryEvent(
      videoId: videoId,
      artistKey: artistKey,
      ts: DateTime.now().millisecondsSinceEpoch,
      source: DiscoverySource.userClick,
      event: DiscoveryEventKind.download,
      title: title,
      artist: artist,
    ));
    await repo.bumpAffinity(artistKey, AffinityWeights.download,
        displayName: artist);
  }

  Future<void> logFollow(String artistName, {bool follow = true}) async {
    final artistKey = normalizeArtistKey(artistName);
    await repo.appendEvent(DiscoveryEvent(
      videoId: '',
      artistKey: artistKey,
      ts: DateTime.now().millisecondsSinceEpoch,
      source: DiscoverySource.userClick,
      event:
          follow ? DiscoveryEventKind.follow : DiscoveryEventKind.unfollow,
      artist: artistName,
    ));
    await repo.bumpAffinity(
        artistKey, follow ? AffinityWeights.follow : -AffinityWeights.follow,
        displayName: artistName);
  }

  Future<void> logNeverPlay(
      String videoId, String? artist, String? title) async {
    final artistKey = normalizeArtistKey(artist);
    await repo.appendEvent(DiscoveryEvent(
      videoId: videoId,
      artistKey: artistKey,
      ts: DateTime.now().millisecondsSinceEpoch,
      source: DiscoverySource.userClick,
      event: DiscoveryEventKind.neverPlay,
      title: title,
      artist: artist,
    ));
    // Mild artist-level penalty
    await repo.bumpAffinity(artistKey, AffinityWeights.neverPlay,
        displayName: artist);
  }

  Future<void> logThumbs({
    required String videoId,
    required String? artist,
    required String? title,
    required bool up,
    String? surface,
  }) async {
    final artistKey = normalizeArtistKey(artist);
    await repo.appendEvent(DiscoveryEvent(
      videoId: videoId,
      artistKey: artistKey,
      ts: DateTime.now().millisecondsSinceEpoch,
      source: DiscoverySource.discover,
      event: up ? DiscoveryEventKind.thumbsUp : DiscoveryEventKind.thumbsDown,
      title: title,
      artist: artist,
      surface: surface,
    ));
    await repo.bumpAffinity(
        artistKey, up ? AffinityWeights.thumbsUp : AffinityWeights.thumbsDown,
        displayName: artist);
  }

  Future<void> logDismiss({
    required String videoId,
    required String? artist,
    required String? title,
    String? surface,
  }) async {
    final artistKey = normalizeArtistKey(artist);
    await repo.appendEvent(DiscoveryEvent(
      videoId: videoId,
      artistKey: artistKey,
      ts: DateTime.now().millisecondsSinceEpoch,
      source: DiscoverySource.discover,
      event: DiscoveryEventKind.dismiss,
      title: title,
      artist: artist,
      surface: surface,
    ));
    await repo.bumpAffinity(artistKey, AffinityWeights.dismiss,
        displayName: artist);
  }

  Future<void> logImpression(String videoId, String surface) =>
      repo.logImpression(videoId, surface);

  // ─── Scoring helpers used by the pipeline ─────────────────────────────

  /// Score a candidate track. Higher is better.
  double scoreCandidate({
    required String videoId,
    required String artistKey,
    required double sourceConfidence,
    double cooccurrenceStrength = 0,
    bool noveltyBonus = false,
    bool isBanned = false,
  }) {
    if (isBanned) return double.negativeInfinity;

    var score = sourceConfidence;
    score += repo.affinityOf(artistKey) * 0.35;
    score += cooccurrenceStrength * 0.5;

    // Penalties
    final lastPlayed = repo.lastPlayedTs(videoId);
    if (lastPlayed != null) {
      final daysAgo =
          (DateTime.now().millisecondsSinceEpoch - lastPlayed) / 86400000;
      if (daysAgo < 7) {
        score -= (7 - daysAgo) * 1.2; // strong recent-play penalty
      }
    }
    if (repo.shownRecently(videoId, within: const Duration(days: 14))) {
      score -= 2.5;
    }
    final skipRate = repo.skipRateOf(artistKey);
    if (skipRate > 0.4) {
      score -= skipRate * 4.0;
    }

    if (noveltyBonus && repo.isUnheard(videoId)) {
      score += 1.5;
    } else if (noveltyBonus) {
      // mild penalty for already-known on exploration surfaces
      score -= 0.3;
    }

    return score;
  }

  int get lifetimeEventCount => repo.recentEvents(limit: 20000).length;

  /// Enough listens for personal sections (~20).
  bool get hasEnoughSignal {
    // Prefer track stats count as a cheap proxy
    final top = repo.topAffinities(limit: 5);
    return top.isNotEmpty &&
        top.values.fold<double>(0, (a, b) => a + b) >= 8;
  }
}
