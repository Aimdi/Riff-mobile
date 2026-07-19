import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:xml/xml.dart';

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
      final results = (res.data is Map ? res.data['results'] : null) as List?;
      if (results == null) return [];
      return results
          .where((r) => (r['feedUrl'] ?? '').toString().isNotEmpty)
          .map((r) => {
                'title': r['collectionName'] ?? r['trackName'] ?? '',
                'author': r['artistName'] ?? '',
                'artwork': r['artworkUrl600'] ?? r['artworkUrl100'] ?? '',
                'feedUrl': r['feedUrl'],
              })
          .toList();
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
      final entries = res.data?['feed']?['entry'] as List?;
      if (entries == null) return [];
      return entries
          .map((e) => {
                'title': e['im:name']?['label'] ?? '',
                'author': e['im:artist']?['label'] ?? '',
                'artwork': (e['im:image'] as List?)?.last?['label'] ?? '',
                'collectionId': e['id']?['attributes']?['im:id'],
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
      final results = res.data is Map ? res.data['results'] as List? : null;
      return results != null && results.isNotEmpty
          ? results.first['feedUrl']
          : null;
    } catch (_) {
      return null;
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
      final channelArt = doc
              .findAllElements('itunes:image')
              .map((e) => e.getAttribute('href'))
              .firstWhere((e) => e != null && e.isNotEmpty,
                  orElse: () => fallbackArt) ??
          fallbackArt;

      final items = doc.findAllElements('item');
      final episodes = <Map<String, dynamic>>[];
      for (final item in items) {
        final enclosure = item.findElements('enclosure').firstOrNull;
        final url = enclosure?.getAttribute('url');
        if (url == null || url.isEmpty) continue;
        final title = item.getElement('title')?.innerText.trim() ?? "Episode";
        final guid = item.getElement('guid')?.innerText.trim() ?? url;
        episodes.add({
          'id': 'podcast_${guid.hashCode}',
          'title': title,
          'description': _stripHtml(
              item.getElement('description')?.innerText ?? ""),
          'url': url,
          'artwork': item
                  .findElements('itunes:image')
                  .firstOrNull
                  ?.getAttribute('href') ??
              channelArt,
          'date': item.getElement('pubDate')?.innerText.trim() ?? "",
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
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
