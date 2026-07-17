import 'package:audio_service/audio_service.dart';

import '../../models/media_Item_builder.dart';
import '../music_service.dart';
import 'discovery_math.dart';
import 'discovery_repository.dart';
import 'discovery_types.dart';

/// Fetches raw candidates from InnerTube / local graph / optional ListenBrainz.
/// Results are MediaItem-compatible JSON maps (via MediaItemBuilder).
class CandidateSources {
  CandidateSources({
    required this.music,
    required this.repo,
    this.listenBrainzFetcher,
  });

  final MusicServices music;
  final DiscoveryRepository repo;

  /// Optional: (videoId, title, artist) → list of similar maps.
  final Future<List<Map<String, dynamic>>> Function(String title, String artist)?
      listenBrainzFetcher;

  static const relatedTtl = Duration(days: 7);
  static const artistTtl = Duration(days: 3);
  static const chartsTtl = Duration(days: 1);

  /// Related / "more like this" via next→related browse.
  Future<List<Map<String, dynamic>>> relatedTracks(String videoId,
      {int limit = 40}) async {
    final cacheKey = 'related:$videoId';
    final cached = repo.getCache(cacheKey);
    if (cached is List) {
      return cached
          .map((e) => Map<String, dynamic>.from(e as Map))
          .take(limit)
          .toList();
    }

    try {
      final sections =
          await music.getContentRelatedToSong(videoId, 'en') as List?;
      final tracks = <Map<String, dynamic>>[];
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
      // Also pull radio-style next tracks as related
      if (tracks.length < 10) {
        final wp = await music.getWatchPlaylist(
            videoId: videoId, radio: true, limit: limit);
        final raw = wp['tracks'] as List? ?? [];
        for (final t in raw) {
          final m = _asTrackMap(t);
          if (m != null && m['videoId'] != videoId) tracks.add(m);
        }
      }
      await repo.putCache(cacheKey, tracks, relatedTtl);
      return tracks.take(limit).toList();
    } catch (_) {
      return [];
    }
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

  /// Artist top songs + related artists' top songs.
  Future<List<Map<String, dynamic>>> artistExpansion(String channelId,
      {int limit = 30}) async {
    final cacheKey = 'artist:$channelId';
    final cached = repo.getCache(cacheKey);
    if (cached is List) {
      return cached
          .map((e) => Map<String, dynamic>.from(e as Map))
          .take(limit)
          .toList();
    }
    try {
      final artist = await music.getArtist(channelId);
      final tracks = <Map<String, dynamic>>[];
      final top = artist['Top songs']?['results'] ??
          artist['Songs']?['results'] ??
          [];
      if (top is List) {
        for (final t in top) {
          final m = _asTrackMap(t);
          if (m != null) tracks.add(m);
        }
      }
      // Fans also like → their top songs (one hop)
      final related = artist['Fans might also like']?['results'] ??
          artist['Related']?['results'] ??
          artist['Similar artists']?['results'] ??
          [];
      if (related is List) {
        var hops = 0;
        for (final a in related) {
          if (hops >= 3) break;
          final id = a is Map ? (a['browseId'] ?? a['id']) : null;
          if (id is! String || id.isEmpty) continue;
          try {
            final ra = await music.getArtist(id);
            final rtop = ra['Top songs']?['results'] ?? [];
            if (rtop is List) {
              for (final t in rtop.take(4)) {
                final m = _asTrackMap(t);
                if (m != null) tracks.add(m);
              }
            }
            hops++;
          } catch (_) {}
        }
      }
      await repo.putCache(cacheKey, tracks, artistTtl);
      return tracks.take(limit).toList();
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

  Future<List<Map<String, dynamic>>> listenBrainzSimilar(
      String title, String artist) async {
    if (listenBrainzFetcher == null) return [];
    try {
      return await listenBrainzFetcher!(title, artist);
    } catch (_) {
      return [];
    }
  }

  /// Search YTM for title+artist (matcher for external ids).
  Future<Map<String, dynamic>?> matchToYtm(String title, String artist) async {
    try {
      final res = await music.search('$title $artist', filter: 'songs');
      final songs = res['songs'] ?? res['Tracks'] ?? [];
      if (songs is! List || songs.isEmpty) return null;
      // Fuzzy: prefer exact-ish title match
      final wantTitle = normalizeTitleKey(title);
      final wantArtist = normalizeArtistKey(artist);
      Map<String, dynamic>? best;
      var bestScore = -1.0;
      for (final s in songs.take(8)) {
        final m = _asTrackMap(s);
        if (m == null) continue;
        final tScore =
            normalizeTitleKey(m['title'] as String?) == wantTitle ? 2.0 : 0.0;
        final aScore = normalizeArtistKey(_artistString(m)) == wantArtist
            ? 2.0
            : 0.0;
        final score = tScore + aScore;
        if (score > bestScore) {
          bestScore = score;
          best = m;
        }
      }
      return best ?? _asTrackMap(songs.first);
    } catch (_) {
      return null;
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

  String _artistString(Map m) {
    if (m['artists'] is List) {
      return (m['artists'] as List)
          .map((e) => e is Map ? (e['name'] ?? '') : e.toString())
          .join(', ');
    }
    return m['artist']?.toString() ?? '';
  }

  /// Convert track maps to MediaItems.
  static List<MediaItem> toMediaItems(List<Map<String, dynamic>> maps,
      {DiscoverySource source = DiscoverySource.discover}) {
    return maps.map((m) {
      final item = MediaItemBuilder.fromJson(m);
      final extras = Map<String, dynamic>.from(item.extras ?? {});
      extras['discoverySource'] = source.wireName;
      return item.copyWith(extras: extras);
    }).toList();
  }
}
