import 'dart:convert';

import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../utils/helper.dart';
import 'spotify_api_service.dart';
import 'spotify_auth_service.dart';
import 'spotify_import_service.dart';

/// Spotify shelves for the Home tab, built from the official Web API only.
///
/// Spotify no longer gives apps its recommendations, Daily Mixes, Discover
/// Weekly, Release Radar or editorial playlists (blocked for Development
/// Mode apps since November 2024 and February 2026), so the shelves are
/// made from what is still allowed: your recent plays, top tracks and
/// artists, followed artists' new releases, playlists and Liked Songs, plus
/// a "your Spotify mix" card that plays Riff's own Spotify radio. Songs are
/// matched to YouTube Music only when played.

/// Shelf ids, also their order on Home.
enum SpotifyShelfId {
  jumpBackIn,
  onRepeat,
  newReleases,
  topArtists,
  playlists,
  recentlyLiked,
}

extension SpotifyShelfTitle on SpotifyShelfId {
  String get titleKey => switch (this) {
        SpotifyShelfId.jumpBackIn => 'spotifyHomeJumpBackIn',
        SpotifyShelfId.onRepeat => 'spotifyHomeOnRepeat',
        SpotifyShelfId.newReleases => 'spotifyHomeNewReleases',
        SpotifyShelfId.topArtists => 'spotifyHomeTopArtists',
        SpotifyShelfId.playlists => 'spotifyHomePlaylists',
        SpotifyShelfId.recentlyLiked => 'spotifyHomeRecentlyLiked',
      };
}

/// A playlist card; [readable] when Spotify shares its songs with the
/// user (owned or collaborative).
class SpotifyHomePlaylist {
  const SpotifyHomePlaylist(this.playlist, {required this.readable});
  final SpotifyPlaylistSummary playlist;
  final bool readable;
}

/// The "your Spotify mix" card: plays a radio from your top tracks, recent
/// plays and Liked Songs. [covers] are a few top-track covers for its art.
class SpotifyTasteMix {
  const SpotifyTasteMix(this.covers);
  final List<String> covers;
}

class SpotifyShelf {
  const SpotifyShelf(this.id, this.items);
  final SpotifyShelfId id;

  /// [SpotifyTrackRef], [SpotifyAlbumSummary], [SpotifyHomePlaylist],
  /// [SpotifyArtistSummary] or [SpotifyTasteMix].
  final List<Object> items;
}

// ── Pure helpers (tested) ──────────────────────────────────────────────

/// Whether [releaseDate] (`yyyy`, `yyyy-mm` or `yyyy-mm-dd`) falls within
/// [days] before [now]. Year-only dates never count (too coarse to call
/// new); month-only dates count from the month's first day.
bool releasedWithin(String? releaseDate, DateTime now, {int days = 28}) {
  if (releaseDate == null) return false;
  final parts = releaseDate.split('-');
  if (parts.length < 2) return false;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = parts.length > 2 ? int.tryParse(parts[2]) : 1;
  if (y == null || m == null || d == null) return false;
  final date = DateTime(y, m, d);
  final from =
      DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
  return !date.isBefore(from) && !date.isAfter(now);
}

/// New albums and singles from [byArtist] (artist → their releases), the
/// newest first, each once.
List<SpotifyAlbumSummary> newReleasesFrom(
    Iterable<List<SpotifyAlbumSummary>> byArtist, DateTime now,
    {int days = 28}) {
  final seen = <String>{};
  final out = [
    for (final list in byArtist)
      for (final a in list)
        if (releasedWithin(a.releaseDate, now, days: days) && seen.add(a.id)) a
  ];
  out.sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
  return out;
}

/// Albums, playlists and artists you played from, newest first, each once.
/// Playlist and artist contexts carry no name in `recently-played`, so they
/// are looked up in [playlists] / [artists] and left out when unknown.
List<Object> jumpBackInFrom(
  List<SpotifyRecentPlay> plays, {
  Map<String, SpotifyHomePlaylist> playlists = const {},
  Map<String, SpotifyArtistSummary> artists = const {},
  int max = 12,
}) {
  final seen = <String>{};
  final out = <Object>[];
  for (final p in plays) {
    if (out.length >= max) break;
    final uri = p.contextUri;
    if (uri == null || !seen.add(uri)) continue;
    final parts = uri.split(':');
    if (parts.length != 3) continue;
    final (type, id) = (parts[1], parts[2]);
    switch (type) {
      case 'album':
        final album = p.album;
        if (album != null && album.id == id) out.add(album);
      case 'playlist':
        if (playlists[id] case final pl?) out.add(pl);
      case 'artist':
        if (artists[id] case final a?) out.add(a);
    }
  }
  return out;
}

/// The next [count] of [total] followed artists to check for releases,
/// starting at [offset] and wrapping, so each refresh looks at others.
List<int> rotatingWindow(int total, int offset, int count) {
  if (total <= 0) return const [];
  final n = count.clamp(0, total);
  return [for (var i = 0; i < n; i++) (offset + i) % total];
}

// ── Cache (JSON in AppPrefs) ────────────────────────────────────────────

Map<String, dynamic> _trackJson(SpotifyTrackRef t) => {
      'id': t.id,
      'title': t.title,
      'artists': t.artists,
      if (t.durationMs != null) 'ms': t.durationMs,
      if (t.isrc != null) 'isrc': t.isrc,
      if (t.album != null) 'album': t.album,
      if (t.artUrl != null) 'art': t.artUrl,
    };

Map<String, dynamic> _albumJson(SpotifyAlbumSummary a) => {
      'id': a.id,
      'name': a.name,
      'artists': a.artists,
      if (a.coverUrl != null) 'art': a.coverUrl,
      if (a.year != null) 'year': a.year,
      if (a.releaseDate != null) 'date': a.releaseDate,
      'n': a.trackCount,
    };

Map<String, dynamic>? spotifyHomeItemToJson(Object item) => switch (item) {
      SpotifyTrackRef t => {'t': 'track', ..._trackJson(t)},
      SpotifyAlbumSummary a => {'t': 'album', ..._albumJson(a)},
      SpotifyArtistSummary a => {
          't': 'artist',
          'id': a.id,
          'name': a.name,
          if (a.imageUrl != null) 'art': a.imageUrl,
        },
      SpotifyHomePlaylist p => {
          't': 'playlist',
          'id': p.playlist.id,
          'name': p.playlist.name,
          if (p.playlist.coverUrl != null) 'art': p.playlist.coverUrl,
          'n': p.playlist.trackCount,
          if (p.playlist.ownerName != null) 'owner': p.playlist.ownerName,
          'readable': p.readable,
        },
      SpotifyTasteMix m => {'t': 'mix', 'covers': m.covers},
      _ => null,
    };

Object? spotifyHomeItemFromJson(dynamic raw) {
  if (raw is! Map) return null;
  String? s(String k) => raw[k] is String ? raw[k] as String : null;
  final id = s('id') ?? '';
  switch (raw['t']) {
    case 'track':
      return SpotifyTrackRef(
          id: id,
          title: s('title') ?? '',
          artists: s('artists') ?? '',
          durationMs: raw['ms'] is int ? raw['ms'] as int : null,
          isrc: s('isrc'),
          album: s('album'),
          artUrl: s('art'));
    case 'album':
      return SpotifyAlbumSummary(
          id: id,
          name: s('name') ?? '',
          artists: s('artists') ?? '',
          coverUrl: s('art'),
          year: s('year'),
          releaseDate: s('date'),
          trackCount: raw['n'] is int ? raw['n'] as int : 0);
    case 'artist':
      return SpotifyArtistSummary(
          id: id, name: s('name') ?? '', imageUrl: s('art'));
    case 'playlist':
      return SpotifyHomePlaylist(
          SpotifyPlaylistSummary(
              id: id,
              name: s('name') ?? '',
              coverUrl: s('art'),
              trackCount: raw['n'] is int ? raw['n'] as int : 0,
              ownerName: s('owner')),
          readable: raw['readable'] == true);
    case 'mix':
      final covers = raw['covers'];
      return SpotifyTasteMix(
          [if (covers is List) ...covers.whereType<String>()]);
  }
  return null;
}

String encodeSpotifyShelves(List<SpotifyShelf> shelves) => jsonEncode([
      for (final s in shelves)
        {
          'id': s.id.name,
          'items': [
            for (final i in s.items)
              if (spotifyHomeItemToJson(i) case final j?) j
          ],
        }
    ]);

List<SpotifyShelf> decodeSpotifyShelves(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final s in list)
        if (s is Map &&
            SpotifyShelfId.values.any((v) => v.name == s['id']) &&
            s['items'] is List)
          SpotifyShelf(
            SpotifyShelfId.values.firstWhere((v) => v.name == s['id']),
            [
              for (final i in s['items'] as List)
                if (spotifyHomeItemFromJson(i) case final o?) o
            ],
          )
    ];
  } catch (_) {
    return const [];
  }
}

// ── Source ──────────────────────────────────────────────────────────────

/// Loads and keeps the Spotify shelves. Cached shelves show at once; a
/// refresh runs in the background when they are older than [ttl].
class SpotifyHome {
  SpotifyHome._();

  static const cacheKey = 'spotifyHomeCache';
  static const cacheAtKey = 'spotifyHomeCacheAt';
  static const unsupportedKey = 'spotifyHomeUnsupported';
  static const artistOffsetKey = 'spotifyHomeArtistOffset';

  static const ttl = Duration(minutes: 30);

  /// Followed artists checked for new releases per refresh.
  static const artistsPerRefresh = 12;

  static final shelves = <SpotifyShelf>[].obs;

  /// The Spotify session ended: Home shows a "Reconnect" card.
  static final needsReconnect = false.obs;

  static bool _loaded = false;
  static Future<void>? _running;

  /// Test hook.
  static SpotifyApiService Function() apiFactory =
      () => SpotifyApiService(auth: SpotifyAuthService());

  static Box? get _box =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// Shows the cached shelves (once).
  static void ensureLoaded() {
    if (_loaded) return;
    final box = _box;
    if (box == null) return;
    _loaded = true;
    if (!SpotifyAuthService.isConnected) return;
    shelves.assignAll(decodeSpotifyShelves(box.get(cacheKey) as String?));
  }

  /// How long a shelf whose endpoint answered 403/404 is left alone
  /// (a lapsed Premium or a removed endpoint; tried again after this).
  static const unsupportedFor = Duration(days: 7);

  static Set<String> get _unsupported {
    final v = _box?.get(unsupportedKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      if (v is Map)
        for (final e in v.entries)
          if (e.value is int &&
              now - (e.value as int) < unsupportedFor.inMilliseconds)
            '${e.key}'
    };
  }

  static void _markUnsupported(SpotifyShelfId id) {
    final v = _box?.get(unsupportedKey);
    _box?.put(unsupportedKey, {
      if (v is Map) ...v,
      id.name: DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Forget everything (sign-out).
  static Future<void> clear() async {
    shelves.clear();
    needsReconnect.value = false;
    await _box?.delete(cacheKey);
    await _box?.delete(cacheAtKey);
    await _box?.delete(unsupportedKey);
  }

  /// Refresh when stale (or [force]); one refresh at a time.
  static Future<void> refresh({bool force = false}) {
    ensureLoaded();
    if (!SpotifyAuthService.isConnected) {
      if (shelves.isNotEmpty) shelves.clear();
      return Future.value();
    }
    final at = (_box?.get(cacheAtKey) as int?) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    if (!force && shelves.isNotEmpty && age < ttl.inMilliseconds) {
      return Future.value();
    }
    return _running ??= _load(force).whenComplete(() => _running = null);
  }

  static Future<void> _load(bool force) async {
    final api = apiFactory();
    final skip = _unsupported;
    var signedOut = false;

    /// Runs one shelf's calls; a 403/404 means this app may not use that
    /// endpoint, so the shelf is switched off for good.
    Future<List<T>> get<T>(
        SpotifyShelfId shelf, Future<List<T>> Function() f) async {
      if (skip.contains(shelf.name) || signedOut) return <T>[];
      try {
        return await f();
      } on SpotifyApiException catch (e) {
        switch (e.kind) {
          case SpotifyErrorKind.signedOut:
            signedOut = true;
          case SpotifyErrorKind.forbidden:
          case SpotifyErrorKind.notFound:
            _markUnsupported(shelf);
          default:
            printINFO('Spotify home ${shelf.name}: ${e.kind.name}');
        }
        return <T>[];
      } catch (e) {
        printINFO('Spotify home ${shelf.name}: $e');
        return <T>[];
      }
    }

    final me = await (() async {
      try {
        return await api.fetchMe();
      } on SpotifyApiException catch (e) {
        if (e.kind == SpotifyErrorKind.signedOut) signedOut = true;
        return null;
      } catch (_) {
        return null;
      }
    })();
    if (signedOut) {
      needsReconnect.value = true;
      return;
    }

    final onRepeat = await get(
        SpotifyShelfId.onRepeat,
        () => api.fetchTopTracks(
            timeRange: 'short_term', limit: 20, force: force));
    final topArtists = await get(
        SpotifyShelfId.topArtists, () => api.fetchTopArtists(force: force));
    final playlists = await get(SpotifyShelfId.playlists,
        () => api.fetchPlaylists(maxPages: 2, force: force));
    final homePlaylists = [
      for (final p in playlists)
        SpotifyHomePlaylist(p, readable: p.readableBy(me?.id))
    ];
    final followed = await get(SpotifyShelfId.newReleases,
        () => api.fetchFollowedArtists(force: force));
    final recent = await get(
        SpotifyShelfId.jumpBackIn, () => api.fetchRecentPlays(force: force));
    final liked = await get(SpotifyShelfId.recentlyLiked,
        () => api.fetchRecentlyLiked(force: force));

    // New releases: a rotating handful of followed artists per refresh.
    final offset = (_box?.get(artistOffsetKey) as int?) ?? 0;
    final window = rotatingWindow(followed.length, offset, artistsPerRefresh);
    final releases = <List<SpotifyAlbumSummary>>[];
    for (final i in window) {
      releases.add(await get(SpotifyShelfId.newReleases,
          () => api.fetchArtistAlbums(followed[i].id)));
    }
    if (followed.isNotEmpty) {
      await _box?.put(
          artistOffsetKey, (offset + window.length) % followed.length);
    }

    if (signedOut) {
      needsReconnect.value = true;
      return;
    }
    needsReconnect.value = false;

    final mixCovers = [
      for (final t in onRepeat)
        if (t.artUrl != null) t.artUrl!
    ].take(4).toList();
    final next = <SpotifyShelf>[
      SpotifyShelf(
          SpotifyShelfId.jumpBackIn,
          jumpBackInFrom(recent, playlists: {
            for (final p in homePlaylists) p.playlist.id: p
          }, artists: {
            for (final a in [...topArtists, ...followed]) a.id: a
          })),
      SpotifyShelf(SpotifyShelfId.onRepeat, [
        if (onRepeat.isNotEmpty) SpotifyTasteMix(mixCovers),
        ...onRepeat,
      ]),
      SpotifyShelf(SpotifyShelfId.newReleases,
          newReleasesFrom(releases, DateTime.now()).take(20).toList()),
      SpotifyShelf(SpotifyShelfId.topArtists, topArtists.take(20).toList()),
      SpotifyShelf(SpotifyShelfId.playlists, homePlaylists.take(20).toList()),
      SpotifyShelf(SpotifyShelfId.recentlyLiked, liked.take(20).toList()),
    ].where((s) => s.items.isNotEmpty).toList();

    // A failed refresh keeps what was there.
    if (next.isEmpty && shelves.isNotEmpty) return;
    shelves.assignAll(next);
    await _box?.put(cacheKey, encodeSpotifyShelves(next));
    await _box?.put(cacheAtKey, DateTime.now().millisecondsSinceEpoch);
  }
}
