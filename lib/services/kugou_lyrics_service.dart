import 'dart:convert';

import 'package:dio/dio.dart';

import '/services/kugou_lyrics_match.dart';
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

      // 1) Search songs, match by duration (±5 s, closest first), grab
      //    lyrics by hash. Each hash is tried once.
      final songs = await _searchSong(keyword);
      for (final hash in songHashesByDuration(songs, durationSec)) {
        final cand =
            await _searchLyricsByHash(hash, durationSec, artist, title);
        if (cand != null) {
          final lrc = await _download(cand[0], cand[1]);
          if (lrc != null && lrc.contains('[')) return lrc;
        }
      }

      // 2) Fall back to a keyword lyric search.
      final cand =
          await _searchLyricsByKeyword(keyword, durationSec, artist, title);
      if (cand != null) {
        final lrc = await _download(cand[0], cand[1]);
        if (lrc != null && lrc.contains('[')) return lrc;
      }
    } catch (e) {
      printINFO("KuGou lyrics lookup failed: $e");
    }
    return null;
  }

  /// Hashes of [songs] whose duration is within [toleranceSec] of
  /// [durationSec], closest first, without duplicates.
  static List<String> songHashesByDuration(
      List<Map<String, dynamic>> songs, int durationSec,
      {int toleranceSec = 5}) {
    final matches = <({String hash, int diff})>[];
    final seen = <String>{};
    for (final s in songs) {
      final hash = s['hash'];
      final dur = s['duration'];
      if (hash is! String || hash.isEmpty || dur is! num) continue;
      final diff = (dur.round() - durationSec).abs();
      if (diff > toleranceSec || !seen.add(hash)) continue;
      matches.add((hash: hash, diff: diff));
    }
    // List.sort isn't stable; tie-break on search rank to keep its order.
    final rank = {for (var i = 0; i < matches.length; i++) matches[i].hash: i};
    matches.sort((a, b) {
      final c = a.diff.compareTo(b.diff);
      return c != 0 ? c : rank[a.hash]!.compareTo(rank[b.hash]!);
    });
    return [for (final m in matches) m.hash];
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

  /// Returns [id, accessKey] of the best lyric candidate, or null.
  ///
  /// The hash already identifies the track, so a candidate is still accepted
  /// when none of them lines up with [durationSec].
  static Future<List<dynamic>?> _searchLyricsByHash(
      String hash, int durationSec, String artist, String title) async {
    final res = await _dio.get('https://krcs.kugou.com/search',
        queryParameters: {
          'ver': 1,
          'man': 'yes',
          'client': 'mobi',
          'hash': hash
        });
    return _bestCandidate(res.data, durationSec, artist, title);
  }

  /// Keyword fallback. The duration is sent along so KuGou can rank sensibly,
  /// and the picker prefers a closer match, but a miss still falls back to the
  /// top result: this path is only reached once the song search failed to
  /// match on duration, so rejecting on duration again would return nothing
  /// for exactly the tracks the fallback exists to rescue.
  static Future<List<dynamic>?> _searchLyricsByKeyword(
      String keyword, int durationSec, String artist, String title) async {
    final res = await _dio.get('https://krcs.kugou.com/search',
        queryParameters: {
          'ver': 1,
          'man': 'yes',
          'client': 'mobi',
          'keyword': keyword,
          if (durationSec > 0) 'duration': durationSec * 1000,
        });
    return _bestCandidate(res.data, durationSec, artist, title);
  }

  static List<dynamic>? _bestCandidate(
    dynamic data,
    int durationSec,
    String artist,
    String title,
  ) {
    final best = pickBestKuGouCandidate(
      parseKuGouCandidates(_json(data)),
      targetDurationSec: durationSec,
      title: title,
      artist: artist,
    );
    return best == null ? null : [best.id, best.accessKey];
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
