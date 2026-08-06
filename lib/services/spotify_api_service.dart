import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/helper.dart';
import 'spotify_auth_service.dart';
import 'spotify_import_service.dart';

/// Reads the signed-in user's own Spotify library through the documented
/// public Web API (`api.spotify.com/v1`).
///
/// Everything is returned as the same [SpotifyTrackRef] / [SpotifyPlaylistImport]
/// shapes the existing public-playlist import already produces, so the tracks
/// flow straight into `SpotifyImportService.resolveTracksToYtm` and reuse the
/// candidate scoring rather than growing a parallel pipeline.
class SpotifyApiService {
  SpotifyApiService({required SpotifyAuthService auth, Dio? dio})
      : _auth = auth,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              responseType: ResponseType.plain,
            ));

  final SpotifyAuthService _auth;
  final Dio _dio;

  static const base = 'https://api.spotify.com/v1';

  /// Spotify caps `limit` at 50 for these endpoints; asking for more is a 400.
  static const pageSize = 50;

  // ---- pure parsing ----------------------------------------------------

  /// Parse a track out of a playlist/saved-tracks item.
  ///
  /// Returns null for the entries Spotify legitimately includes but that cannot
  /// be played: removed tracks (`track: null`), local files, and podcast
  /// episodes appearing in a playlist.
  static SpotifyTrackRef? parseTrackItem(dynamic item) {
    if (item is! Map) return null;
    // Saved-tracks and playlist-items both nest the track under `track`;
    // a raw track object is accepted too.
    final t = item['track'] ?? item;
    if (t is! Map) return null;
    if (t['is_local'] == true) return null;
    if ((t['type']?.toString() ?? 'track') != 'track') return null;

    final name = t['name']?.toString() ?? '';
    if (name.isEmpty) return null;

    final id = t['id']?.toString() ?? '';
    final artists = (t['artists'] is List)
        ? (t['artists'] as List)
            .map((a) => (a is Map ? a['name']?.toString() : null))
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(', ')
        : '';

    final durMs = t['duration_ms'];
    return SpotifyTrackRef(
      id: id,
      title: name,
      artists: artists,
      durationMs: (durMs is num && durMs > 0) ? durMs.toInt() : null,
    );
  }

  /// Parse one page of items into track refs, skipping unplayable entries.
  static List<SpotifyTrackRef> parseTrackPage(String body) {
    final json = _tryDecode(body);
    if (json == null) return const [];
    final items = json['items'];
    if (items is! List) return const [];
    return items
        .map(parseTrackItem)
        .whereType<SpotifyTrackRef>()
        .toList(growable: false);
  }

  /// The `next` URL of a paged response, or null on the last page.
  static String? nextPageUrl(String body) {
    final json = _tryDecode(body);
    final next = json?['next'];
    return (next is String && next.isNotEmpty) ? next : null;
  }

  /// Parse the user's playlist list (not their tracks).
  static List<SpotifyPlaylistSummary> parsePlaylistPage(String body) {
    final json = _tryDecode(body);
    final items = json?['items'];
    if (items is! List) return const [];
    final out = <SpotifyPlaylistSummary>[];
    for (final p in items) {
      if (p is! Map) continue;
      final id = p['id']?.toString();
      final name = p['name']?.toString();
      if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
      String? cover;
      final images = p['images'];
      if (images is List && images.isNotEmpty && images.first is Map) {
        cover = images.first['url']?.toString();
      }
      final total = p['tracks'] is Map ? p['tracks']['total'] : null;
      out.add(SpotifyPlaylistSummary(
        id: id,
        name: name,
        coverUrl: cover,
        trackCount: total is num ? total.toInt() : 0,
      ));
    }
    return out;
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      final d = jsonDecode(body);
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  // ---- network ---------------------------------------------------------

  Future<String?> _get(String url) async {
    final token = await _auth.validAccessToken();
    if (token == null) return null;
    final res = await _dio.get(
      url,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        validateStatus: (_) => true,
      ),
    );
    if (res.statusCode == 200) return res.data.toString();
    printINFO('Spotify API ${res.statusCode} for $url');
    return null;
  }

  /// Follow `next` links until the library is exhausted. [maxPages] is a
  /// runaway guard, not a product limit — it is generous enough for very large
  /// libraries and is logged if ever reached.
  Future<List<SpotifyTrackRef>> _pagedTracks(String firstUrl,
      {int maxPages = 100}) async {
    final out = <SpotifyTrackRef>[];
    String? url = firstUrl;
    var pages = 0;
    while (url != null && pages < maxPages) {
      final body = await _get(url);
      if (body == null) break;
      out.addAll(parseTrackPage(body));
      url = nextPageUrl(body);
      pages++;
    }
    if (url != null) {
      printINFO('Spotify: stopped paging at $maxPages pages; list truncated');
    }
    return out;
  }

  /// The user's own + followed playlists.
  Future<List<SpotifyPlaylistSummary>> fetchPlaylists(
      {int maxPages = 40}) async {
    final out = <SpotifyPlaylistSummary>[];
    String? url = '$base/me/playlists?limit=$pageSize';
    var pages = 0;
    while (url != null && pages < maxPages) {
      final body = await _get(url);
      if (body == null) break;
      out.addAll(parsePlaylistPage(body));
      url = nextPageUrl(body);
      pages++;
    }
    return out;
  }

  /// Every track in one playlist.
  Future<List<SpotifyTrackRef>> fetchPlaylistTracks(String playlistId) =>
      _pagedTracks('$base/playlists/$playlistId/tracks?limit=$pageSize');

  /// The user's Liked Songs.
  Future<List<SpotifyTrackRef>> fetchLikedSongs() =>
      _pagedTracks('$base/me/tracks?limit=$pageSize');

  /// Convenience: a playlist as the same shape the public import produces.
  Future<SpotifyPlaylistImport> fetchPlaylistAsImport(
      SpotifyPlaylistSummary summary) async {
    final tracks = await fetchPlaylistTracks(summary.id);
    return SpotifyPlaylistImport(
      id: summary.id,
      name: summary.name,
      type: 'playlist',
      tracks: tracks,
      coverUrl: summary.coverUrl,
    );
  }
}

/// A playlist as listed on the user's account, before its tracks are fetched.
class SpotifyPlaylistSummary {
  const SpotifyPlaylistSummary({
    required this.id,
    required this.name,
    this.coverUrl,
    this.trackCount = 0,
  });

  final String id;
  final String name;
  final String? coverUrl;
  final int trackCount;
}
