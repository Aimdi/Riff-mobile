import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:xml/xml.dart';

import '/models/thumbnail.dart';
import '/utils/helper.dart';

/// Podcast support modelled on AntennaPod: discovery via Apple's public
/// podcast directory (the iTunes Search API, no key), subscriptions and
/// listen state stored locally (distributed / privacy-preserving — the
/// app never reports what you follow), episodes parsed straight from the
/// podcast's RSS feed. Episode audio is a direct enclosure URL, so it
/// plays through the normal pipeline without YouTube resolution.
class PodcastService {
  PodcastService._();

  static final _dio = Dio(BaseOptions(
    receiveTimeout: const Duration(seconds: 15),
    followRedirects: true,
    headers: {'user-agent': 'Riff/1.0 (podcast)'},
  ));

  static Box get _subs => Hive.box("PodcastSubs");

  /// The iTunes Search API replies with Content-Type text/javascript, so
  /// Dio hands back a String rather than a parsed Map. Decode defensively.
  static Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  // --- Discovery (Apple / iTunes Search API) ---

  /// Returns [{title, author, artwork, feedUrl}].
  static Future<List<Map<String, dynamic>>> search(String term) async {
    try {
      final res = await _dio.get('https://itunes.apple.com/search',
          queryParameters: {
            'media': 'podcast',
            'term': term,
            'limit': 40,
          });
      final results = _asMap(res.data)?['results'] as List?;
      if (results == null) return [];
      return results
          .where((r) => (r['feedUrl'] ?? '').toString().isNotEmpty)
          .map((r) {
            // Prefer 600px, then upscale mzstatic path to 3000×3000 for sharp player art.
            final raw = (r['artworkUrl600'] ??
                    r['artworkUrl100'] ??
                    r['artworkUrl60'] ??
                    '')
                .toString();
            return {
              'title': r['collectionName'] ?? r['trackName'] ?? '',
              'author': r['artistName'] ?? '',
              'artwork': Thumbnail(raw).extraHigh,
              'feedUrl': r['feedUrl'],
            };
          }).toList();
    } catch (e) {
      printERROR("Podcast search failed: $e");
      return [];
    }
  }

  /// Popular podcasts to seed an empty Podcasts screen (Apple top charts).
  static Future<List<Map<String, dynamic>>> topPodcasts() async {
    try {
      final res = await _dio.get(
          'https://itunes.apple.com/us/rss/toppodcasts/limit=25/json');
      final entries = _asMap(res.data)?['feed']?['entry'] as List?;
      if (entries == null) return [];
      return entries
          .map((e) {
            // Apple top-charts feed includes several im:image sizes; take the last
            // (largest) then upscale via Thumbnail for player-quality art.
            final images = e['im:image'] as List?;
            final raw = (images != null && images.isNotEmpty)
                ? (images.last['label'] ?? '').toString()
                : '';
            return {
              'title': e['im:name']?['label'] ?? '',
              'author': e['im:artist']?['label'] ?? '',
              'artwork': Thumbnail(raw).extraHigh,
              'collectionId': e['id']?['attributes']?['im:id'],
            };
          })
          .where((e) => e['collectionId'] != null)
          .toList();
    } catch (e) {
      printERROR("Top podcasts failed: $e");
      return [];
    }
  }

  /// Resolves a feed URL from an Apple collection id (top-charts entries
  /// don't include the feed URL directly).
  static Future<String?> feedUrlForCollection(String collectionId) async {
    try {
      final res = await _dio.get('https://itunes.apple.com/lookup',
          queryParameters: {'id': collectionId});
      final results = _asMap(res.data)?['results'] as List?;
      return results != null && results.isNotEmpty
          ? results.first['feedUrl']
          : null;
    } catch (_) {
      return null;
    }
  }

  // --- Similar podcasts ("popular with listeners of X") ---

  static final Map<String, List<Map<String, dynamic>>> _similarCache = {};

  /// Best-effort Apple storefront (country code) from the device locale, so a
  /// German/Spanish/etc. user gets that store's genre charts, not the US one.
  static String _storefront() {
    try {
      final m = RegExp(r'[_-]([A-Za-z]{2})').firstMatch(Platform.localeName);
      if (m != null) return m.group(1)!.toLowerCase();
    } catch (_) {}
    return 'us';
  }

  /// Podcasts in the same Apple genre as [title] — a no-key "popular with
  /// listeners of X" signal (no login, nothing reported). Pipeline: find the
  /// seed podcast on Apple to read its genre, pull that genre's top charts,
  /// drop the seed itself and anything already followed, then batch-resolve
  /// feed URLs so each result opens straight into its episode list.
  /// Returns [{title, author, artwork, feedUrl}].
  static Future<List<Map<String, dynamic>>> similar(String title,
      {int limit = 15}) async {
    final key = title.trim().toLowerCase();
    if (key.isEmpty) return [];
    final cached = _similarCache[key];
    if (cached != null) return cached;
    try {
      final cc = _storefront();
      // 1. Find the seed podcast on Apple to read its genre + id.
      final look = await _dio.get('https://itunes.apple.com/search',
          queryParameters: {
            'media': 'podcast',
            'term': title,
            'country': cc,
            'limit': 3,
          });
      final matches = _asMap(look.data)?['results'] as List?;
      if (matches == null || matches.isEmpty) return [];
      final src = matches.first as Map;
      final srcId = '${src['collectionId'] ?? src['trackId'] ?? ''}';
      final genreIds = (src['genreIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      // genreIds always carries "26" (root "Podcasts"); the real category is
      // the first non-root id.
      final genreId = genreIds.firstWhere((g) => g != '26',
          orElse: () => genreIds.isNotEmpty ? genreIds.first : '');
      if (genreId.isEmpty) return [];

      // 2. Top podcasts in that genre (popularity within the same category).
      final rss = await _dio.get(
          'https://itunes.apple.com/$cc/rss/toppodcasts/genre=$genreId/limit=50/json');
      final entries = _asMap(rss.data)?['feed']?['entry'] as List?;
      if (entries == null) return [];

      final followed = subscriptions.map((s) => '${s['feedUrl']}').toSet();
      final candidates = <Map<String, dynamic>>[];
      for (final e in entries) {
        if (e is! Map) continue;
        final id = '${e['id']?['attributes']?['im:id'] ?? ''}';
        if (id.isEmpty || id == srcId) continue;
        final images = e['im:image'] as List?;
        final raw = (images != null && images.isNotEmpty)
            ? '${images.last['label'] ?? ''}'
            : '';
        candidates.add({
          'collectionId': id,
          'title': '${e['im:name']?['label'] ?? ''}',
          'author': '${e['im:artist']?['label'] ?? ''}',
          'artwork': Thumbnail(raw).extraHigh,
        });
        if (candidates.length >= limit) break;
      }
      if (candidates.isEmpty) return [];

      // 3. Batch-resolve feed URLs (one lookup) — needed to open episodes.
      final ids = candidates.map((c) => c['collectionId']).join(',');
      final lk = await _dio.get('https://itunes.apple.com/lookup',
          queryParameters: {'id': ids});
      final results = _asMap(lk.data)?['results'] as List? ?? const [];
      final feedById = <String, String>{};
      for (final r in results) {
        if (r is Map && r['feedUrl'] != null) {
          feedById['${r['collectionId']}'] = '${r['feedUrl']}';
        }
      }

      final out = <Map<String, dynamic>>[];
      for (final c in candidates) {
        final feed = feedById['${c['collectionId']}'];
        if (feed == null || feed.isEmpty || followed.contains(feed)) continue;
        out.add({
          'title': c['title'],
          'author': c['author'],
          'artwork': c['artwork'],
          'feedUrl': feed,
        });
      }
      _similarCache[key] = out;
      return out;
    } catch (e) {
      printERROR("Similar podcasts failed: $e");
      return [];
    }
  }

  // --- Subscriptions ---

  static bool isSubscribed(String feedUrl) => _subs.containsKey(feedUrl);

  static Future<void> subscribe(Map<String, dynamic> podcast) =>
      _subs.put(podcast['feedUrl'], {
        'title': podcast['title'],
        'author': podcast['author'],
        'artwork': podcast['artwork'],
        'feedUrl': podcast['feedUrl'],
      });

  static Future<void> unsubscribe(String feedUrl) => _subs.delete(feedUrl);

  static List<Map<String, dynamic>> get subscriptions => _subs.values
      .map((v) => Map<String, dynamic>.from(v))
      .toList();

  // --- Feed parsing ---

  /// Fetches a podcast RSS feed and returns its episodes:
  /// [{id, title, description, url, artwork, date, durationSec, podcast}].
  static Future<List<Map<String, dynamic>>> episodes(
      String feedUrl, String podcastTitle, String fallbackArt) async {
    try {
      final res = await _dio.get(feedUrl,
          options: Options(responseType: ResponseType.plain));
      final doc = XmlDocument.parse(res.data as String);
      final channelArtRaw = doc
              .findAllElements('itunes:image')
              .map((e) => e.getAttribute('href'))
              .firstWhere((e) => e != null && e.isNotEmpty,
                  orElse: () => fallbackArt) ??
          fallbackArt;
      // Also try <image><url> (RSS 2.0 channel image).
      final rssImage = doc
          .findAllElements('image')
          .map((e) => e.getElement('url')?.innerText.trim())
          .firstWhere((e) => e != null && e.isNotEmpty, orElse: () => null);
      // Best channel-level art for episodes with no image of their own:
      // prefer the RSS 2.0 <image> then itunes:image, upscaled.
      final channelFallback = (rssImage != null && rssImage.isNotEmpty)
          ? rssImage
          : channelArtRaw;

      final items = doc.findAllElements('item');
      final episodes = <Map<String, dynamic>>[];
      for (final item in items) {
        final enclosure = item.findElements('enclosure').firstOrNull;
        final url = enclosure?.getAttribute('url');
        if (url == null || url.isEmpty) continue;
        final title = item.getElement('title')?.innerText.trim() ?? "Episode";
        final guid = item.getElement('guid')?.innerText.trim() ?? url;
        final sizeBytes =
            int.tryParse(enclosure?.getAttribute('length') ?? '') ?? 0;
        final epArtRaw = item
                .findElements('itunes:image')
                .firstOrNull
                ?.getAttribute('href') ??
            item
                .findElements('media:thumbnail')
                .firstOrNull
                ?.getAttribute('url') ??
            item
                .findElements('media:content')
                .map((e) => e.getAttribute('url'))
                .firstWhere(
                    (u) =>
                        u != null &&
                        (u.endsWith('.jpg') ||
                            u.endsWith('.png') ||
                            u.endsWith('.webp') ||
                            u.contains('image')),
                    orElse: () => null) ??
            channelFallback;
        episodes.add({
          'id': 'podcast_${guid.hashCode}',
          'title': title,
          'description': _stripHtml(
              item.getElement('description')?.innerText ?? ""),
          'url': url,
          'artwork': Thumbnail(epArtRaw).extraHigh,
          'date': _formatDate(item.getElement('pubDate')?.innerText.trim()),
          'sizeBytes': sizeBytes,
          'durationSec':
              _parseDuration(item.getElement('itunes:duration')?.innerText),
          'podcast': podcastTitle,
        });
      }
      return episodes;
    } catch (e) {
      printERROR("Feed parse failed ($feedUrl): $e");
      return [];
    }
  }

  static int _parseDuration(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    final t = raw.trim();
    if (!t.contains(':')) return int.tryParse(t) ?? 0;
    final parts = t.split(':').map((p) => int.tryParse(p) ?? 0).toList();
    if (parts.length == 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
    if (parts.length == 2) return parts[0] * 60 + parts[1];
    return 0;
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  /// RSS pubDate → "19 Jul 2026" (drops weekday and time for a compact row).
  static String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return "";
    try {
      // RFC-822: "Sat, 19 Jul 2026 08:00:00 +0000"
      final parts = raw.replaceFirst(RegExp(r'^\w+,\s*'), '').split(' ');
      if (parts.length >= 3) return "${parts[0]} ${parts[1]} ${parts[2]}";
    } catch (_) {}
    return raw;
  }

  /// enclosure length (bytes) → "42.3 MB" / "512 KB".
  static String formatSize(int bytes) {
    if (bytes <= 0) return "";
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return "${mb.toStringAsFixed(1)} MB";
    return "${(bytes / 1024).toStringAsFixed(0)} KB";
  }

  /// seconds → "1:02:33" / "42:10".
  static String formatDuration(int sec) {
    if (sec <= 0) return "";
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? "$h:${two(m)}:${two(s)}" : "$m:${two(s)}";
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
