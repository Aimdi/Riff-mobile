import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../models/media_Item_builder.dart';
import '../utils/helper.dart';
import 'music_service.dart';

/// One track as listed on a public Spotify playlist / album page.
class SpotifyTrackRef {
  const SpotifyTrackRef({
    required this.id,
    required this.title,
    required this.artists,
    this.durationMs,
  });

  final String id;
  final String title;
  final String artists;
  final int? durationMs;

  String get searchQuery {
    // Spotify subtitles use non-breaking spaces between artists.
    final cleanedArtists =
        artists.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return '$title $cleanedArtists'.trim();
  }
}

class SpotifyPlaylistImport {
  const SpotifyPlaylistImport({
    required this.id,
    required this.name,
    required this.type,
    required this.tracks,
    this.coverUrl,
  });

  final String id;
  final String name;
  final String type; // playlist | album
  final List<SpotifyTrackRef> tracks;
  final String? coverUrl;
}

/// Spotube-style public Spotify metadata import.
///
/// Does **not** require a Spotify login. Public playlists / albums are loaded
/// via Spotify's embed page (`open.spotify.com/embed/...`), then each track is
/// resolved on YouTube Music by title + artist search — the same idea Spotube
/// uses when bridging Spotify libraries to free sources.
class SpotifyImportService extends GetxService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'user-agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'accept-language': 'en-US,en;q=0.9',
    },
    responseType: ResponseType.plain,
  ));

  /// Parse playlist / album id from a Spotify share URL or URI.
  /// Returns `(type, id)` e.g. `('playlist', '37i9d...')`.
  static (String, String)? parseSpotifyUrl(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    // spotify:playlist:ID / spotify:album:ID
    final uriMatch =
        RegExp(r'spotify:(playlist|album):([A-Za-z0-9]+)').firstMatch(raw);
    if (uriMatch != null) {
      return (uriMatch.group(1)!, uriMatch.group(2)!);
    }

    // https://open.spotify.com/playlist/ID?...  (also international.spotify.com)
    final urlMatch = RegExp(
      r'(?:open|play)\.spotify\.com/(?:intl-[a-z]{2}/)?(playlist|album)/([A-Za-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (urlMatch != null) {
      return (urlMatch.group(1)!.toLowerCase(), urlMatch.group(2)!);
    }

    // Bare id — assume playlist
    if (RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(raw)) {
      return ('playlist', raw);
    }
    return null;
  }

  /// Fetch public playlist / album metadata + track list from Spotify embed.
  Future<SpotifyPlaylistImport> fetchPublicCollection(String urlOrId) async {
    final parsed = parseSpotifyUrl(urlOrId);
    if (parsed == null) {
      throw ArgumentError('Invalid Spotify playlist/album URL');
    }
    final (type, id) = parsed;
    final embedUrl = 'https://open.spotify.com/embed/$type/$id';

    final res = await _dio.get(embedUrl);
    final html = res.data.toString();

    final nextData = _extractNextData(html);
    if (nextData == null) {
      throw StateError('Could not read Spotify embed data');
    }

    final entity = nextData['props']?['pageProps']?['state']?['data']
        ?['entity'] as Map?;
    if (entity == null) {
      throw StateError('Spotify collection not found or private');
    }

    final name = (entity['name'] ?? entity['title'] ?? 'Spotify import')
        .toString();
    String? coverUrl;
    final sources = entity['coverArt']?['sources'];
    if (sources is List && sources.isNotEmpty) {
      coverUrl = sources.last['url']?.toString() ??
          sources.first['url']?.toString();
    }

    final trackList = entity['trackList'] as List? ?? const [];
    final tracks = <SpotifyTrackRef>[];
    for (final t in trackList) {
      if (t is! Map) continue;
      final uri = (t['uri'] ?? '').toString();
      final trackId = uri.contains(':') ? uri.split(':').last : uri;
      final title = (t['title'] ?? '').toString();
      if (title.isEmpty) continue;
      tracks.add(SpotifyTrackRef(
        id: trackId,
        title: title,
        artists: (t['subtitle'] ?? '').toString(),
        durationMs: t['duration'] is num ? (t['duration'] as num).toInt() : null,
      ));
    }

    if (tracks.isEmpty) {
      throw StateError(
          'No tracks found — playlist may be private or region-locked');
    }

    printINFO('Spotify import: "$name" ($type) → ${tracks.length} tracks');
    return SpotifyPlaylistImport(
      id: id,
      name: name,
      type: type,
      tracks: tracks,
      coverUrl: coverUrl,
    );
  }

  Map<String, dynamic>? _extractNextData(String html) {
    final marker = 'id="__NEXT_DATA__"';
    final i = html.indexOf(marker);
    if (i < 0) return null;
    final start = html.indexOf('>', i);
    if (start < 0) return null;
    final end = html.indexOf('</script>', start);
    if (end < 0) return null;
    final jsonStr = html.substring(start + 1, end).trim();
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Resolve Spotify tracks to YouTube Music [MediaItem]s via song search.
  ///
  /// [onProgress] is called with `(done, total)` after each track.
  Future<List<MediaItem>> resolveTracksToYtm(
    List<SpotifyTrackRef> tracks, {
    void Function(int done, int total)? onProgress,
    int concurrency = 3,
  }) async {
    final music = Get.find<MusicServices>();
    final results = List<MediaItem?>.filled(tracks.length, null);
    var done = 0;

    Future<void> resolveOne(int index) async {
      final t = tracks[index];
      try {
        final res = await music.search(
          t.searchQuery,
          filter: 'songs',
          limit: 5,
        );
        MediaItem? best;
        for (final entry in res.entries) {
          if (entry.key == 'params' || entry.key == 'searchEndpoint') continue;
          final list = entry.value;
          if (list is! List) continue;
          for (final item in list) {
            if (item is MediaItem) {
              best = item;
              break;
            }
            if (item is Map && item['videoId'] != null) {
              best = MediaItemBuilder.fromJson(item);
              break;
            }
          }
          if (best != null) break;
        }
        results[index] = best;
      } catch (e) {
        printERROR('YTM resolve failed for "${t.searchQuery}": $e');
      } finally {
        done++;
        onProgress?.call(done, tracks.length);
      }
    }

    // Simple worker pool
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= tracks.length) return;
        await resolveOne(i);
      }
    }

    final n = concurrency.clamp(1, 6);
    await Future.wait(List.generate(n, (_) => worker()));

    return results.whereType<MediaItem>().toList();
  }
}
