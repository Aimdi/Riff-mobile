import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '/models/thumbnail.dart';
import '/utils/helper.dart';

/// A commercial audiobook entry (metadata only — not playable in-app).
class AudiobookItem {
  AudiobookItem({
    required this.title,
    required this.author,
    required this.cover,
    required this.genre,
    required this.description,
  });
  final String title;
  final String author;
  final String cover;
  final String genre;
  final String description;

  /// An Audible search link for this exact book.
  String get audibleUrl {
    final q = Uri.encodeQueryComponent(
        [title, author].where((s) => s.isNotEmpty).join(' '));
    return 'https://www.audible.com/search?keywords=$q';
  }
}

/// "Audible-style" discovery of popular audiobooks. Uses Apple's public
/// audiobook catalog (iTunes, no key) for real bestseller metadata — cover,
/// author, description — then links out to Audible to listen/buy. Audible
/// itself has no playable API (DRM + paid), so this is browse-only.
class AudiobookCatalogService {
  AudiobookCatalogService._();

  static final _dio = Dio(BaseOptions(
    receiveTimeout: const Duration(seconds: 15),
    headers: {'user-agent': 'Riff/1.0 (audiobooks)'},
  ));

  static String _storefront() {
    try {
      final m = RegExp(r'[_-]([A-Za-z]{2})').firstMatch(Platform.localeName);
      if (m != null) return m.group(1)!.toLowerCase();
    } catch (_) {}
    return 'us';
  }

  static Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      try {
        final d = jsonDecode(data);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return null;
  }

  /// Popular audiobooks (Apple top-audiobooks chart).
  static Future<List<AudiobookItem>> browse({int limit = 25}) async {
    try {
      final cc = _storefront();
      final res = await _dio.get(
          'https://itunes.apple.com/$cc/rss/topaudiobooks/limit=$limit/json');
      final entries = _asMap(res.data)?['feed']?['entry'] as List?;
      if (entries == null) return [];
      return entries
          .whereType<Map>()
          .map((e) {
            final images = e['im:image'] as List?;
            final raw = (images != null && images.isNotEmpty)
                ? '${images.last['label'] ?? ''}'
                : '';
            return AudiobookItem(
              title: '${e['im:name']?['label'] ?? ''}',
              author: '${e['im:artist']?['label'] ?? ''}',
              cover: Thumbnail(raw).extraHigh,
              genre: '${e['category']?['attributes']?['label'] ?? ''}',
              description: _stripHtml('${e['summary']?['label'] ?? ''}'),
            );
          })
          .where((b) => b.title.isNotEmpty)
          .toList();
    } catch (e) {
      printERROR('Audiobook browse failed: $e');
      return [];
    }
  }

  /// Search the Apple audiobook catalog by title/author.
  static Future<List<AudiobookItem>> search(String term) async {
    final t = term.trim();
    if (t.isEmpty) return [];
    try {
      final cc = _storefront();
      final res = await _dio.get('https://itunes.apple.com/search',
          queryParameters: {
            'media': 'audiobook',
            'term': t,
            'country': cc,
            'limit': 30,
          });
      final results = _asMap(res.data)?['results'] as List?;
      if (results == null) return [];
      return results
          .whereType<Map>()
          .map((r) {
            final raw = '${r['artworkUrl600'] ?? r['artworkUrl100'] ?? ''}';
            return AudiobookItem(
              title: '${r['collectionName'] ?? r['trackName'] ?? ''}',
              author: '${r['artistName'] ?? ''}',
              cover: Thumbnail(raw).extraHigh,
              genre: '${r['primaryGenreName'] ?? ''}',
              description: _stripHtml('${r['description'] ?? ''}'),
            );
          })
          .where((b) => b.title.isNotEmpty)
          .toList();
    } catch (e) {
      printERROR('Audiobook search failed: $e');
      return [];
    }
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').trim();
}
