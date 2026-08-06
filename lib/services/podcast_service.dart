import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
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
  static final _chaptersCache = <String, List<PodcastChapter>>{};

  /// Fetch Podcasting 2.0 chapters (JSON) for an episode. Used for ad auto-skip
  /// and the chapter jump button. Returns [] when unavailable.
  static Future<List<PodcastChapter>> chapters(String url) async {
    if (url.isEmpty) return [];
    final cached = _chaptersCache[url];
    if (cached != null) return cached;
    try {
      final res = await _dio.get(url);
      final list = _asMap(res.data)?['chapters'];
      if (list is! List) return [];
      final out = <PodcastChapter>[];
      for (final c in list) {
        if (c is! Map) continue;
        final st = c['startTime'];
        if (st is! num) continue;
        out.add(PodcastChapter(
          startSec: st.toDouble(),
          endSec: c['endTime'] is num ? (c['endTime'] as num).toDouble() : null,
          title: '${c['title'] ?? ''}',
        ));
      }
      out.sort((a, b) => a.startSec.compareTo(b.startSec));
      _chaptersCache[url] = out;
      return out;
    } catch (e) {
      printERROR('Chapters fetch failed: $e');
      return [];
    }
  }

  /// Preference order for `<podcast:transcript>` formats: the Podcasting 2.0
  /// JSON is richest (speakers + times), then SRT, then WebVTT; bare
  /// text/HTML parses without timestamps (no live sync).
  static int _transcriptTypeScore(String type, String url) {
    final u = url.toLowerCase();
    if (type.contains('json') || u.endsWith('.json')) return 4;
    if (type.contains('srt') || type.contains('subrip') || u.endsWith('.srt')) {
      return 3;
    }
    if (type.contains('vtt') || u.endsWith('.vtt')) return 2;
    if (type.contains('plain') || u.endsWith('.txt')) return 1;
    if (type.contains('html') || u.endsWith('.html')) return 0;
    return 1; // unknown type — still try to sniff-parse it
  }

  static final _transcriptCache = <String, List<PodcastTranscriptCue>>{};

  /// Fetch and parse a Podcasting 2.0 episode transcript into cues, coalesced
  /// into readable lines. Cues carry startSec = -1 when the source has no
  /// timestamps (plain text/HTML) — the viewer then skips live sync.
  /// Returns [] when unavailable or unparseable.
  static Future<List<PodcastTranscriptCue>> transcript(String url,
      {String type = ''}) async {
    if (url.isEmpty) return [];
    final cached = _transcriptCache[url];
    if (cached != null) return cached;
    try {
      final res = await _dio.get(url,
          options: Options(responseType: ResponseType.plain));
      final cues = parseTranscriptDocument('${res.data ?? ''}', type: type);
      _transcriptCache[url] = cues;
      return cues;
    } catch (e) {
      printERROR('Transcript fetch failed: $e');
      return [];
    }
  }

  /// Parse a transcript document (format sniffed from [type] and content)
  /// into display-ready cues. Public for unit tests.
  static List<PodcastTranscriptCue> parseTranscriptDocument(String raw,
      {String type = ''}) {
    final body = raw.trim();
    if (body.isEmpty) return [];
    List<PodcastTranscriptCue> cues;
    final t = type.toLowerCase();
    if (t.contains('json') || body.startsWith('{') || body.startsWith('[')) {
      cues = _parseJsonTranscript(body);
    } else if (body.startsWith('WEBVTT') || t.contains('vtt')) {
      cues = _parseTimedTranscript(body, isVtt: true);
    } else if (t.contains('srt') ||
        t.contains('subrip') ||
        RegExp(r'\d{2}:\d{2}:\d{2},\d{3}\s*-->').hasMatch(body)) {
      cues = _parseTimedTranscript(body, isVtt: false);
    } else {
      cues = _parsePlainTranscript(body, isHtml: t.contains('html'));
    }
    // A "timed" doc that yielded nothing may still be readable as text.
    if (cues.isEmpty && body.isNotEmpty) {
      cues = _parsePlainTranscript(body, isHtml: false);
    }
    if (cues.isNotEmpty && cues.first.startSec >= 0) {
      cues.sort((a, b) => a.startSec.compareTo(b.startSec));
      cues = _coalesceCues(cues);
    }
    return cues;
  }

  /// Podcasting 2.0 JSON transcript:
  /// {"segments": [{"speaker": "X", "startTime": 0.5, "endTime": 3, "body": ".."}]}
  static List<PodcastTranscriptCue> _parseJsonTranscript(String body) {
    try {
      final data = jsonDecode(body);
      final segments = data is Map ? data['segments'] : data;
      if (segments is! List) return [];
      final out = <PodcastTranscriptCue>[];
      for (final s in segments) {
        if (s is! Map) continue;
        final text = '${s['body'] ?? s['text'] ?? ''}'.trim();
        if (text.isEmpty) continue;
        final st = s['startTime'];
        out.add(PodcastTranscriptCue(
          startSec: st is num ? st.toDouble() : -1,
          endSec: s['endTime'] is num ? (s['endTime'] as num).toDouble() : null,
          speaker: s['speaker']?.toString(),
          text: text,
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// SRT and WebVTT share the shape: blocks with a "start --> end" timing
  /// line followed by text lines. VTT adds a header, NOTE/STYLE blocks and
  /// inline tags like `<v Speaker>`; SRT prefixes blocks with an index line.
  static List<PodcastTranscriptCue> _parseTimedTranscript(String body,
      {required bool isVtt}) {
    final out = <PodcastTranscriptCue>[];
    final blocks = body.replaceAll('\r\n', '\n').split(RegExp(r'\n{2,}'));
    for (final block in blocks) {
      final lines =
          block.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;
      if (isVtt &&
          (lines.first.startsWith('WEBVTT') ||
              lines.first.startsWith('NOTE') ||
              lines.first.startsWith('STYLE') ||
              lines.first.startsWith('REGION'))) {
        continue;
      }
      final timingIdx = lines.indexWhere((l) => l.contains('-->'));
      if (timingIdx < 0 || timingIdx + 1 > lines.length) continue;
      final timing = lines[timingIdx].split('-->');
      if (timing.length < 2) continue;
      final start = _parseTimestamp(timing[0]);
      // VTT may append cue settings ("align:start") after the end time.
      final end = _parseTimestamp(timing[1].trim().split(RegExp(r'\s+')).first);
      if (start == null) continue;
      var text = lines.skip(timingIdx + 1).join(' ').trim();
      String? speaker;
      final v = RegExp(r'^<v\s+([^>]+)>').firstMatch(text);
      if (v != null) speaker = v.group(1)?.trim();
      text = text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      // "Speaker: text" prefix (common in SRT transcripts).
      final sp = RegExp(r'^([A-Za-z][\w .\-]{0,30}):\s+(.*)$').firstMatch(text);
      if (speaker == null && sp != null && (sp.group(2) ?? '').isNotEmpty) {
        speaker = sp.group(1);
        text = sp.group(2)!;
      }
      if (text.isEmpty) continue;
      out.add(PodcastTranscriptCue(
          startSec: start, endSec: end, speaker: speaker, text: text));
    }
    return out;
  }

  /// "HH:MM:SS.mmm", "MM:SS.mmm" (VTT) or "HH:MM:SS,mmm" (SRT) → seconds.
  static double? _parseTimestamp(String raw) {
    final m = RegExp(r'(?:(\d+):)?(\d{1,2}):(\d{1,2})[.,](\d{1,3})')
        .firstMatch(raw.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '') ?? 0;
    final min = int.parse(m.group(2)!);
    final s = int.parse(m.group(3)!);
    final ms = int.parse(m.group(4)!.padRight(3, '0'));
    return h * 3600 + min * 60 + s + ms / 1000.0;
  }

  /// Plain text / HTML transcript: no timestamps, one cue per paragraph.
  static List<PodcastTranscriptCue> _parsePlainTranscript(String body,
      {required bool isHtml}) {
    var text = body;
    if (isHtml || text.contains('<p') || text.contains('<br')) {
      text = text
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
      text = stripHtml(text);
    }
    return text
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((p) => p.isNotEmpty)
        .map((p) => PodcastTranscriptCue(startSec: -1, text: p))
        .toList();
  }

  /// Merge caption-sized cues (SRT/VTT chop sentences into 1-3s chunks) into
  /// readable lines: same speaker, small gap, stop at sentence ends.
  static List<PodcastTranscriptCue> _coalesceCues(
      List<PodcastTranscriptCue> raw) {
    const maxChars = 200;
    const maxGapSec = 1.5;
    final sentenceEnd = RegExp(r'''[.!?…]["')\]]?$''');
    final out = <PodcastTranscriptCue>[];
    for (final c in raw) {
      final last = out.isEmpty ? null : out.last;
      final sameSpeaker = last != null &&
          (c.speaker == null ||
              last.speaker == null ||
              c.speaker == last.speaker);
      final gap = last == null
          ? double.infinity
          : c.startSec - (last.endSec ?? last.startSec);
      if (last != null &&
          sameSpeaker &&
          gap <= maxGapSec &&
          last.text.length + c.text.length + 1 <= maxChars &&
          !sentenceEnd.hasMatch(last.text)) {
        out[out.length - 1] = PodcastTranscriptCue(
          startSec: last.startSec,
          endSec: c.endSec ?? last.endSec,
          speaker: last.speaker ?? c.speaker,
          text: '${last.text} ${c.text}',
        );
      } else {
        out.add(c);
      }
    }
    return out;
  }

  /// Apple Podcasts' top-level categories (genre ids) for the browse grid.
  static const podcastGenres = <Map<String, String>>[
    {'id': '1489', 'name': 'News'},
    {'id': '1303', 'name': 'Comedy'},
    {'id': '1488', 'name': 'True Crime'},
    {'id': '1324', 'name': 'Society & Culture'},
    {'id': '1321', 'name': 'Business'},
    {'id': '1318', 'name': 'Technology'},
    {'id': '1512', 'name': 'History'},
    {'id': '1487', 'name': 'Health & Fitness'},
    {'id': '1533', 'name': 'Science'},
    {'id': '1304', 'name': 'Education'},
    {'id': '1310', 'name': 'Music'},
    {'id': '1545', 'name': 'Sports'},
    {'id': '1483', 'name': 'Fiction'},
    {'id': '1314', 'name': 'Religion & Spirituality'},
    {'id': '1502', 'name': 'Leisure'},
    {'id': '1309', 'name': 'TV & Film'},
    {'id': '1301', 'name': 'Arts'},
    {'id': '1305', 'name': 'Kids & Family'},
    {'id': '1511', 'name': 'Government'},
  ];

  static final _genreCache = <String, List<Map<String, dynamic>>>{};

  /// Top podcasts in an Apple genre (browse a category). Returns cards with a
  /// resolved feedUrl so they open straight in the episode list.
  static Future<List<Map<String, dynamic>>> topByGenre(String genreId,
      {int limit = 40}) async {
    if (genreId.isEmpty) return [];
    final cached = _genreCache[genreId];
    if (cached != null) return cached;
    try {
      final cc = _storefront();
      final rss = await _dio.get(
          'https://itunes.apple.com/$cc/rss/toppodcasts/genre=$genreId/limit=$limit/json');
      final entries = _asMap(rss.data)?['feed']?['entry'] as List?;
      if (entries == null) return [];
      final candidates = <Map<String, dynamic>>[];
      for (final e in entries) {
        if (e is! Map) continue;
        final id = '${e['id']?['attributes']?['im:id'] ?? ''}';
        if (id.isEmpty) continue;
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
      }
      if (candidates.isEmpty) return [];
      // Batch-resolve feed URLs (needed to open episodes).
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
        if (feed == null || feed.isEmpty) continue;
        out.add({
          'title': c['title'],
          'author': c['author'],
          'artwork': c['artwork'],
          'feedUrl': feed,
        });
      }
      _genreCache[genreId] = out;
      return out;
    } catch (e) {
      printERROR('Top podcasts by genre failed: $e');
      return [];
    }
  }

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

  /// Bumps whenever the subscription set changes, so Obx UIs (Subs grid,
  /// follow buttons) rebuild live. Read `subsRev.value` inside an Obx.
  static final subsRev = 0.obs;

  static bool isSubscribed(String feedUrl) => _subs.containsKey(feedUrl);

  static Future<void> subscribe(Map<String, dynamic> podcast) async {
    await _subs.put(podcast['feedUrl'], {
      'title': podcast['title'],
      'author': podcast['author'],
      'artwork': podcast['artwork'],
      'feedUrl': podcast['feedUrl'],
    });
    subsRev.value++;
  }

  static Future<void> unsubscribe(String feedUrl) async {
    await _subs.delete(feedUrl);
    subsRev.value++;
  }

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
        // Podcasting 2.0 chapters (used for ad auto-skip when present).
        final chaptersUrl = item
            .findElements('podcast:chapters')
            .firstOrNull
            ?.getAttribute('url');
        // Podcasting 2.0 transcript (Spotify-style transcript view). A feed
        // can list several formats; keep the one we parse best.
        String? transcriptUrl;
        String? transcriptType;
        var transcriptScore = -1;
        for (final t in item.findElements('podcast:transcript')) {
          final tUrl = t.getAttribute('url');
          if (tUrl == null || tUrl.isEmpty) continue;
          final tType = (t.getAttribute('type') ?? '').toLowerCase();
          final score = _transcriptTypeScore(tType, tUrl);
          if (score > transcriptScore) {
            transcriptScore = score;
            transcriptUrl = tUrl;
            transcriptType = tType;
          }
        }
        episodes.add({
          'id': 'podcast_${guid.hashCode}',
          'title': title,
          'description': stripHtml(
              item.getElement('description')?.innerText ?? ""),
          'url': url,
          'artwork': Thumbnail(epArtRaw).extraHigh,
          'date': _formatDate(item.getElement('pubDate')?.innerText.trim()),
          'sizeBytes': sizeBytes,
          'durationSec':
              _parseDuration(item.getElement('itunes:duration')?.innerText),
          'podcast': podcastTitle,
          if (chaptersUrl != null && chaptersUrl.isNotEmpty)
            'chaptersUrl': chaptersUrl,
          if (transcriptUrl != null) 'transcriptUrl': transcriptUrl,
          if (transcriptUrl != null) 'transcriptType': transcriptType ?? '',
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

  static const Map<String, String> _namedEntities = {
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    // Plain space, not U+00A0: shownotes render in a bare Text widget and a
    // no-break space would stop long runs from wrapping.
    'nbsp': ' ',
    'mdash': '—',
    'ndash': '–',
    'hellip': '…',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'bull': '•',
    'middot': '·',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'deg': '°',
    'laquo': '«',
    'raquo': '»',
    'amp': '&',
  };

  static final RegExp _entityRe =
      RegExp(r'&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);');

  /// Decodes HTML character references in a single left-to-right pass.
  ///
  /// Single pass is deliberate: shownotes are HTML *inside* XML, so the XML
  /// parser already undid one level of escaping. Re-scanning the output would
  /// turn a literal, author-intended "&amp;#39;" into an apostrophe.
  static String decodeHtmlEntities(String s) {
    if (!s.contains('&')) return s;
    return s.replaceAllMapped(_entityRe, (m) {
      final ref = m.group(1)!;
      if (ref.startsWith('#')) {
        final isHex = ref.length > 1 && (ref[1] == 'x' || ref[1] == 'X');
        final code = isHex
            ? int.tryParse(ref.substring(2), radix: 16)
            : int.tryParse(ref.substring(1));
        if (code == null || code < 0x9 || code > 0x10ffff) return m.group(0)!;
        // Lone surrogates are not valid scalar values.
        if (code >= 0xd800 && code <= 0xdfff) return m.group(0)!;
        return String.fromCharCode(code);
      }
      return _namedEntities[ref.toLowerCase()] ?? m.group(0)!;
    });
  }

  /// Removes markup and decodes character references, so feed descriptions and
  /// HTML transcripts render as text instead of raw "&amp;#8217;" codes.
  static String stripHtml(String s) =>
      decodeHtmlEntities(s.replaceAll(RegExp(r'<[^>]*>'), '')).trim();

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

/// One line of an episode transcript. [startSec] is -1 when the source
/// transcript has no timestamps (plain text/HTML).
class PodcastTranscriptCue {
  PodcastTranscriptCue(
      {required this.startSec, required this.text, this.endSec, this.speaker});
  final double startSec;
  final double? endSec;
  final String? speaker;
  final String text;
}

/// One Podcasting 2.0 chapter.
class PodcastChapter {
  PodcastChapter({required this.startSec, required this.title, this.endSec});
  final double startSec;
  final double? endSec;
  final String title;

  /// Whether this chapter looks like an ad / sponsor read (by title).
  bool get isAd {
    final t = title.toLowerCase();
    const needles = [
      'sponsor',
      'advert',
      'promo',
      'werbung', // de
      'anuncio', // es
    ];
    if (needles.any(t.contains)) return true;
    // Standalone "ad" / "ads" token.
    return RegExp(r'(^|\s)ads?(\s|:|$)').hasMatch(t);
  }
}
