import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/helper.dart';

/// Canonical recording metadata from Deezer's public API.
///
/// This is a **metadata-only** source. Deezer's public endpoints need no
/// authentication and return the catalogue's canonical title, artist, album
/// and — the reason this exists — the exact duration. No audio is fetched from
/// Deezer: playback stays on Riff's existing free sources.
///
/// Why it earns its place: the Spotify import scrapes the public embed page,
/// which frequently omits `duration`. Duration is the strongest signal for
/// telling a studio take from a remix, a live cut or a sped-up upload, so a
/// missing one measurably degrades match quality. Deezer fills it in.
class DeezerTrackMeta {
  const DeezerTrackMeta({
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
  });

  final String title;
  final String artist;
  final String? album;
  final int? durationMs;

  @override
  String toString() =>
      'DeezerTrackMeta($title / $artist / ${durationMs ?? '?'}ms)';
}

class DeezerMetadataService {
  DeezerMetadataService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 12),
              responseType: ResponseType.plain,
            ));

  final Dio _dio;

  static const String searchEndpoint = 'https://api.deezer.com/search';

  /// Deezer's advanced search syntax. Quoting each field keeps multi-word
  /// titles from being split into loose terms, which otherwise returns
  /// popular-but-wrong tracks for short titles.
  static String buildQuery(String title, String artist) {
    String clean(String s) => s
        .replaceAll('"', ' ')
        .replaceAll(' ', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final t = clean(title);
    final a = clean(artist);
    if (a.isEmpty) return 'track:"$t"';
    // Only the first credited artist — Deezer indexes the primary artist, and
    // passing a joined "A, B, C" string matches nothing.
    final primary = a.split(RegExp(r'\s*[,&/]\s*| feat\.? | ft\.? ')).first;
    return 'track:"$t" artist:"$primary"';
  }

  /// Parse Deezer's `/search` payload. Tolerant by design: the API returns
  /// `{"data": []}` for a miss and `{"error": {...}}` for quota problems, and
  /// neither should throw into the import loop.
  static DeezerTrackMeta? parseFirstResult(String body) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      json = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    if (json['error'] != null) return null;
    final data = json['data'];
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    if (first is! Map) return null;

    final title = (first['title_short'] ?? first['title'] ?? '').toString();
    if (title.isEmpty) return null;
    final artist = (first['artist'] is Map)
        ? (first['artist']['name'] ?? '').toString()
        : '';
    final album =
        (first['album'] is Map) ? first['album']['title']?.toString() : null;

    // Deezer reports duration in whole seconds.
    final durSec = first['duration'];
    final durationMs =
        (durSec is num && durSec > 0) ? (durSec.toInt() * 1000) : null;

    return DeezerTrackMeta(
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
    );
  }

  /// Look up canonical metadata for a recording. Returns null on any failure —
  /// this is an enrichment step and must never break an import.
  Future<DeezerTrackMeta?> lookup(String title, String artist) async {
    if (title.trim().isEmpty) return null;
    try {
      final res = await _dio.get(
        searchEndpoint,
        queryParameters: {'q': buildQuery(title, artist), 'limit': 1},
      );
      if (res.statusCode != 200) return null;
      return parseFirstResult(res.data.toString());
    } catch (e) {
      printINFO('Deezer metadata lookup failed for "$title": $e');
      return null;
    }
  }
}
