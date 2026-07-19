import 'dart:convert';

import 'package:dio/dio.dart';

import '/utils/helper.dart';

/// KuGou synced-lyrics provider, ported from RiPlay. Used as a fallback
/// when LRCLIB has no match — KuGou's catalogue covers a lot of Asian and
/// long-tail tracks LRCLIB misses. Returns LRC text or null.
class KuGouLyricsService {
  KuGouLyricsService._();

  static final _dio = Dio(BaseOptions(
    receiveTimeout: const Duration(seconds: 8),
    sendTimeout: const Duration(seconds: 8),
    headers: {'accept': 'application/json'},
  ));

  static Future<String?> getSyncedLyrics(
      String artist, String title, int durationSec) async {
    try {
      final keyword = _keyword(artist, title);

      // 1) Search songs, match by duration (±tolerance), grab lyrics by hash.
      final songs = await _searchSong(keyword);
      for (var tolerance = 0; tolerance <= 5; tolerance++) {
        for (final s in songs) {
          final dur = (s['duration'] ?? 0) as int;
          if (dur >= durationSec - tolerance && dur <= durationSec + tolerance) {
            final cand = await _searchLyricsByHash(s['hash'] as String);
            if (cand != null) {
              final lrc = await _download(cand[0], cand[1]);
              if (lrc != null && lrc.contains('[')) return lrc;
            }
          }
        }
      }

      // 2) Fall back to a keyword lyric search.
      final cand = await _searchLyricsByKeyword(keyword);
      if (cand != null) {
        final lrc = await _download(cand[0], cand[1]);
        if (lrc != null && lrc.contains('[')) return lrc;
      }
    } catch (e) {
      printINFO("KuGou lyrics lookup failed: $e");
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> _searchSong(String keyword) async {
    final res = await _dio.get(
      'https://mobileservice.kugou.com/api/v3/search/song',
      queryParameters: {
        'version': 9108,
        'plat': 0,
        'pagesize': 8,
        'showtype': 0,
        'keyword': keyword,
      },
    );
    final info = _json(res.data)?['data']?['info'];
    if (info is List) return info.cast<Map<String, dynamic>>();
    return [];
  }

  /// Returns [id, accessKey] of the first lyric candidate, or null.
  static Future<List<dynamic>?> _searchLyricsByHash(String hash) async {
    final res = await _dio.get('https://krcs.kugou.com/search',
        queryParameters: {
          'ver': 1,
          'man': 'yes',
          'client': 'mobi',
          'hash': hash
        });
    return _firstCandidate(res.data);
  }

  static Future<List<dynamic>?> _searchLyricsByKeyword(String keyword) async {
    final res = await _dio.get('https://krcs.kugou.com/search',
        queryParameters: {
          'ver': 1,
          'man': 'yes',
          'client': 'mobi',
          'keyword': keyword
        });
    return _firstCandidate(res.data);
  }

  static List<dynamic>? _firstCandidate(dynamic data) {
    final cands = _json(data)?['candidates'];
    if (cands is List && cands.isNotEmpty) {
      return [cands[0]['id'], cands[0]['accesskey']];
    }
    return null;
  }

  static Future<String?> _download(dynamic id, dynamic accessKey) async {
    final res = await _dio.get('https://krcs.kugou.com/download',
        queryParameters: {
          'ver': 1,
          'man': 'yes',
          'client': 'pc',
          'fmt': 'lrc',
          'id': id,
          'accesskey': accessKey,
        });
    final content = _json(res.data)?['content'];
    if (content is String && content.isNotEmpty) {
      try {
        return utf8.decode(base64.decode(content));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _json(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }

  static String _keyword(String artist, String title) {
    var newTitle = title;
    var featuring = '';
    final featIdx = title.indexOf(' (feat. ');
    if (featIdx != -1) {
      final end = title.indexOf(')', featIdx);
      if (end != -1) {
        featuring = title.substring(featIdx + 8, end);
        newTitle = title.substring(0, featIdx);
      }
    }
    final newArtist = (featuring.isEmpty ? artist : '$artist, $featuring')
        .replaceAll(', ', '、')
        .replaceAll(' & ', '、')
        .replaceAll('.', '');
    return '$newArtist - $newTitle';
  }
}
