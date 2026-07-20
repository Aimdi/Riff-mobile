import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '/models/thumbnail.dart';
import '/utils/helper.dart';

/// A commercial audiobook entry (metadata only — not playable in-app).
class AudiobookItem {
  AudiobookItem({
    required this.id,
    required this.title,
    required this.author,
    required this.cover,
    required this.genre,
    required this.description,
  });
  final String id; // Apple collectionId (for the details lookup)
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'cover': cover,
        'genre': genre,
        'description': description,
      };

  factory AudiobookItem.fromJson(Map json) => AudiobookItem(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        author: '${json['author'] ?? ''}',
        cover: '${json['cover'] ?? ''}',
        genre: '${json['genre'] ?? ''}',
        description: '${json['description'] ?? ''}',
      );
}

/// Fuller metadata fetched on demand for a book's detail page.
class AudiobookDetails {
  AudiobookDetails({
    required this.description,
    required this.releaseDate,
    required this.publisher,
    required this.genre,
    required this.rating,
    required this.appleUrl,
  });
  final String description;
  final String releaseDate;
  final String publisher;
  final String genre;
  final String rating;
  final String appleUrl;
}

/// A star rating for a book, sourced from Google Books (iTunes doesn't expose
/// audiobook ratings). [average] is 0–5; [count] is the number of ratings.
class AudiobookRating {
  AudiobookRating({required this.average, required this.count});
  final double average;
  final int count;
}

/// Extra metadata from Google Books: a star rating (if any) and subject/genre
/// tags — used to enrich the detail page beyond what iTunes returns.
class AudiobookExtras {
  AudiobookExtras({this.rating, this.categories = const []});
  final AudiobookRating? rating;
  final List<String> categories;
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
              id: '${e['id']?['attributes']?['im:id'] ?? ''}',
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
              id: '${r['collectionId'] ?? r['trackId'] ?? ''}',
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

  /// Similar audiobooks for the detail page: more by the same author first,
  /// topped up with same-genre titles. Excludes the book itself.
  static Future<List<AudiobookItem>> similar({
    required String author,
    required String genre,
    required String excludeId,
    int limit = 15,
  }) async {
    final out = <AudiobookItem>[];
    final seen = <String>{excludeId};
    void addAll(List<AudiobookItem> items) {
      for (final b in items) {
        if (b.id.isEmpty || seen.contains(b.id)) continue;
        seen.add(b.id);
        out.add(b);
      }
    }

    if (author.trim().isNotEmpty) addAll(await search(author));
    if (out.length < 3 && genre.trim().isNotEmpty) {
      addAll(await search(genre));
    }
    return out.take(limit).toList();
  }

  /// Fuller details for one book (description, release date, publisher, genre,
  /// rating) via an iTunes lookup — the top-charts feed omits most of these.
  static Future<AudiobookDetails?> details(String collectionId) async {
    if (collectionId.isEmpty) return null;
    try {
      final res = await _dio.get('https://itunes.apple.com/lookup',
          queryParameters: {'id': collectionId, 'country': _storefront()});
      final results = _asMap(res.data)?['results'] as List?;
      if (results == null || results.isEmpty) return null;
      final r = results.first as Map;
      final rating = r['contentAdvisoryRating'] != null
          ? '${r['contentAdvisoryRating']}'
          : '';
      return AudiobookDetails(
        description: _stripHtml('${r['description'] ?? ''}'),
        releaseDate: _year('${r['releaseDate'] ?? ''}'),
        publisher: '${r['copyright'] ?? ''}',
        genre: '${r['primaryGenreName'] ?? ''}',
        rating: rating,
        appleUrl: '${r['collectionViewUrl'] ?? ''}',
      );
    } catch (e) {
      printERROR('Audiobook details failed: $e');
      return null;
    }
  }

  /// Best-effort rating + subject tags for a book, matched by title (+ author)
  /// against Google Books (free `averageRating`/`ratingsCount`/`categories`).
  static Future<AudiobookExtras> extras({
    required String title,
    required String author,
  }) async {
    if (title.trim().isEmpty) return AudiobookExtras();
    try {
      final q =
          [title.trim(), author.trim()].where((s) => s.isNotEmpty).join(' ');
      final res = await _dio.get(
        'https://www.googleapis.com/books/v1/volumes',
        queryParameters: {
          'q': q,
          'maxResults': 5,
          'country': _storefront().toUpperCase(),
        },
      );
      final items = _asMap(res.data)?['items'] as List?;
      if (items == null) return AudiobookExtras();
      AudiobookRating? rating;
      final cats = <String>{};
      for (final it in items.whereType<Map>()) {
        final vi = it['volumeInfo'];
        if (vi is! Map) continue;
        if (rating == null && vi['averageRating'] != null) {
          final avg = (vi['averageRating'] as num).toDouble();
          if (avg > 0) {
            rating = AudiobookRating(
                average: avg,
                count: (vi['ratingsCount'] as num?)?.toInt() ?? 0);
          }
        }
        final c = vi['categories'];
        if (c is List) {
          for (final entry in c) {
            // "Fiction / Thrillers / Psychological" → 3 tags.
            for (final part in '$entry'.split('/')) {
              final t = part.trim();
              if (t.isNotEmpty && t.toLowerCase() != 'general') cats.add(t);
            }
          }
        }
      }
      return AudiobookExtras(rating: rating, categories: cats.take(6).toList());
    } catch (e) {
      printERROR('Audiobook extras failed: $e');
      return AudiobookExtras();
    }
  }

  static String _year(String iso) {
    if (iso.length >= 4) return iso.substring(0, 4);
    return '';
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').trim();
}
