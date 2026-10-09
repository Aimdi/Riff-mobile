import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive/hive.dart';

import '../utils/helper.dart';
import 'spotify_auth_service.dart';
import 'spotify_connect_models.dart';
import 'spotify_import_service.dart';

/// Why a Spotify Web API call failed, for a message the user can act on.
enum SpotifyErrorKind {
  /// Not signed in, or the session ended (sign in again).
  signedOut,

  /// 403: the app owner's Premium lapsed, the user isn't on the app's
  /// user list, or the endpoint isn't available to Development Mode apps.
  forbidden,

  /// 404.
  notFound,

  /// 429 that didn't clear after waiting as asked.
  rateLimited,

  /// 429 with `reason: QUOTA_EXCEEDED`: the developer account's quota is
  /// used up; wait longer.
  quotaExceeded,

  /// 5xx and other answers.
  server,

  /// No answer.
  network,

  /// 403 `PREMIUM_REQUIRED`: playback control needs Spotify Premium.
  premiumRequired,

  /// 404 `NO_ACTIVE_DEVICE`: no Spotify device is awake to play on.
  noActiveDevice,
}

class SpotifyApiException implements Exception {
  const SpotifyApiException(this.kind, {this.status, this.retryAfter});
  final SpotifyErrorKind kind;
  final int? status;

  /// For [SpotifyErrorKind.rateLimited] / [SpotifyErrorKind.quotaExceeded]:
  /// how long until it's worth trying again, when known.
  final Duration? retryAfter;

  @override
  String toString() => 'SpotifyApiException(${kind.name}, $status)';
}

/// What a non-200 answer means.
SpotifyErrorKind classifySpotifyError(int status, Object? body) {
  final reason = spotifyErrorReason(body);
  if (status == 401) return SpotifyErrorKind.signedOut;
  if (status == 403) {
    return reason == 'PREMIUM_REQUIRED'
        ? SpotifyErrorKind.premiumRequired
        : SpotifyErrorKind.forbidden;
  }
  if (status == 404) {
    return reason == 'NO_ACTIVE_DEVICE'
        ? SpotifyErrorKind.noActiveDevice
        : SpotifyErrorKind.notFound;
  }
  if (status == 429) {
    return isQuotaExceeded(body)
        ? SpotifyErrorKind.quotaExceeded
        : SpotifyErrorKind.rateLimited;
  }
  return SpotifyErrorKind.server;
}

/// `error.reason` of an error answer (`PREMIUM_REQUIRED`, …), or null.
String? spotifyErrorReason(Object? body) {
  try {
    final j = body is Map ? body : jsonDecode('$body');
    final e = j is Map ? j['error'] : null;
    final r = e is Map ? e['reason'] : null;
    return r is String ? r : null;
  } catch (_) {
    return null;
  }
}

/// `{"error":{"status":429,"message":"Too many requests",
/// "reason":"QUOTA_EXCEEDED"}}`.
bool isQuotaExceeded(Object? body) {
  try {
    final j = body is Map ? body : jsonDecode('$body');
    final e = j is Map ? j['error'] : null;
    return e is Map && e['reason'] == 'QUOTA_EXCEEDED';
  } catch (_) {
    return false;
  }
}

/// `Retry-After` in seconds (Spotify sends seconds).
Duration? parseRetryAfter(String? header) {
  final s = int.tryParse((header ?? '').trim());
  return s == null || s < 0 ? null : Duration(seconds: s);
}

/// How long to wait before retry [attempt] (0-based) of a 429: what the
/// server asked for, else 1 s, 2 s, 4 s.
Duration rateLimitDelay(Duration? retryAfter, int attempt) =>
    retryAfter ?? Duration(seconds: 1 << attempt.clamp(0, 5));

/// Whether a cached answer stored at [storedAtMs] is still good.
bool spotifyCacheFresh(int storedAtMs, int nowMs, Duration ttl) =>
    nowMs >= storedAtMs && nowMs - storedAtMs < ttl.inMilliseconds;

/// Reads the signed-in user's own Spotify library through the documented
/// public Web API (`api.spotify.com/v1`), within what Development Mode apps
/// may use since February 2026: no batch lookups, artist top tracks,
/// browse, recommendations or related artists; search returns at most 10
/// per page; playlist contents only for playlists the user owns or
/// collaborates on.
///
/// Tracks come back as the same [SpotifyTrackRef]s the public import
/// produces, so they flow into `SpotifyImportService` for matching.
class SpotifyApiService {
  SpotifyApiService({
    required SpotifyAuthService auth,
    Dio? dio,
    Future<String?> Function()? token,
    Future<bool> Function()? refresh,
    Future<void> Function(Duration)? sleep,
    bool useCache = true,
  })  : _token = token ?? auth.validAccessToken,
        _refresh = refresh ?? auth.refresh,
        _sleep = sleep ?? Future<void>.delayed,
        _useCache = useCache,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              responseType: ResponseType.plain,
            ));

  final Future<String?> Function() _token;
  final Future<bool> Function() _refresh;
  final Future<void> Function(Duration) _sleep;
  final bool _useCache;
  final Dio _dio;

  static const base = 'https://api.spotify.com/v1';

  /// Spotify caps `limit` at 50 for library endpoints.
  static const pageSize = 50;

  /// Search returns at most 10 per page for Development Mode apps.
  static const searchPageSize = 10;

  /// Library and profile answers are kept this long.
  static const libraryTtl = Duration(hours: 6);

  /// Waits longer than this aren't done in place; the call fails with the
  /// time to wait instead.
  static const maxInlineWait = Duration(seconds: 30);

  /// After QUOTA_EXCEEDED, no calls for this long.
  static const quotaCooldown = Duration(minutes: 10);

  static int _cooldownUntilMs = 0;

  /// Tests: forget a quota cooldown.
  @visibleForTesting
  static void resetCooldown() => _cooldownUntilMs = 0;

  static const cacheBox = 'SpotifyCache';

  // ---- pure parsing ----------------------------------------------------

  static String _joinArtists(Object? artists) => artists is List
      ? artists
          .map((a) => (a is Map ? a['name']?.toString() : null))
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(', ')
      : '';

  static String? _firstImage(Object? images) {
    if (images is List && images.isNotEmpty && images.first is Map) {
      final u = (images.first as Map)['url'];
      if (u is String && u.isNotEmpty) return u;
    }
    return null;
  }

  /// Parse a track out of a playlist/saved-tracks/recently-played item.
  ///
  /// Returns null for the entries Spotify legitimately includes but that cannot
  /// be played: removed tracks (`track: null`), local files, and podcast
  /// episodes appearing in a playlist. [album] fills in album name and art
  /// for album track lists, whose tracks don't carry them.
  static SpotifyTrackRef? parseTrackItem(dynamic item, {Map? album}) {
    if (item is! Map) return null;
    // Playlist items nest the track under `item` (since 2026) or `track`;
    // saved tracks under `track`; a raw track object is accepted too.
    final t = item.containsKey('item')
        ? item['item']
        : (item.containsKey('track') ? item['track'] : item);
    if (t is! Map) return null;
    if (t['is_local'] == true) return null;
    if ((t['type']?.toString() ?? 'track') != 'track') return null;

    final name = t['name']?.toString() ?? '';
    if (name.isEmpty) return null;

    final id = t['id']?.toString() ?? '';
    final al = t['album'] is Map ? t['album'] as Map : album;
    final ext = t['external_ids'];
    final isrc = ext is Map ? ext['isrc']?.toString().toUpperCase() : null;

    final durMs = t['duration_ms'];
    return SpotifyTrackRef(
      id: id,
      title: name,
      artists: _joinArtists(t['artists']),
      durationMs: (durMs is num && durMs > 0) ? durMs.toInt() : null,
      isrc: isrc != null && isrc.isNotEmpty ? isrc : null,
      album: al?['name']?.toString(),
      artUrl: _firstImage(al?['images']),
    );
  }

  /// Parse one page of items into track refs, skipping unplayable entries.
  static List<SpotifyTrackRef> parseTrackPage(String body, {Map? album}) {
    final json = _tryDecode(body);
    if (json == null) return const [];
    final items = json['items'];
    if (items is! List) return const [];
    return items
        .map((i) => parseTrackItem(i, album: album))
        .whereType<SpotifyTrackRef>()
        .toList(growable: false);
  }

  /// The `next` URL of a paged response, or null on the last page.
  static String? nextPageUrl(String body, {String? under}) {
    var json = _tryDecode(body);
    if (under != null) {
      final inner = json?[under];
      json = inner is Map ? Map<String, dynamic>.from(inner) : null;
    }
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
      // `items` since 2026, `tracks` before.
      final counter = p['items'] is Map ? p['items'] : p['tracks'];
      final total = counter is Map ? counter['total'] : null;
      final owner = p['owner'];
      out.add(SpotifyPlaylistSummary(
        id: id,
        name: name,
        coverUrl: _firstImage(p['images']),
        trackCount: total is num ? total.toInt() : 0,
        ownerId: owner is Map ? owner['id']?.toString() : null,
        ownerName: owner is Map ? owner['display_name']?.toString() : null,
        collaborative: p['collaborative'] == true,
      ));
    }
    return out;
  }

  static SpotifyAlbumSummary? parseAlbum(dynamic a) {
    if (a is Map && a['album'] is Map) a = a['album'];
    if (a is! Map) return null;
    final id = a['id']?.toString() ?? '';
    final name = a['name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final date = a['release_date']?.toString() ?? '';
    final total = a['total_tracks'];
    return SpotifyAlbumSummary(
      id: id,
      name: name,
      artists: _joinArtists(a['artists']),
      coverUrl: _firstImage(a['images']),
      year: date.length >= 4 ? date.substring(0, 4) : null,
      trackCount: total is num ? total.toInt() : 0,
      releaseDate: date.isEmpty ? null : date,
    );
  }

  static SpotifyArtistSummary? parseArtist(dynamic a) {
    if (a is! Map) return null;
    final id = a['id']?.toString() ?? '';
    final name = a['name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final genres = a['genres'];
    return SpotifyArtistSummary(
        id: id,
        name: name,
        imageUrl: _firstImage(a['images']),
        genres: [
          if (genres is List)
            for (final g in genres)
              if (g is String && g.isNotEmpty) g
        ]);
  }

  static List<T> _parseList<T>(Object? items, T? Function(dynamic) parse) => [
        if (items is List)
          for (final i in items)
            if (parse(i) case final T v) v
      ];

  /// Recently-played items with their `context` (album, playlist,
  /// artist); plays without one keep a null context.
  static List<SpotifyRecentPlay> parseRecentPlays(String body) {
    final items = _tryDecode(body)?['items'];
    if (items is! List) return const [];
    final out = <SpotifyRecentPlay>[];
    for (final i in items) {
      final track = parseTrackItem(i);
      if (track == null || i is! Map) continue;
      final t = i['track'];
      final ctx = i['context'];
      final uri = ctx is Map ? ctx['uri']?.toString() : null;
      out.add(SpotifyRecentPlay(
        track: track,
        contextUri: uri != null && uri.isNotEmpty ? uri : null,
        album: parseAlbum(t is Map ? t['album'] : null),
        playedAt: DateTime.tryParse('${i['played_at'] ?? ''}'),
      ));
    }
    return out;
  }

  static SpotifyUser? parseUser(String body) {
    final j = _tryDecode(body);
    final id = j?['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return SpotifyUser(id: id, name: j?['display_name']?.toString() ?? id);
  }

  /// One page of search results (tracks, albums, artists).
  static SpotifySearchPage parseSearch(String body) {
    final j = _tryDecode(body) ?? const {};
    Map sec(String k) => j[k] is Map ? j[k] as Map : const {};
    bool more(String k) => sec(k)['next'] is String;
    return SpotifySearchPage(
      tracks: _parseList(sec('tracks')['items'], (i) => parseTrackItem(i)),
      albums: _parseList(sec('albums')['items'], parseAlbum),
      artists: _parseList(sec('artists')['items'], parseArtist),
      hasMore: more('tracks') || more('albums') || more('artists'),
    );
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      final d = jsonDecode(body);
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  // ---- cache -----------------------------------------------------------

  static bool _pruned = false;

  static Future<Box?> _cache() async {
    try {
      final box = Hive.isBoxOpen(cacheBox)
          ? Hive.box(cacheBox)
          : await Hive.openBox(cacheBox);
      if (!_pruned) {
        _pruned = true;
        await pruneCache(box, DateTime.now().millisecondsSinceEpoch);
      }
      return box;
    } catch (_) {
      return null;
    }
  }

  /// Drop answers no request can use any more (older than [libraryTtl],
  /// the longest time anything is kept). Done once per launch: the box is
  /// read into memory whole, and every album, artist or playlist opened
  /// used to stay in it until sign-out. Returns how many went.
  @visibleForTesting
  static Future<int> pruneCache(Box box, int nowMs) async {
    bool isStale(Object? v) =>
        v is! Map ||
        v['at'] is! int ||
        !spotifyCacheFresh(v['at'] as int, nowMs, libraryTtl);
    final stale = [
      for (final k in box.keys)
        if (isStale(box.get(k))) k
    ];
    if (stale.isNotEmpty) await box.deleteAll(stale);
    return stale.length;
  }

  /// Forget every cached answer (sign-out, account switch).
  static Future<void> clearCache() async => (await _cache())?.clear();

  // ---- network ---------------------------------------------------------

  /// GET [url]. A 401 refreshes the session once and retries; a 429 waits
  /// as long as Spotify asks (up to [maxInlineWait]) and retries twice;
  /// QUOTA_EXCEEDED stops all calls for [quotaCooldown]. With [ttl], a
  /// cached answer younger than that is used unless [force].
  Future<String> _get(String url, {Duration? ttl, bool force = false}) =>
      _request('GET', url, ttl: ttl, force: force);

  /// [method] [url] with the error handling of [_get]. Writes (PUT,
  /// DELETE) succeed on any 2xx and are never cached.
  Future<String> _request(String method, String url,
      {Duration? ttl, bool force = false, Object? body}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final box =
        _useCache && ttl != null && method == 'GET' ? await _cache() : null;
    if (box != null && !force) {
      final hit = box.get(url);
      if (hit is Map &&
          hit['at'] is int &&
          hit['body'] is String &&
          spotifyCacheFresh(hit['at'] as int, now, ttl!)) {
        return hit['body'] as String;
      }
    }
    if (now < _cooldownUntilMs) {
      throw SpotifyApiException(SpotifyErrorKind.quotaExceeded,
          status: 429,
          retryAfter: Duration(milliseconds: _cooldownUntilMs - now));
    }
    var token = await _token();
    if (token == null) {
      throw const SpotifyApiException(SpotifyErrorKind.signedOut);
    }
    var refreshed = false;
    for (var attempt = 0;; attempt++) {
      final Response res;
      try {
        res = await _dio.request(
          url,
          data: body == null ? null : jsonEncode(body),
          options: Options(
            method: method,
            headers: {
              'Authorization': 'Bearer $token',
              if (body != null) 'Content-Type': 'application/json',
            },
            validateStatus: (_) => true,
          ),
        );
      } on DioException {
        throw const SpotifyApiException(SpotifyErrorKind.network);
      }
      final status = res.statusCode ?? 0;
      if (status == 204) return ''; // nothing to say (e.g. nothing playing)
      if (status == 200 || (method != 'GET' && status >= 200 && status < 300)) {
        final text = '${res.data ?? ''}';
        await box?.put(url, {'at': now, 'body': text});
        return text;
      }
      final kind = classifySpotifyError(status, res.data);
      if (kind == SpotifyErrorKind.signedOut && !refreshed) {
        refreshed = true;
        if (await _refresh()) {
          token = await _token();
          if (token != null) continue;
        }
        throw const SpotifyApiException(SpotifyErrorKind.signedOut,
            status: 401);
      }
      final wait = parseRetryAfter(res.headers.value('retry-after'));
      if (kind == SpotifyErrorKind.quotaExceeded) {
        final cool =
            wait != null && wait > quotaCooldown ? wait : quotaCooldown;
        _cooldownUntilMs =
            DateTime.now().millisecondsSinceEpoch + cool.inMilliseconds;
        throw SpotifyApiException(kind, status: status, retryAfter: cool);
      }
      if (kind == SpotifyErrorKind.rateLimited) {
        final delay = rateLimitDelay(wait, attempt);
        if (attempt < 2 && delay <= maxInlineWait) {
          await _sleep(delay);
          continue;
        }
        throw SpotifyApiException(kind, status: status, retryAfter: delay);
      }
      printINFO('Spotify API $status for $url');
      throw SpotifyApiException(kind, status: status);
    }
  }

  /// Follow `next` links. [maxPages] is a runaway guard, not a product
  /// limit.
  Future<List<T>> _paged<T>(
    String firstUrl,
    List<T> Function(String body) parse, {
    String? nextUnder,
    int maxPages = 100,
    Duration? ttl = libraryTtl,
    bool force = false,
  }) async {
    final out = <T>[];
    String? url = firstUrl;
    var pages = 0;
    while (url != null && pages < maxPages) {
      final body = await _get(url, ttl: ttl, force: force);
      out.addAll(parse(body));
      url = nextPageUrl(body, under: nextUnder);
      pages++;
    }
    if (url != null) {
      printINFO('Spotify: stopped paging at $maxPages pages; list truncated');
    }
    return out;
  }

  /// The signed-in user (id and name).
  Future<SpotifyUser?> fetchMe({bool force = false}) async =>
      parseUser(await _get('$base/me', ttl: libraryTtl, force: force));

  /// The user's own + followed playlists.
  Future<List<SpotifyPlaylistSummary>> fetchPlaylists(
          {int maxPages = 40, bool force = false}) =>
      _paged('$base/me/playlists?limit=$pageSize', parsePlaylistPage,
          maxPages: maxPages, force: force);

  /// Every track in a playlist the user owns or collaborates on (Spotify
  /// returns no contents for others).
  Future<List<SpotifyTrackRef>> fetchPlaylistTracks(String playlistId,
      {bool force = false}) async {
    try {
      return await _paged(
          '$base/playlists/$playlistId/items?limit=$pageSize', parseTrackPage,
          force: force);
    } on SpotifyApiException catch (e) {
      // Older API deployments only know `/tracks`.
      if (e.kind != SpotifyErrorKind.notFound) rethrow;
      return _paged(
          '$base/playlists/$playlistId/tracks?limit=$pageSize', parseTrackPage,
          force: force);
    }
  }

  /// The user's Liked Songs.
  Future<List<SpotifyTrackRef>> fetchLikedSongs({bool force = false}) =>
      _paged('$base/me/tracks?limit=$pageSize', parseTrackPage, force: force);

  /// Saved albums.
  Future<List<SpotifyAlbumSummary>> fetchSavedAlbums({bool force = false}) =>
      _paged('$base/me/albums?limit=$pageSize',
          (b) => _parseList(_tryDecode(b)?['items'], parseAlbum),
          force: force);

  /// An album's tracks, with the album's name and cover filled in.
  Future<List<SpotifyTrackRef>> fetchAlbumTracks(String albumId,
      {bool force = false}) async {
    final body =
        await _get('$base/albums/$albumId', ttl: libraryTtl, force: force);
    final album = _tryDecode(body);
    if (album == null) return const [];
    final tracks = album['tracks'];
    final first = tracks is Map ? tracks['items'] : null;
    final out = <SpotifyTrackRef>[
      for (final t in (first is List ? first : const []))
        if (parseTrackItem(t, album: album) case final r?) r
    ];
    final next = tracks is Map ? tracks['next'] : null;
    if (next is String && next.isNotEmpty) {
      out.addAll(await _paged(next, (b) => parseTrackPage(b, album: album),
          force: force));
    }
    return out;
  }

  /// Followed artists (cursor-paged under `artists`).
  Future<List<SpotifyArtistSummary>> fetchFollowedArtists(
          {bool force = false}) =>
      _paged('$base/me/following?type=artist&limit=$pageSize', (b) {
        final artists = _tryDecode(b)?['artists'];
        return _parseList(
            artists is Map ? artists['items'] : null, parseArtist);
      }, nextUnder: 'artists', force: force);

  /// An artist's albums and singles.
  Future<List<SpotifyAlbumSummary>> fetchArtistAlbums(String artistId,
          {bool force = false}) =>
      _paged(
          '$base/artists/$artistId/albums?include_groups=album,single'
          '&limit=$searchPageSize',
          (b) => _parseList(_tryDecode(b)?['items'], parseAlbum),
          maxPages: 10,
          force: force);

  /// Top tracks; [timeRange] `short_term` (about four weeks),
  /// `medium_term` (six months, the default) or `long_term`.
  Future<List<SpotifyTrackRef>> fetchTopTracks(
          {bool force = false,
          String timeRange = 'medium_term',
          int limit = pageSize}) =>
      _paged('$base/me/top/tracks?limit=$limit&time_range=$timeRange',
          parseTrackPage,
          maxPages: 1, force: force);

  /// Top artists over roughly the last six months.
  Future<List<SpotifyArtistSummary>> fetchTopArtists({bool force = false}) =>
      _paged('$base/me/top/artists?limit=$pageSize&time_range=medium_term',
          (b) => _parseList(_tryDecode(b)?['items'], parseArtist),
          maxPages: 1, force: force);

  /// The last 50 plays (kept for a few minutes only).
  Future<List<SpotifyTrackRef>> fetchRecentlyPlayed({bool force = false}) =>
      _paged('$base/me/player/recently-played?limit=$pageSize', parseTrackPage,
          maxPages: 1, ttl: const Duration(minutes: 5), force: force);

  /// The last 50 plays with the album, playlist or artist each was played
  /// from, newest first.
  Future<List<SpotifyRecentPlay>> fetchRecentPlays({bool force = false}) =>
      _paged('$base/me/player/recently-played?limit=$pageSize',
          parseRecentPlays,
          maxPages: 1, ttl: const Duration(minutes: 5), force: force);

  /// The newest Liked Songs, one page.
  Future<List<SpotifyTrackRef>> fetchRecentlyLiked(
          {int limit = 20, bool force = false}) =>
      _paged('$base/me/tracks?limit=$limit', parseTrackPage,
          maxPages: 1, force: force);

  /// One page of search results (at most 10 of each kind).
  Future<SpotifySearchPage> search(String query, {int offset = 0}) async {
    final uri = Uri.parse('$base/search').replace(queryParameters: {
      'q': query,
      'type': 'track,album,artist',
      'limit': '$searchPageSize',
      'offset': '$offset',
    });
    return parseSearch(await _get(uri.toString()));
  }

  /// Songs only, for finding a Spotify track for a Riff song.
  Future<List<SpotifyTrackRef>> searchTracks(String query,
      {int limit = 5}) async {
    final uri = Uri.parse('$base/search').replace(queryParameters: {
      'q': query,
      'type': 'track',
      'limit': '${limit.clamp(1, searchPageSize)}',
    });
    return parseSearch(await _get(uri.toString())).tracks;
  }

  /// Most ids per library write.
  static const libraryBatch = 40;

  /// Add tracks to Liked Songs (`PUT /me/library` with `spotify:track:`
  /// URIs; the older `PUT /me/tracks` where that isn't known). Needs the
  /// `user-library-modify` scope.
  Future<void> saveTracks(List<String> trackIds) =>
      _libraryWrite('PUT', trackIds);

  /// Remove tracks from Liked Songs.
  Future<void> removeTracks(List<String> trackIds) =>
      _libraryWrite('DELETE', trackIds);

  Future<void> _libraryWrite(String method, List<String> ids) async {
    for (var i = 0; i < ids.length; i += libraryBatch) {
      final batch = ids.sublist(i, (i + libraryBatch).clamp(0, ids.length));
      try {
        await _request(
            method,
            Uri.parse('$base/me/library').replace(queryParameters: {
              'uris': batch.map((id) => 'spotify:track:$id').join(','),
            }).toString());
      } on SpotifyApiException catch (e) {
        if (e.kind != SpotifyErrorKind.notFound) rethrow;
        await _request(
            method,
            Uri.parse('$base/me/tracks')
                .replace(queryParameters: {'ids': batch.join(',')}).toString());
      }
    }
  }

  // ── Spotify Connect (Premium) ──────────────────────────────────────

  /// Devices that can play: the Spotify app on a phone or computer, a
  /// speaker. Needs `user-read-playback-state`.
  Future<List<SpotifyDevice>> fetchDevices() async =>
      parseDevices(await _get('$base/me/player/devices'));

  /// What's playing, and where; null when nothing is.
  Future<SpotifyPlaybackState?> fetchPlaybackState() async =>
      parsePlaybackState(await _get('$base/me/player'),
          parseTrack: (i) => parseTrackItem(i));

  /// Move playback to [deviceId]. Needs `user-modify-playback-state`, as
  /// do the controls below.
  Future<void> transferPlayback(String deviceId, {bool play = true}) =>
      _request('PUT', '$base/me/player', body: {
        'device_ids': [deviceId],
        'play': play,
      });

  String _onDevice(String path, String? deviceId,
          [Map<String, String> more = const {}]) =>
      Uri.parse('$base/me/player/$path').replace(queryParameters: {
        if (deviceId != null) 'device_id': deviceId,
        ...more,
      }).toString();

  /// Start [body] (see `connectPlayBody`), or carry on when it's null.
  Future<void> play({String? deviceId, Map<String, dynamic>? body}) =>
      _request('PUT', _onDevice('play', deviceId), body: body);

  Future<void> pause({String? deviceId}) =>
      _request('PUT', _onDevice('pause', deviceId));

  Future<void> next({String? deviceId}) =>
      _request('POST', _onDevice('next', deviceId));

  Future<void> previous({String? deviceId}) =>
      _request('POST', _onDevice('previous', deviceId));

  Future<void> seek(int positionMs, {String? deviceId}) => _request(
      'PUT',
      _onDevice('seek', deviceId,
          {'position_ms': '${positionMs.clamp(0, 1 << 31)}'}));

  Future<void> setVolume(int percent, {String? deviceId}) => _request(
      'PUT',
      _onDevice(
          'volume', deviceId, {'volume_percent': '${percent.clamp(0, 100)}'}));

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

/// One play from `recently-played`.
class SpotifyRecentPlay {
  const SpotifyRecentPlay(
      {required this.track, this.contextUri, this.album, this.playedAt});
  final SpotifyTrackRef track;

  /// `spotify:album:…`, `spotify:playlist:…`, `spotify:artist:…`.
  final String? contextUri;

  /// The track's album (for album contexts: the context itself).
  final SpotifyAlbumSummary? album;
  final DateTime? playedAt;
}

class SpotifyUser {
  const SpotifyUser({required this.id, required this.name});
  final String id;
  final String name;
}

/// A playlist as listed on the user's account, before its tracks are fetched.
class SpotifyPlaylistSummary {
  const SpotifyPlaylistSummary({
    required this.id,
    required this.name,
    this.coverUrl,
    this.trackCount = 0,
    this.ownerId,
    this.ownerName,
    this.collaborative = false,
  });

  final String id;
  final String name;
  final String? coverUrl;
  final int trackCount;
  final String? ownerId;
  final String? ownerName;
  final bool collaborative;

  /// Spotify returns the contents only of playlists the user owns or
  /// collaborates on.
  bool readableBy(String? userId) =>
      collaborative || (userId != null && ownerId == userId);
}

class SpotifyAlbumSummary {
  const SpotifyAlbumSummary({
    required this.id,
    required this.name,
    this.artists = '',
    this.coverUrl,
    this.year,
    this.trackCount = 0,
    this.releaseDate,
  });
  final String id;
  final String name;
  final String artists;
  final String? coverUrl;
  final String? year;
  final int trackCount;

  /// `release_date` as Spotify sends it: `2026`, `2026-09` or
  /// `2026-09-30` (precision varies).
  final String? releaseDate;
}

class SpotifyArtistSummary {
  const SpotifyArtistSummary(
      {required this.id,
      required this.name,
      this.imageUrl,
      this.genres = const []});
  final String id;
  final String name;
  final String? imageUrl;

  /// Top and followed artists carry genres; used by Spotify radio.
  final List<String> genres;
}

class SpotifySearchPage {
  const SpotifySearchPage({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.hasMore = false,
  });
  final List<SpotifyTrackRef> tracks;
  final List<SpotifyAlbumSummary> albums;
  final List<SpotifyArtistSummary> artists;
  final bool hasMore;
}
