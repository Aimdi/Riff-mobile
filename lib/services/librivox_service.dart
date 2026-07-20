import 'dart:convert';

import 'package:dio/dio.dart';

import '/utils/helper.dart';

/// A LibriVox audiobook chapter (a directly-playable mp3 hosted on archive.org).
class LvChapter {
  LvChapter(this.title, this.url, this.durationSec);
  final String title;
  final String url;
  final int durationSec;
}

/// A free public-domain audiobook from LibriVox.
class LvAudiobook {
  LvAudiobook({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.cover,
    required this.chapters,
    required this.totalSec,
  });
  final String id;
  final String title;
  final String author;
  final String description;
  final String cover;
  final List<LvChapter> chapters;
  final int totalSec;
}

/// Discovery for free audiobooks via LibriVox's public JSON API (no key). Books
/// come back with their chapters (direct archive.org mp3 URLs), so they play
/// through the normal pipeline like podcasts. Cover art is derived from the
/// archive.org item id in the first chapter's URL.
class LibriVoxService {
  LibriVoxService._();

  static final _dio = Dio(BaseOptions(
    receiveTimeout: const Duration(seconds: 20),
    headers: {'user-agent': 'Riff/1.0 (audiobooks)'},
  ));

  static const _base = 'https://librivox.org/api/feed/audiobooks';

  /// Recently released audiobooks — a browse feed to seed the Discover view.
  static Future<List<LvAudiobook>> browse({int limit = 30}) =>
      _fetch({'format': 'json', 'extended': '1', 'limit': '$limit'});

  /// Search by title (LibriVox matches a title prefix with ^).
  static Future<List<LvAudiobook>> search(String term) {
    final t = term.trim();
    if (t.isEmpty) return Future.value([]);
    return _fetch({
      'format': 'json',
      'extended': '1',
      'limit': '30',
      'title': '^$t',
    });
  }

  static Future<List<LvAudiobook>> _fetch(Map<String, String> params) async {
    try {
      final res = await _dio.get(_base, queryParameters: params);
      final data = res.data is String ? jsonDecode(res.data) : res.data;
      final books = (data is Map) ? data['books'] as List? : null;
      if (books == null) return [];
      return books
          .whereType<Map>()
          .map(_parse)
          .whereType<LvAudiobook>()
          .toList();
    } catch (e) {
      printERROR('LibriVox fetch failed: $e');
      return [];
    }
  }

  static LvAudiobook? _parse(Map b) {
    final id = '${b['id'] ?? ''}';
    final title = '${b['title'] ?? ''}'.trim();
    if (id.isEmpty || title.isEmpty) return null;

    // Author: first reader/author entry.
    var author = '';
    final authors = b['authors'];
    if (authors is List && authors.isNotEmpty && authors.first is Map) {
      final a = authors.first as Map;
      author = ['${a['first_name'] ?? ''}', '${a['last_name'] ?? ''}']
          .where((s) => s.trim().isNotEmpty)
          .join(' ')
          .trim();
    }

    final sections = b['sections'];
    final chapters = <LvChapter>[];
    String? firstUrl;
    if (sections is List) {
      for (var i = 0; i < sections.length; i++) {
        final s = sections[i];
        if (s is! Map) continue;
        final url = '${s['listen_url'] ?? ''}';
        if (url.isEmpty) continue;
        firstUrl ??= url;
        chapters.add(LvChapter(
          '${s['title'] ?? 'Chapter ${i + 1}'}',
          url,
          int.tryParse('${s['playtime'] ?? 0}') ?? 0,
        ));
      }
    }
    if (chapters.isEmpty) return null;

    return LvAudiobook(
      id: id,
      title: title,
      author: author,
      description: _stripHtml('${b['description'] ?? ''}'),
      cover: _coverFromUrl(firstUrl),
      chapters: chapters,
      totalSec: int.tryParse('${b['totaltime_secs'] ?? 0}') ?? 0,
    );
  }

  /// archive.org serves an item's cover at /services/img/{identifier}, and the
  /// identifier is the path segment after /download/ in a chapter URL.
  static String _coverFromUrl(String? url) {
    if (url == null) return '';
    final m = RegExp(r'/download/([^/]+)/').firstMatch(url);
    if (m != null) {
      return 'https://archive.org/services/img/${m.group(1)}';
    }
    return '';
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').trim();
}
