import 'dart:convert';

import 'package:dio/dio.dart';

import 'soulseek_client.dart';
import 'soulseek_search.dart';

/// Looks up album/song artwork for Soulseek search rows.
///
/// Soulseek peers don't send covers with FileSearch results. We query public
/// metadata APIs (iTunes + Deezer fallback) and cache aggressively.
class SoulseekCoverService {
  SoulseekCoverService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              headers: {
                'User-Agent': 'RiffMobile/1.0',
                'Accept': 'application/json,text/javascript,*/*',
              },
              // iTunes returns Content-Type: text/javascript — don't rely on
              // Dio's JSON transformer (it can leave data as a String / fail).
              responseType: ResponseType.plain,
              validateStatus: (s) => s != null && s < 500,
            ));

  final Dio _dio;

  /// Resolved cover URLs by cache key. Empty string = looked up, no art found.
  final Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inflight = {};

  /// Stable completed futures so FutureBuilder / State doesn't reset.
  final Map<String, Future<String?>> _completed = {};

  static final instance = SoulseekCoverService();

  void clear() {
    _cache.clear();
    _inflight.clear();
    _completed.clear();
  }

  /// Cover for a single file result.
  Future<String?> coverForFile(
    SoulseekFile file, {
    SoulseekQuery? query,
  }) {
    final hint = CoverLookupHint.fromFile(file, query);
    return coverForHint(hint);
  }

  /// Cover for an album folder aggregate.
  Future<String?> coverForAlbum(
    SoulseekAlbumFolder folder, {
    SoulseekQuery? query,
  }) {
    final hint = CoverLookupHint(
      artist: query?.artist?.trim().isNotEmpty == true
          ? query!.artist!.trim()
          : _artistFromPath(folder.folderPath, folder.folderName),
      album: query?.mode == SoulseekSearchMode.album &&
              (query?.title?.trim().isNotEmpty ?? false)
          ? query!.title!.trim()
          : folder.folderName,
      title: null,
    );
    return coverForHint(hint);
  }

  Future<String?> coverForHint(CoverLookupHint hint) {
    final key = hint.cacheKey;
    if (key.isEmpty || key == '||') {
      return _completed.putIfAbsent(key, () => Future<String?>.value(null));
    }
    if (_completed.containsKey(key)) return _completed[key]!;
    if (_cache.containsKey(key)) {
      final v = _cache[key]!;
      final fut = Future<String?>.value(v.isEmpty ? null : v);
      _completed[key] = fut;
      return fut;
    }
    return _inflight.putIfAbsent(key, () async {
      try {
        final url = await _lookup(hint);
        _cache[key] = url ?? '';
        final fut = Future<String?>.value(url);
        _completed[key] = fut;
        return url;
      } catch (_) {
        _cache[key] = '';
        final fut = Future<String?>.value(null);
        _completed[key] = fut;
        return null;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  Future<String?> _lookup(CoverLookupHint hint) async {
    final terms = hint.searchTerms;
    for (final term in terms) {
      if (term.trim().length < 2) continue;
      final itunes = await _searchItunes(term);
      if (itunes != null) return itunes;
      final deezer = await _searchDeezer(term);
      if (deezer != null) return deezer;
    }
    return null;
  }

  Future<String?> _searchItunes(String term) async {
    try {
      final album = await _itunesEntity(term, 'album');
      if (album != null) return album;
      return _itunesEntity(term, 'song');
    } catch (_) {
      return null;
    }
  }

  Future<String?> _itunesEntity(String term, String entity) async {
    final res = await _dio.get<String>(
      'https://itunes.apple.com/search',
      queryParameters: {
        'term': term,
        'media': 'music',
        'entity': entity,
        'limit': 1,
      },
    );
    if (res.statusCode != 200 || res.data == null || res.data!.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(res.data!);
    if (decoded is! Map) return null;
    final results = decoded['results'];
    if (results is! List || results.isEmpty) return null;
    final first = results.first;
    if (first is! Map) return null;
    final raw =
        '${first['artworkUrl100'] ?? first['artworkUrl60'] ?? ''}'.trim();
    if (raw.isEmpty) return null;
    return raw
        .replaceAll('100x100bb', '300x300bb')
        .replaceAll('60x60bb', '300x300bb');
  }

  Future<String?> _searchDeezer(String term) async {
    try {
      final res = await _dio.get<String>(
        'https://api.deezer.com/search',
        queryParameters: {'q': term, 'limit': 1},
      );
      if (res.statusCode != 200 || res.data == null) return null;
      final decoded = jsonDecode(res.data!);
      if (decoded is! Map) return null;
      final data = decoded['data'];
      if (data is! List || data.isEmpty) return null;
      final first = data.first;
      if (first is! Map) return null;
      final album = first['album'];
      if (album is Map) {
        final cover =
            '${album['cover_medium'] ?? album['cover'] ?? album['cover_big'] ?? ''}'
                .trim();
        if (cover.isNotEmpty) return cover;
      }
      final artist = first['artist'];
      if (artist is Map) {
        final pic = '${artist['picture_medium'] ?? ''}'.trim();
        if (pic.isNotEmpty) return pic;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? _artistFromPath(String folderPath, String folderName) {
    final parts = folderPath
        .replaceAll('\\', '/')
        .split('/')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;
    final parent = parts[parts.length - 2];
    if (parent.startsWith('@@')) return null;
    final lower = parent.toLowerCase();
    if (lower == 'music' ||
        lower == 'audio' ||
        lower == 'albums' ||
        lower == 'complete' ||
        lower == 'discography') {
      return null;
    }
    if (parent == folderName) return null;
    return parent;
  }
}

/// What to ask cover APIs for.
class CoverLookupHint {
  const CoverLookupHint({this.artist, this.album, this.title});

  final String? artist;
  final String? album;
  final String? title;

  String get cacheKey {
    final a = (artist ?? '').trim().toLowerCase();
    final al = (album ?? '').trim().toLowerCase();
    final t = (title ?? '').trim().toLowerCase();
    return '$a|$al|$t';
  }

  /// Ordered search strings — most specific first.
  List<String> get searchTerms {
    final a = artist?.trim() ?? '';
    final al = album?.trim() ?? '';
    final t = title?.trim() ?? '';
    final out = <String>[];
    void add(String s) {
      final x = s.trim();
      if (x.length < 2) return;
      if (!out.contains(x)) out.add(x);
    }

    if (a.isNotEmpty && t.isNotEmpty) add('$a $t');
    if (a.isNotEmpty && al.isNotEmpty) add('$a $al');
    if (t.isNotEmpty) add(t);
    if (al.isNotEmpty) add(al);
    if (a.isNotEmpty) add(a);
    return out;
  }

  factory CoverLookupHint.fromFile(SoulseekFile file, SoulseekQuery? query) {
    final qArtist = query?.artist?.trim();
    final qTitle = query?.title?.trim();

    String? artist = (qArtist != null && qArtist.isNotEmpty) ? qArtist : null;
    String? album;
    String? title = _titleFromFilename(file.displayName);

    // Only trust query title when it looks like Artist - Title (has artist).
    // Bare searches like "hu ta" must not overwrite every row's track title.
    if (query?.mode == SoulseekSearchMode.album &&
        qTitle != null &&
        qTitle.isNotEmpty) {
      album = qTitle;
    } else if (query?.mode == SoulseekSearchMode.song &&
        artist != null &&
        qTitle != null &&
        qTitle.isNotEmpty) {
      title = qTitle;
    }

    album ??= _cleanFolder(file.folderName);

    artist ??= SoulseekCoverService._artistFromPath(
      file.folderPath,
      file.folderName,
    );

    // Path pattern: "Artist - Album" as folder name.
    final folder = file.folderName;
    final split = RegExp(r'\s+-\s+').firstMatch(folder);
    if (split != null) {
      final left = folder.substring(0, split.start).trim();
      final right = folder.substring(split.end).trim();
      if (left.isNotEmpty && right.isNotEmpty) {
        artist ??= left;
        if (album == folder) album = right;
      }
    }

    // Filename "Artist - Title.mp3"
    final fileSplit = RegExp(r'\s+-\s+').firstMatch(title ?? '');
    if (fileSplit != null && title != null) {
      final left = title.substring(0, fileSplit.start).trim();
      final right = title.substring(fileSplit.end).trim();
      if (left.isNotEmpty && right.isNotEmpty && artist == null) {
        artist = left;
        title = right;
      }
    }

    return CoverLookupHint(artist: artist, album: album, title: title);
  }

  static String? _cleanFolder(String name) {
    final n = name.trim();
    if (n.isEmpty || n.startsWith('@@')) return null;
    return n;
  }

  static String? _titleFromFilename(String name) {
    var n = name.trim();
    final dot = n.lastIndexOf('.');
    if (dot > 0) n = n.substring(0, dot);
    n = n.replaceFirst(RegExp(r'^\d{1,3}[\s.\-_]+'), '').trim();
    n = n.replaceFirst(RegExp(r'^\d{1,3}\s+-\s+'), '').trim();
    return n.isEmpty ? null : n;
  }
}
