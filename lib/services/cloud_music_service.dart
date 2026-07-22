import 'dart:convert';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../utils/helper.dart';

/// A song on the self-hosted server (Subsonic `child` object).
class CloudSong {
  CloudSong({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.albumId,
    this.coverArt,
    this.duration,
    this.track,
  });

  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String? albumId;
  final String? coverArt;
  final Duration? duration;
  final int? track;

  static CloudSong? fromJson(dynamic j) {
    if (j is! Map || j['id'] == null) return null;
    final durSec = (j['duration'] as num?)?.toInt();
    return CloudSong(
      id: j['id'].toString(),
      title: (j['title'] ?? j['name'] ?? 'Untitled').toString(),
      artist: j['artist']?.toString(),
      album: j['album']?.toString(),
      albumId: j['albumId']?.toString(),
      coverArt: j['coverArt']?.toString(),
      duration: durSec != null && durSec > 0 ? Duration(seconds: durSec) : null,
      track: (j['track'] as num?)?.toInt(),
    );
  }
}

/// An album row from `getAlbumList2` / `search3`.
class CloudAlbum {
  CloudAlbum({
    required this.id,
    required this.name,
    this.artist,
    this.coverArt,
    this.songCount,
    this.year,
  });

  final String id;
  final String name;
  final String? artist;
  final String? coverArt;
  final int? songCount;
  final int? year;

  static CloudAlbum? fromJson(dynamic j) {
    if (j is! Map || j['id'] == null) return null;
    return CloudAlbum(
      id: j['id'].toString(),
      name: (j['name'] ?? j['title'] ?? j['album'] ?? 'Album').toString(),
      artist: j['artist']?.toString(),
      coverArt: j['coverArt']?.toString(),
      songCount: (j['songCount'] as num?)?.toInt(),
      year: (j['year'] as num?)?.toInt(),
    );
  }
}

/// A playlist row from `getPlaylists`.
class CloudPlaylist {
  CloudPlaylist({
    required this.id,
    required this.name,
    this.coverArt,
    this.songCount,
    this.duration,
  });

  final String id;
  final String name;
  final String? coverArt;
  final int? songCount;
  final Duration? duration;

  static CloudPlaylist? fromJson(dynamic j) {
    if (j is! Map || j['id'] == null) return null;
    final durSec = (j['duration'] as num?)?.toInt();
    return CloudPlaylist(
      id: j['id'].toString(),
      name: (j['name'] ?? 'Playlist').toString(),
      coverArt: j['coverArt']?.toString(),
      songCount: (j['songCount'] as num?)?.toInt(),
      duration: durSec != null && durSec > 0 ? Duration(seconds: durSec) : null,
    );
  }
}

/// An album or playlist opened with its tracks, ready for playback.
class CloudCollection {
  CloudCollection({
    required this.id,
    required this.name,
    this.subtitle,
    this.coverArt,
    this.songs = const [],
  });

  final String id;
  final String name;
  final String? subtitle;
  final String? coverArt;
  final List<CloudSong> songs;
}

/// Combined `search3` results.
class CloudSearchResult {
  CloudSearchResult({this.songs = const [], this.albums = const []});
  final List<CloudSong> songs;
  final List<CloudAlbum> albums;
}

/// Subsonic API error (status != ok), with the protocol error code.
class CloudApiException implements Exception {
  CloudApiException(this.code, this.message);
  final int? code;
  final String message;

  /// 40 = wrong username/password, 41 = token auth not supported for user.
  bool get isAuthError => code == 40 || code == 41;

  @override
  String toString() => message.isEmpty ? 'Server error ($code)' : message;
}

/// Self-hosted music server client (Cloud tab), inspired by Resonus
/// (https://github.com/juananzzz/resonus).
///
/// Speaks the Subsonic REST API (`/rest/*.view`), so it works with
/// Navidrome, OpenSubsonic, Airsonic-Advanced, Gonic, Ampache and friends:
/// login, browse albums/playlists, random songs, search, and stream through
/// Riff's player via tokenized URLs — same pattern as the Audiobookshelf
/// integration.
class CloudMusicService extends GetxService {
  static const _apiVersion = '1.16.1';
  static const _clientName = 'Riff';
  static const _albumPageSize = 100;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'user-agent': 'Riff-mobile/1.0 (Cloud; Subsonic-compatible)',
    },
  ));

  final isConnected = false.obs;
  final host = ''.obs;
  final username = ''.obs;
  final isLoading = false.obs;
  final statusMessage = ''.obs;

  /// Albums tab content (paged, alphabetical).
  final albums = <CloudAlbum>[].obs;
  final albumsHaveMore = false.obs;

  /// Playlists tab content.
  final playlists = <CloudPlaylist>[].obs;

  /// Songs tab content (a random slice of the library, re-rollable).
  final songs = <CloudSong>[].obs;

  String _password = '';

  /// Servers that can't verify the salted token (e.g. LDAP-backed users)
  /// get the legacy hex-encoded password auth instead, like Resonus does.
  bool _legacyAuth = false;

  Box get _prefs => Hive.box('AppPrefs');

  @override
  void onInit() {
    super.onInit();
    _restoreSession();
  }

  void _restoreSession() {
    final cfg = _prefs.get('cloudMusic');
    if (cfg is! Map) return;
    host.value = (cfg['host'] ?? '').toString();
    username.value = (cfg['username'] ?? '').toString();
    _password = (cfg['password'] ?? '').toString();
    _legacyAuth = cfg['legacyAuth'] == true;
    if (host.value.isNotEmpty &&
        username.value.isNotEmpty &&
        _password.isNotEmpty) {
      isConnected.value = true;
      // Lazy refresh of the library views
      Future.microtask(() async {
        try {
          await refreshLibrary();
        } catch (e) {
          printERROR('Cloud restore failed: $e');
        }
      });
    }
  }

  void _persist() {
    _prefs.put('cloudMusic', {
      'host': host.value,
      'username': username.value,
      'password': _password,
      'legacyAuth': _legacyAuth,
    });
  }

  String _normalizeHost(String raw) {
    var h = raw.trim();
    while (h.endsWith('/')) {
      h = h.substring(0, h.length - 1);
    }
    if (!h.startsWith('http://') && !h.startsWith('https://')) {
      h = 'https://$h';
    }
    return h;
  }

  String _makeSalt() {
    final rnd = Random.secure();
    const chars = '0123456789abcdef';
    return List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// Auth query params sent with every request (Subsonic scheme, as in
  /// Resonus): `u` + salted md5 token, or `p=enc:<hex>` for legacy servers.
  Map<String, String> _authParams() {
    if (_legacyAuth) {
      final hexPass = utf8
          .encode(_password)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      return {
        'u': username.value,
        'p': 'enc:$hexPass',
        'v': _apiVersion,
        'c': _clientName,
        'f': 'json',
      };
    }
    final salt = _makeSalt();
    final token = md5.convert(utf8.encode('$_password$salt')).toString();
    return {
      'u': username.value,
      't': token,
      's': salt,
      'v': _apiVersion,
      'c': _clientName,
      'f': 'json',
    };
  }

  /// GET `/rest/<endpoint>` and unwrap the `subsonic-response` envelope,
  /// throwing [CloudApiException] when the server reports an error.
  Future<Map> _request(String endpoint,
      [Map<String, dynamic>? params]) async {
    _ensureConfigured();
    final res = await _dio.get(
      '${host.value}/rest/$endpoint',
      queryParameters: {
        ..._authParams(),
        ...?params?.map((k, v) => MapEntry(k, v.toString())),
      },
    );
    var data = res.data;
    if (data is String && data.isNotEmpty) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        throw CloudApiException(null, 'Unexpected server response');
      }
    }
    final body = data is Map ? data['subsonic-response'] : null;
    if (body is! Map) {
      throw CloudApiException(null, 'Not a Subsonic-compatible server');
    }
    if (body['status'] != 'ok') {
      final err = body['error'];
      throw CloudApiException(
        err is Map ? (err['code'] as num?)?.toInt() : null,
        err is Map ? (err['message'] ?? '').toString() : '',
      );
    }
    return body;
  }

  /// Connect and remember the server. Tries token auth first, then falls
  /// back to legacy password auth when the server rejects tokens (code 41).
  Future<void> login({
    required String serverUrl,
    required String user,
    required String password,
  }) async {
    isLoading.value = true;
    statusMessage.value = '';
    try {
      host.value = _normalizeHost(serverUrl);
      username.value = user;
      _password = password;
      _legacyAuth = false;
      try {
        await _request('ping.view');
      } on CloudApiException catch (e) {
        if (e.code == 41) {
          _legacyAuth = true;
          await _request('ping.view');
        } else {
          rethrow;
        }
      }
      isConnected.value = true;
      _persist();
      statusMessage.value = '';
      try {
        await refreshLibrary();
      } catch (e) {
        // Connected fine; library views can be retried from the UI.
        printERROR('Cloud initial fetch failed: $e');
      }
    } on CloudApiException catch (e) {
      isConnected.value = false;
      statusMessage.value =
          e.isAuthError ? 'cloudLoginFailed'.tr : e.toString();
      rethrow;
    } on DioException catch (e) {
      isConnected.value = false;
      statusMessage.value = e.message ?? 'networkError'.tr;
      rethrow;
    } catch (e) {
      isConnected.value = false;
      statusMessage.value = e.toString();
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    isConnected.value = false;
    host.value = '';
    username.value = '';
    _password = '';
    _legacyAuth = false;
    albums.clear();
    playlists.clear();
    songs.clear();
    albumsHaveMore.value = false;
    statusMessage.value = '';
    _prefs.delete('cloudMusic');
  }

  /// Refresh all three library views in one go.
  Future<void> refreshLibrary() async {
    await Future.wait([
      fetchAlbums(),
      fetchPlaylists(),
      fetchRandomSongs(),
    ]);
  }

  /// Alphabetical album list (`getAlbumList2`), paged via [loadMore].
  Future<void> fetchAlbums({bool loadMore = false}) async {
    final offset = loadMore ? albums.length : 0;
    final body = await _request('getAlbumList2.view', {
      'type': 'alphabeticalByName',
      'size': _albumPageSize,
      'offset': offset,
    });
    final page = _list(body['albumList2'], 'album')
        .map(CloudAlbum.fromJson)
        .whereType<CloudAlbum>()
        .toList();
    if (loadMore) {
      albums.addAll(page);
    } else {
      albums.assignAll(page);
    }
    albumsHaveMore.value = page.length >= _albumPageSize;
  }

  Future<void> fetchPlaylists() async {
    final body = await _request('getPlaylists.view');
    playlists.assignAll(_list(body['playlists'], 'playlist')
        .map(CloudPlaylist.fromJson)
        .whereType<CloudPlaylist>()
        .toList());
  }

  /// Re-roll the Songs tab with a random slice of the library.
  Future<void> fetchRandomSongs({int size = 100}) async {
    final body = await _request('getRandomSongs.view', {'size': size});
    songs.assignAll(_list(body['randomSongs'], 'song')
        .map(CloudSong.fromJson)
        .whereType<CloudSong>()
        .toList());
  }

  /// Album with its tracks (`getAlbum`).
  Future<CloudCollection> fetchAlbum(String id) async {
    final body = await _request('getAlbum.view', {'id': id});
    final a = body['album'];
    final map = a is Map ? a : const {};
    final tracks = _list(a, 'song')
        .map(CloudSong.fromJson)
        .whereType<CloudSong>()
        .toList();
    return CloudCollection(
      id: id,
      name: (map['name'] ?? map['title'] ?? 'Album').toString(),
      subtitle: map['artist']?.toString(),
      coverArt: map['coverArt']?.toString(),
      songs: tracks,
    );
  }

  /// Playlist with its tracks (`getPlaylist`).
  Future<CloudCollection> fetchPlaylist(String id) async {
    final body = await _request('getPlaylist.view', {'id': id});
    final p = body['playlist'];
    final map = p is Map ? p : const {};
    final tracks = _list(p, 'entry')
        .map(CloudSong.fromJson)
        .whereType<CloudSong>()
        .toList();
    return CloudCollection(
      id: id,
      name: (map['name'] ?? 'Playlist').toString(),
      subtitle: map['owner']?.toString(),
      coverArt: map['coverArt']?.toString(),
      songs: tracks,
    );
  }

  /// Unified server search (`search3`): songs + albums.
  Future<CloudSearchResult> search(String query) async {
    final body = await _request('search3.view', {
      'query': query,
      'songCount': 100,
      'albumCount': 40,
      'artistCount': 0,
    });
    final result = body['searchResult3'];
    return CloudSearchResult(
      songs: _list(result, 'song')
          .map(CloudSong.fromJson)
          .whereType<CloudSong>()
          .toList(),
      albums: _list(result, 'album')
          .map(CloudAlbum.fromJson)
          .whereType<CloudAlbum>()
          .toList(),
    );
  }

  /// Tokenized stream URL for the player (`stream`).
  String streamUrl(String songId) => _restUrl('stream.view', {'id': songId});

  /// Cover art URL, or empty string when the item has none.
  String coverUrl(String? coverArt, {int size = 400}) {
    if (coverArt == null || coverArt.isEmpty || isConnected.isFalse) {
      return '';
    }
    return _restUrl('getCoverArt.view', {'id': coverArt, 'size': '$size'});
  }

  String _restUrl(String endpoint, Map<String, String> params) {
    _ensureConfigured();
    return Uri.parse('${host.value}/rest/$endpoint')
        .replace(queryParameters: {..._authParams(), ...params}).toString();
  }

  /// Convert a server song into a [MediaItem] Riff's player can stream.
  /// IDs use the `cloud_` prefix so [MyAudioHandler.checkNGetUrl] plays the
  /// direct URL instead of resolving a YouTube stream.
  MediaItem toMediaItem(CloudSong s) {
    final cover = coverUrl(s.coverArt);
    final artist = s.artist ?? host.value;
    return MediaItem(
      id: 'cloud_${s.id}',
      title: s.title,
      album: s.album,
      artist: artist,
      duration: s.duration,
      artUri: cover.isNotEmpty ? Uri.tryParse(cover) : null,
      extras: {
        'url': streamUrl(s.id),
        'streamSource': 'cloud',
        'album': s.albumId != null ? {'name': s.album, 'id': s.albumId} : null,
        'artists': [
          {'name': artist, 'id': null}
        ],
      },
    );
  }

  List<MediaItem> toMediaItems(List<CloudSong> list) =>
      list.map(toMediaItem).toList();

  /// Subsonic JSON nests lists as `parent[key] = [...]` (or a single map on
  /// some servers) — normalize to a List.
  List _list(dynamic parent, String key) {
    if (parent is! Map) return const [];
    final v = parent[key];
    if (v is List) return v;
    if (v is Map) return [v];
    return const [];
  }

  void _ensureConfigured() {
    if (host.value.isEmpty || username.value.isEmpty || _password.isEmpty) {
      throw StateError('Not connected to a music server');
    }
  }
}
