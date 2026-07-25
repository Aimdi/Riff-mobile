import 'package:dio/dio.dart';

import '/utils/helper.dart';

/// Preferred lyrics provider for the in-player overlay.
enum LyricsSource {
  auto,
  betterLyrics,
  lrclib,
}

/// Result from Better Lyrics — keeps raw TTML for word-level sync.
class BetterLyricsResult {
  const BetterLyricsResult({
    required this.ttml,
    required this.lrc,
    this.plain,
  });

  final String ttml;
  final String lrc;
  final String? plain;
}

/// Better Lyrics API — syllable-timed TTML (+ LRC fallback for flutter_lyric).
class BetterLyricsService {
  BetterLyricsService._();

  static const _base = 'https://lyrics-api.boidu.dev';

  static final _dio = Dio(BaseOptions(
    receiveTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 8),
    headers: {'accept': 'application/json'},
  ));

  /// Full result with TTML retained for word-synced UI.
  static Future<BetterLyricsResult?> fetch({
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
        if (durationSec != null && durationSec > 0) 'd': durationSec,
      };
      final res = await _dio.get('$_base/getLyrics', queryParameters: params);
      final data = res.data;
      if (data is! Map) return null;
      final ttml = data['ttml'];
      if (ttml is! String || ttml.isEmpty) return null;
      final lrc = ttmlToLrc(ttml);
      if (lrc == null) return null;
      printINFO('Synced lyrics from Better Lyrics (word-capable)');
      return BetterLyricsResult(
        ttml: ttml,
        lrc: lrc,
        plain: ttmlToPlain(ttml),
      );
    } on DioException catch (e) {
      printINFO('Better Lyrics miss: ${e.response?.statusCode ?? e.message}');
      return null;
    } catch (e) {
      printINFO('Better Lyrics failed: $e');
      return null;
    }
  }

  /// Returns LRC text only (legacy callers / tests).
  static Future<String?> getSyncedLyrics({
    required String artist,
    required String title,
    String? album,
    int? durationSec,
  }) async {
    final r = await fetch(
      artist: artist,
      title: title,
      album: album,
      durationSec: durationSec,
    );
    return r?.lrc;
  }

  /// Convert Apple Music–style TTML (`<p begin>` lines) to LRC.
  static String? ttmlToLrc(String ttml) {
    final lines = parseTimedLines(ttml);
    if (lines.isEmpty) return null;
    final buf = StringBuffer();
    for (final line in lines) {
      final stamp = formatTimestamp(line.beginSec);
      if (stamp == null) continue;
      buf.writeln('[$stamp]${line.text}');
    }
    final out = buf.toString().trim();
    return out.contains('[') ? out : null;
  }

  static String? ttmlToPlain(String ttml) {
    final lines = parseTimedLines(ttml);
    if (lines.isEmpty) return null;
    return lines.map((l) => l.text).join('\n');
  }

  /// Parse TTML into timed lines with optional word spans.
  static List<TtmlLine> parseTimedLines(String ttml) {
    final pRe = RegExp(
      r'<p\s+[^>]*begin="([^"]+)"[^>]*(?:end="([^"]*)")?[^>]*>(.*?)</p>',
      caseSensitive: false,
      dotAll: true,
    );
    final spanRe = RegExp(
      r'<span\s+[^>]*begin="([^"]+)"[^>]*(?:end="([^"]*)")?[^>]*>(.*?)</span>',
      caseSensitive: false,
      dotAll: true,
    );
    final out = <TtmlLine>[];
    for (final m in pRe.allMatches(ttml)) {
      final begin = parseClock(m.group(1)!);
      if (begin == null) continue;
      final endRaw = m.group(2);
      final end = endRaw != null && endRaw.isNotEmpty
          ? parseClock(endRaw)
          : null;
      final raw = m.group(3)!;
      final words = <TtmlWord>[];
      for (final s in spanRe.allMatches(raw)) {
        final wb = parseClock(s.group(1)!);
        if (wb == null) continue;
        final weRaw = s.group(2);
        final we =
            weRaw != null && weRaw.isNotEmpty ? parseClock(weRaw) : null;
        final text = _decode(s.group(3)!);
        if (text.isEmpty) continue;
        words.add(TtmlWord(beginSec: wb, endSec: we, text: text));
      }
      final lineText = words.isNotEmpty
          ? words.map((w) => w.text).join(' ')
          : _decode(raw);
      if (lineText.isEmpty) continue;
      out.add(TtmlLine(
        beginSec: begin,
        endSec: end,
        text: lineText,
        words: words,
      ));
    }
    return out;
  }

  static String _decode(String raw) => raw
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static double? parseClock(String begin) {
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
      return seconds;
    } catch (_) {
      return null;
    }
  }

  static String? formatTimestamp(double seconds) {
    if (seconds < 0) return null;
    final m = seconds ~/ 60;
    final s = seconds - m * 60;
    final whole = s.floor();
    // 3 fractional digits: flutter_lyric's parser only handles millisecond
    // stamps correctly (2-digit stamps hit its broken padRight branch).
    final frac = ((s - whole) * 1000).round().clamp(0, 999);
    return '${m.toString().padLeft(2, '0')}:'
        '${whole.toString().padLeft(2, '0')}.'
        '${frac.toString().padLeft(3, '0')}';
  }
}

class TtmlLine {
  const TtmlLine({
    required this.beginSec,
    required this.text,
    this.endSec,
    this.words = const [],
  });

  final double beginSec;
  final double? endSec;
  final String text;
  final List<TtmlWord> words;

  bool get hasWords => words.isNotEmpty;
}

class TtmlWord {
  const TtmlWord({
    required this.beginSec,
    required this.text,
    this.endSec,
  });

  final double beginSec;
  final double? endSec;
  final String text;
}
