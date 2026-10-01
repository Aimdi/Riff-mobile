import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '/utils/helper.dart';

/// Id prefix for playable free audiobook chapters: `lv_<identifier>_<index>`.
/// Like `abs_` / `podcast_`, it tells the audio handler the item carries its
/// own stream URL (no YouTube resolution, no song cache).
const String freeAudiobookIdPrefix = 'lv_';

/// A public-domain LibriVox recording, as listed by the Internet Archive.
class FreeAudiobook {
  FreeAudiobook({
    required this.id,
    required this.title,
    required this.author,
    this.downloads = 0,
  });

  /// Internet Archive identifier (e.g. `adventures_holmes_0711_librivox`).
  final String id;
  final String title;
  final String author;
  final int downloads;

  /// The Archive's thumbnail service serves each item's cover art.
  String get cover => coverFor(id);

  static String coverFor(String id) => '$coverBase${Uri.encodeComponent(id)}';

  @visibleForTesting
  static String coverBase = 'https://archive.org/services/img/';

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'author': author, 'downloads': downloads};

  factory FreeAudiobook.fromJson(Map json) => FreeAudiobook(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        author: '${json['author'] ?? ''}',
        downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      );
}

/// One MP3 section of a book.
class FreeAudiobookChapter {
  FreeAudiobookChapter({
    required this.index,
    required this.title,
    required this.url,
    required this.durationSec,
  });
  final int index;
  final String title;
  final String url;
  final double durationSec;
}

/// A book's metadata plus its ordered chapters.
class FreeAudiobookDetail {
  FreeAudiobookDetail({
    required this.book,
    required this.description,
    required this.chapters,
    this.subjects = const [],
    this.language = '',
  });
  final FreeAudiobook book;
  final String description;
  final List<FreeAudiobookChapter> chapters;
  final List<String> subjects;
  final String language;

  double get totalSec => chapters.fold(
      0.0, (sum, c) => sum + (c.durationSec > 0 ? c.durationSec : 0));
}

/// A browsable genre: a localisation key for the label and the Archive
/// subject it searches.
class FreeAudiobookGenre {
  const FreeAudiobookGenre(this.labelKey, this.subject);
  final String labelKey;
  final String subject;
}

/// Free, legal audiobooks: LibriVox volunteer recordings of public-domain
/// books, hosted by the Internet Archive (`collection:librivoxaudio`). No key,
/// no account; chapters are plain MP3 files, so they play in-app like
/// podcast episodes.
class FreeAudiobookService {
  FreeAudiobookService._();

  static const genres = <FreeAudiobookGenre>[
    FreeAudiobookGenre('abGenreMystery', 'mystery'),
    FreeAudiobookGenre('abGenreAdventure', 'adventure'),
    FreeAudiobookGenre('abGenreSciFi', 'science fiction'),
    FreeAudiobookGenre('abGenreFantasy', 'fantasy'),
    FreeAudiobookGenre('abGenreHorror', 'horror'),
    FreeAudiobookGenre('abGenreRomance', 'romance'),
    FreeAudiobookGenre('abGenreChildren', 'children'),
    FreeAudiobookGenre('abGenrePoetry', 'poetry'),
    FreeAudiobookGenre('abGenrePhilosophy', 'philosophy'),
    FreeAudiobookGenre('abGenreHistory', 'history'),
  ];

  @visibleForTesting
  static Dio dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'user-agent': 'Riff/1.0 (audiobooks)'},
  ));

  static final _listCache = <String, List<FreeAudiobook>>{};
  static final _detailCache = <String, FreeAudiobookDetail>{};

  @visibleForTesting
  static void clearCache() {
    _listCache.clear();
    _detailCache.clear();
  }

  /// Most-downloaded LibriVox books.
  static Future<List<FreeAudiobook>> popular({int rows = 30}) =>
      _list(searchUri(rows: rows));

  /// Most-downloaded books tagged with [subject].
  static Future<List<FreeAudiobook>> byGenre(String subject, {int rows = 40}) =>
      _list(searchUri(subject: subject, rows: rows));

  /// Title / author search, best matches by popularity.
  static Future<List<FreeAudiobook>> search(String text, {int rows = 40}) {
    if (sanitizeTerms(text).isEmpty) return Future.value(const []);
    return _list(searchUri(text: text, rows: rows));
  }

  static Future<List<FreeAudiobook>> _list(Uri uri) async {
    final key = uri.toString();
    final hit = _listCache[key];
    if (hit != null) return hit;
    try {
      final res = await dio.getUri(uri);
      final list = parseSearch(_asMap(res.data));
      if (list.isNotEmpty) _listCache[key] = list;
      return list;
    } catch (e) {
      printERROR('Free audiobook list failed: $e');
      return const [];
    }
  }

  /// Full metadata + chapter list for one book; null when unreachable.
  static Future<FreeAudiobookDetail?> detail(String id) async {
    if (id.isEmpty) return null;
    final hit = _detailCache[id];
    if (hit != null) return hit;
    try {
      final res = await dio.getUri(
          Uri.https('archive.org', '/metadata/${Uri.encodeComponent(id)}'));
      final d = parseMetadata(_asMap(res.data));
      if (d != null && d.chapters.isNotEmpty) _detailCache[id] = d;
      return d;
    } catch (e) {
      printERROR('Free audiobook detail failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------- pure --

  /// Search words only: the Archive query language treats `:()"*` etc. as
  /// syntax, so user text is reduced to letters, digits and spaces.
  static String sanitizeTerms(String text) => text
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static String buildQuery({String? text, String? subject}) {
    final parts = ['collection:librivoxaudio', 'mediatype:audio'];
    final s = sanitizeTerms(subject ?? '');
    if (s.isNotEmpty) parts.add('subject:"$s"');
    final t = sanitizeTerms(text ?? '');
    if (t.isNotEmpty) parts.add('(title:($t) OR creator:($t))');
    return parts.join(' AND ');
  }

  static Uri searchUri(
          {String? text, String? subject, int rows = 30, int page = 1}) =>
      Uri.https('archive.org', '/advancedsearch.php', {
        'q': buildQuery(text: text, subject: subject),
        'fl[]': const ['identifier', 'title', 'creator', 'downloads'],
        'sort[]': 'downloads desc',
        'rows': '$rows',
        'page': '$page',
        'output': 'json',
      });

  /// `advancedsearch.php` JSON → books (drops entries without id/title).
  static List<FreeAudiobook> parseSearch(Map<String, dynamic>? json) {
    final response = json?['response'];
    final docs = response is Map ? response['docs'] : null;
    if (docs is! List) return const [];
    final out = <FreeAudiobook>[];
    final seen = <String>{};
    for (final d in docs.whereType<Map>()) {
      final id = _first(d['identifier']);
      final title = cleanTitle(_first(d['title']));
      if (id.isEmpty || title.isEmpty || !seen.add(id)) continue;
      out.add(FreeAudiobook(
        id: id,
        title: title,
        author: _first(d['creator']),
        downloads: (d['downloads'] as num?)?.toInt() ?? 0,
      ));
    }
    return out;
  }

  /// MP3 flavours in preference order: the 64 kbps derivative is plenty for
  /// speech and a third of the data of the 128 kbps original.
  static const _formats = ['64Kbps MP3', 'VBR MP3', '128Kbps MP3', 'MP3'];

  /// `/metadata/<id>` JSON → detail with chapters in track order.
  static FreeAudiobookDetail? parseMetadata(Map<String, dynamic>? json) {
    final meta = json?['metadata'];
    if (meta is! Map) return null;
    final id = _first(meta['identifier']);
    if (id.isEmpty) return null;
    final rawFiles = json?['files'];
    final files =
        rawFiles is List ? rawFiles.whereType<Map>().toList() : <Map>[];

    List<Map> pick = const [];
    for (final f in _formats) {
      final match = files.where((e) => '${e['format']}' == f).toList();
      if (match.isNotEmpty) {
        pick = match;
        break;
      }
    }
    if (pick.isEmpty) {
      pick = files
          .where((e) => '${e['name']}'.toLowerCase().endsWith('.mp3'))
          .toList();
    }
    final ordered = [...pick]..sort((a, b) {
        final ta = _trackNo(a['track']);
        final tb = _trackNo(b['track']);
        if (ta != tb) return ta.compareTo(tb);
        return '${a['name']}'.compareTo('${b['name']}');
      });

    final chapters = <FreeAudiobookChapter>[];
    for (final f in ordered) {
      final name = '${f['name'] ?? ''}';
      if (name.isEmpty) continue;
      final title = _first(f['title']);
      chapters.add(FreeAudiobookChapter(
        index: chapters.length,
        title: title.isNotEmpty ? title : _stem(name),
        url: 'https://archive.org/download/${Uri.encodeComponent(id)}/'
            '${name.split('/').map(Uri.encodeComponent).join('/')}',
        durationSec: parseLength('${f['length'] ?? ''}'),
      ));
    }

    final subjects = <String>[];
    final rawSubjects = meta['subject'];
    for (final s in rawSubjects is List ? rawSubjects : [rawSubjects]) {
      for (final part in '${s ?? ''}'.split(';')) {
        final t = part.trim();
        final lower = t.toLowerCase();
        if (t.isEmpty ||
            lower == 'librivox' ||
            lower == 'audiobook' ||
            lower == 'audiobooks' ||
            subjects.any((x) => x.toLowerCase() == lower)) {
          continue;
        }
        subjects.add(t);
      }
    }

    return FreeAudiobookDetail(
      book: FreeAudiobook(
        id: id,
        title: cleanTitle(_first(meta['title'])),
        author: _first(meta['creator']),
        downloads: (json?['item'] is Map
                ? ((json!['item'] as Map)['downloads'] as num?)?.toInt()
                : null) ??
            0,
      ),
      description: htmlToText(_first(meta['description'])),
      chapters: chapters,
      subjects: subjects.take(6).toList(),
      language: _first(meta['language']),
    );
  }

  /// Seconds from `"3040.39"`, `"50:40"` or `"1:02:03"`; 0 when unknown.
  static double parseLength(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 0;
    if (!s.contains(':')) return double.tryParse(s) ?? 0;
    var total = 0.0;
    for (final p in s.split(':')) {
      final v = double.tryParse(p.trim());
      if (v == null) return 0;
      total = total * 60 + v;
    }
    return total;
  }

  /// LibriVox titles often end in a recording note — keep the book's name.
  static String cleanTitle(String t) => t
      .replaceAll(
          RegExp(r'\s*\((?:version|dramatic reading)[^)]*\)\s*$',
              caseSensitive: false),
          '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Description HTML (LibriVox uses `<p>`, `<br>`, links and entities) to
  /// plain paragraphs.
  static String htmlToText(String html) {
    if (html.trim().isEmpty) return '';
    final withBreaks = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n');
    final text = html_parser.parseFragment(withBreaks).text ?? '';
    return text
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// One [MediaItem] per chapter, in order, ready for the player queue.
  static List<MediaItem> toMediaItems(FreeAudiobookDetail d) {
    final author = d.book.author.isEmpty ? 'Audiobook' : d.book.author;
    final art = Uri.tryParse(d.book.cover);
    return [
      for (final c in d.chapters)
        MediaItem(
          id: '$freeAudiobookIdPrefix${d.book.id}_${c.index}',
          title: c.title,
          album: d.book.title,
          artist: author,
          duration: c.durationSec > 0
              ? Duration(milliseconds: (c.durationSec * 1000).round())
              : null,
          artUri: art,
          extras: {
            'url': c.url,
            'streamSource': 'librivox',
            'audiobookId': d.book.id,
            'audiobookTrackIndex': c.index,
            'audiobookTrackCount': d.chapters.length,
            'album': {'name': d.book.title, 'id': d.book.id},
            'artists': [
              {'name': author, 'id': null}
            ],
          },
        ),
    ];
  }

  static int _trackNo(dynamic raw) {
    // "01", "3", "3/24"
    final m = RegExp(r'\d+').firstMatch('${raw ?? ''}');
    return m == null ? 1 << 30 : int.parse(m.group(0)!);
  }

  static String _stem(String name) {
    final base = name.split('/').last;
    final dot = base.lastIndexOf('.');
    return (dot > 0 ? base.substring(0, dot) : base).replaceAll('_', ' ');
  }

  static String _first(dynamic v) {
    if (v is List) return v.isEmpty ? '' : _first(v.first);
    return v == null ? '' : '$v'.trim();
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
}
