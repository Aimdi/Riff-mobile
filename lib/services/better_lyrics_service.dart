import 'package:dio/dio.dart';

import '/utils/helper.dart';

/// Preferred lyrics provider for the in-player overlay.
///
/// [auto] tries Better Lyrics, then LRCLIB, then KuGou.
/// [betterLyrics] prefers Better Lyrics first (same cascade after).
/// [lrclib] skips Better Lyrics (LRCLIB → KuGou).
enum LyricsSource {
  auto,
  betterLyrics,
  lrclib,
}

/// Better Lyrics API — syllable-timed TTML converted to LRC for [flutter_lyric].
///
/// Docs: https://lyrics-api-docs.boidu.dev/
class BetterLyricsService {
  BetterLyricsService._();

  static const _base = 'https://lyrics-api.boidu.dev';

  static final _dio = Dio(BaseOptions(
    receiveTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 8),
    headers: {'accept': 'application/json'},
  ));

  /// Returns LRC text, or null on miss/error.
  static Future<String?> getSyncedLyrics({
    required String artist,
    required String title,
    String? album,
    int? durationSec,
  }) async {
    final a = artist.trim();
    final s = title.trim();
    if (a.isEmpty && s.isEmpty) return null;

    try {
      final params = <String, dynamic>{
        if (s.isNotEmpty) 's': s,
        if (a.isNotEmpty) 'a': a,
        if (album != null && album.trim().isNotEmpty) 'al': album.trim(),
        // API docs list duration in seconds for matching.
        if (durationSec != null && durationSec > 0) 'd': durationSec,
      };
      final res = await _dio.get('$_base/getLyrics', queryParameters: params);
      final data = res.data;
      if (data is! Map) return null;
      final ttml = data['ttml'];
      if (ttml is! String || ttml.isEmpty) return null;
      final lrc = ttmlToLrc(ttml);
      if (lrc != null) {
        printINFO('Synced lyrics from Better Lyrics');
      }
      return lrc;
    } on DioException catch (e) {
      printINFO('Better Lyrics miss: ${e.response?.statusCode ?? e.message}');
      return null;
    } catch (e) {
      printINFO('Better Lyrics failed: $e');
      return null;
    }
  }

  /// Convert Apple Music–style TTML (`<p begin>` lines) to LRC.
  /// Exposed for unit tests.
  static String? ttmlToLrc(String ttml) {
    final pRe = RegExp(
      r'<p\s+[^>]*begin="([^"]+)"[^>]*>(.*?)</p>',
      caseSensitive: false,
      dotAll: true,
    );
    final buf = StringBuffer();
    for (final m in pRe.allMatches(ttml)) {
      final begin = m.group(1)!;
      final raw = m.group(2)!;
      final text = raw
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isEmpty) continue;
      final stamp = _formatTimestamp(begin);
      if (stamp == null) continue;
      buf.writeln('[$stamp]$text');
    }
    final out = buf.toString().trim();
    return out.contains('[') ? out : null;
  }

  /// Plain text from TTML line bodies (no timestamps).
  static String? ttmlToPlain(String ttml) {
    final lrc = ttmlToLrc(ttml);
    if (lrc == null) return null;
    return lrc
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^\[[^\]]+\]'), ''))
        .where((l) => l.trim().isNotEmpty)
        .join('\n');
  }

  /// [begin] is seconds (`9.731`) or clock (`1:09.731` / `0:09.731`).
  static String? _formatTimestamp(String begin) {
    try {
      double seconds;
      if (begin.contains(':')) {
        final parts = begin.split(':');
        seconds = 0;
        for (final part in parts) {
          seconds = seconds * 60 + double.parse(part);
        }
      } else {
        seconds = double.parse(begin);
      }
      if (seconds < 0) return null;
      final m = seconds ~/ 60;
      final s = seconds - m * 60;
      final whole = s.floor();
      final frac = ((s - whole) * 100).round().clamp(0, 99);
      return '${m.toString().padLeft(2, '0')}:'
          '${whole.toString().padLeft(2, '0')}.'
          '${frac.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }
}
