import 'package:audio_service/audio_service.dart';

import '../../models/media_Item_builder.dart';
import '../../utils/media_item_video.dart';
import '../music_service.dart';
import 'discovery_repository.dart';

/// Fetches raw candidates from InnerTube and the local co-occurrence graph.
/// Results are MediaItem-compatible JSON maps (via MediaItemBuilder).
class CandidateSources {
  CandidateSources({
    required this.music,
    required this.repo,
  });

  final MusicServices music;
  final DiscoveryRepository repo;

  static const relatedTtl = Duration(days: 7);
  static const chartsTtl = Duration(days: 1);

  /// Related lookups in flight, by seed id. The similar-songs panel, smart
  /// radio and the smart queue often ask for the same seed at once.
  final _relatedInflight = <String, Future<List<Map<String, dynamic>>>>{};

  /// Related / "more like this" via next→related browse.
  ///
  /// Videos often lack a Related tab; we fall back to radio / search and
  /// always bound wait time so the player UI cannot spin forever.
  Future<List<Map<String, dynamic>>> relatedTracks(String videoId,
      {int limit = 40, MediaItem? seed}) async {
    final cacheKey = 'related:$videoId';
    final cached = repo.getCache(cacheKey);
    if (cached is List) {
      return cached
          .map((e) => Map<String, dynamic>.from(e as Map))
          .take(limit)
          .toList();
    }

    try {
      // Joined like the cache: the first caller's fetch serves everyone.
      // (Block body: an arrow would hand whenComplete the removed future,
      // i.e. itself, and it would wait forever.)
      final tracks = await (_relatedInflight[videoId] ??=
          _fetchRelated(videoId, cacheKey, limit: limit, seed: seed)
              .whenComplete(() {
        _relatedInflight.remove(videoId);
      }));
      // Copies, as from the cache: joined callers must not share maps.
      return tracks
          .take(limit)
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRelated(
      String videoId, String cacheKey,
      {required int limit, MediaItem? seed}) async {
    final tracks = await _relatedTracksUncached(videoId,
            limit: limit, seed: seed)
        .timeout(const Duration(seconds: 12), onTimeout: () => []);
    if (tracks.isNotEmpty) {
      await repo.putCache(cacheKey, tracks, relatedTtl);
    }
    return tracks;
  }

  Future<List<Map<String, dynamic>>> _relatedTracksUncached(
    String videoId, {
    required int limit,
    MediaItem? seed,
  }) async {
    final tracks = <Map<String, dynamic>>[];
    final isVideo = _seedLooksLikeVideo(seed);

    // Music videos: Related browse is often missing — prefer radio first.
    if (isVideo) {
      try {
        final wp = await music.getWatchPlaylist(
            videoId: videoId, radio: true, limit: limit);
        final raw = wp['tracks'] as List? ?? [];
        for (final t in raw) {
          final m = _asTrackMap(t);
          if (m != null && m['videoId'] != videoId) tracks.add(m);
        }
      } catch (_) {}
    }

    if (tracks.length < 10) {
      try {
        final sections =
            await music.getContentRelatedToSong(videoId, 'en') as List?;
        if (sections != null) {
          for (final section in sections) {
            if (section is! Map) continue;
            final contents = section['contents'] ?? section['playlists'];
            if (contents is! List) continue;
            for (final item in contents) {
              final m = _asTrackMap(item);
              if (m != null) tracks.add(m);
            }
          }
        }
      } catch (_) {}
    }

    // Radio-style next tracks as related (songs + videos). A video seed
    // already has its radio above: asking again re-fetched the same list
    // and appended every track a second time.
    if (!isVideo && tracks.length < 10) {
      try {
        final wp = await music.getWatchPlaylist(
            videoId: videoId, radio: true, limit: limit);
        final raw = wp['tracks'] as List? ?? [];
        for (final t in raw) {
          final m = _asTrackMap(t);
          if (m != null && m['videoId'] != videoId) tracks.add(m);
        }
      } catch (_) {}
    }

    // Last resort: search by title (and artist) so videos still get neighbors.
    if (tracks.length < 8 && seed != null) {
      final q = [
        seed.title.trim(),
        if ((seed.artist ?? '').trim().isNotEmpty) seed.artist!.trim(),
      ].join(' ');
      if (q.isNotEmpty) {
        try {
          final filter = isVideo ? 'videos' : 'songs';
          final res = await music.search(q, filter: filter);
          final bucket = isVideo
              ? (res['Videos'] ?? res['videos'] ?? res['songs'] ?? [])
              : (res['songs'] ?? res['Songs'] ?? res['Tracks'] ?? []);
          if (bucket is List) {
            for (final t in bucket.take(limit)) {
              final m = _asTrackMap(t);
              if (m != null && m['videoId'] != videoId) tracks.add(m);
            }
          }
        } catch (_) {}
      }
    }

    return tracks;
  }

  static bool _seedLooksLikeVideo(MediaItem? seed) {
    if (seed == null) return false;
    // Prefer shared helper so player + discovery stay in sync.
    return seed.isYoutubeVideo;
  }

  /// Radio continuation batch for a seed.
  Future<List<Map<String, dynamic>>> radioBatch(String videoId,
      {int limit = 25, String? additionalParams}) async {
    try {
      final wp = await music.getWatchPlaylist(
        videoId: videoId,
        radio: true,
        limit: limit,
        additionalParamsNext: additionalParams,
      );
      final raw = wp['tracks'] as List? ?? [];
      return raw
          .map(_asTrackMap)
          .whereType<Map<String, dynamic>>()
          .where((m) => m['videoId'] != videoId)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Local co-occurrence neighbors as candidate ids (need song meta from stats/cache).
  List<String> localNeighborIds(String videoId, {int limit = 30}) {
    return repo.neighborsOf(videoId, limit: limit).keys.toList();
  }

  /// Charts for cold start.
  Future<List<Map<String, dynamic>>> charts({int limit = 40}) async {
    const cacheKey = 'charts:home';
    final cached = repo.getCache(cacheKey);
    if (cached is List) {
      return cached
          .map((e) => Map<String, dynamic>.from(e as Map))
          .take(limit)
          .toList();
    }
    try {
      final home = await music.getHome(limit: 4) as List;
      final tracks = <Map<String, dynamic>>[];
      for (final section in home) {
        if (section is! Map) continue;
        final contents = section['contents'];
        if (contents is! List) continue;
        for (final item in contents) {
          final m = _asTrackMap(item);
          if (m != null) tracks.add(m);
        }
      }
      await repo.putCache(cacheKey, tracks, chartsTtl);
      return tracks.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic>? _asTrackMap(dynamic item) {
    if (item == null) return null;
    if (item is MediaItem) {
      return MediaItemBuilder.toJson(item);
    }
    if (item is Map) {
      final m = Map<String, dynamic>.from(item);
      // Already a track map with videoId
      if (m['videoId'] != null) {
        // Ensure thumbnails shape for MediaItemBuilder
        if (m['thumbnails'] == null) {
          final thumb = m['thumbnail'];
          if (thumb is String) {
            m['thumbnails'] = [
              {'url': thumb}
            ];
          } else if (thumb is List) {
            m['thumbnails'] = thumb;
          } else {
            m['thumbnails'] = [
              {'url': ''}
            ];
          }
        }
        return m;
      }
    }
    return null;
  }
}
