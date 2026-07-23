import 'package:dio/dio.dart';

import 'soulseek_client.dart';
import 'soulseek_search.dart';

/// Looks up album/song artwork for Soulseek search rows.
///
/// Soulseek peers don't send covers with FileSearch results. Sockseek-style
/// clients fetch art separately (Cover Fetcher / MusicBrainz / iTunes). We use
/// the public iTunes Search API (no key) — same source Riff already uses for
/// audiobook covers — and cache aggressively.
class SoulseekCoverService {
  SoulseekCoverService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'User-Agent': 'RiffMobile/1.0'},
            ));

  final Dio _dio;

  /// Resolved cover URLs by cache key. Empty string = looked up, no art found.
  final Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inflight = {};

  static final instance = SoulseekCoverService();

  void clear() {
    _cache.clear();
    _inflight.clear();
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
    if (key.isEmpty) return Future.value(null);
    if (_cache.containsKey(key)) {
      final v = _cache[key]!;
      return Future.value(v.isEmpty ? null : v);
    }
    return _inflight.putIfAbsent(key, () async {
      try {
        final url = await _lookupItunes(hint);
        _cache[key] = url ?? '';
        return url;
      } catch (_) {
        _cache[key] = '';
        return null;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  Future<String?> _lookupItunes(CoverLookupHint hint) async {
    final termParts = <String>[
      if (hint.artist != null && hint.artist!.isNotEmpty) hint.artist!,
      if (hint.album != null && hint.album!.isNotEmpty) hint.album!,
      if ((hint.album == null || hint.album!.isEmpty) &&
          hint.title != null &&
          hint.title!.isNotEmpty)
        hint.title!,
    ];
    final term = termParts.join(' ').trim();
    if (term.length < 2) return null;

    // Prefer album art; fall back to song artwork.
    final albumUrl = await _search(
      term: term,
      entity: 'album',
    );
    if (albumUrl != null) return albumUrl;

    if (hint.title != null && hint.title!.isNotEmpty) {
      final songTerm = [
        if (hint.artist != null) hint.artist!,
        hint.title!,
      ].join(' ');
      return _search(term: songTerm, entity: 'song');
    }
    return _search(term: term, entity: 'song');
  }

  Future<String?> _search({
    required String term,
    required String entity,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      'https://itunes.apple.com/search',
      queryParameters: {
        'term': term,
        'media': 'music',
        'entity': entity,
        'limit': 1,
      },
      options: Options(responseType: ResponseType.json),
    );
    final results = res.data?['results'];
    if (results is! List || results.isEmpty) return null;
    final first = results.first;
    if (first is! Map) return null;
    final raw =
        '${first['artworkUrl100'] ?? first['artworkUrl60'] ?? ''}'.trim();
    if (raw.isEmpty) return null;
    // Upscale common iTunes thumb sizes for list tiles.
    return raw
        .replaceAll('100x100bb', '300x300bb')
        .replaceAll('60x60bb', '300x300bb');
  }

  static String? _artistFromPath(String folderPath, String folderName) {
    final parts = folderPath
        .replaceAll('\\', '/')
        .split('/')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;
    // Drop leaf folder (album); previous segment is often the artist.
    final parent = parts[parts.length - 2];
    if (parent.startsWith('@@')) return null;
    final lower = parent.toLowerCase();
    if (lower == 'music' || lower == 'audio' || lower == 'albums') return null;
    if (parent == folderName) return null;
    return parent;
  }
}

/// What to ask iTunes for.
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

  factory CoverLookupHint.fromFile(SoulseekFile file, SoulseekQuery? query) {
    final qArtist = query?.artist?.trim();
    final qTitle = query?.title?.trim();

    String? artist = (qArtist != null && qArtist.isNotEmpty) ? qArtist : null;
    String? album;
    String? title;

    if (query?.mode == SoulseekSearchMode.album &&
        qTitle != null &&
        qTitle.isNotEmpty) {
      album = qTitle;
    } else if (query?.mode == SoulseekSearchMode.song &&
        qTitle != null &&
        qTitle.isNotEmpty) {
      title = qTitle;
    }

    album ??= _cleanFolder(file.folderName);
    title ??= _titleFromFilename(file.displayName);

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
        album = album == folder ? right : album;
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
    // Strip leading track numbers: "01 - Title" / "01. Title"
    n = n.replaceFirst(RegExp(r'^\d{1,3}[\s.\-_]+'), '').trim();
    n = n.replaceFirst(RegExp(r'^\d{1,3}\s+-\s+'), '').trim();
    return n.isEmpty ? null : n;
  }
}
