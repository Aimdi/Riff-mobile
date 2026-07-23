import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:html/parser.dart' as html_parser;

import 'torrent_search_service.dart';

/// Shared Dio for public HTML indexers.
Dio _publicDio() => Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
        followRedirects: true,
        validateStatus: (s) => s != null && s < 500,
      ),
    );

/// Gazelle music trackers: Redacted / Orpheus (API key auth).
class GazelleTorrentService {
  GazelleTorrentService._({
    required this.source,
    required this.siteLink,
    required this.prefsKey,
    required this.authHeaderValue,
    required this.displayName,
  }) : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 25),
            headers: {
              'User-Agent': 'RiffMobile/1.0',
              'Accept': 'application/json',
            },
          ),
        );

  factory GazelleTorrentService.redacted({Dio? dio}) {
    final s = GazelleTorrentService._(
      source: TorrentSourceId.redacted,
      siteLink: 'https://redacted.sh/',
      prefsKey: 'redactedApiKey',
      authHeaderValue: (key) => key,
      displayName: 'Redacted',
    );
    if (dio != null) s._dio = dio;
    return s;
  }

  factory GazelleTorrentService.orpheus({Dio? dio}) {
    final s = GazelleTorrentService._(
      source: TorrentSourceId.orpheus,
      siteLink: 'https://orpheus.network/',
      prefsKey: 'orpheusApiKey',
      authHeaderValue: (key) => 'token $key',
      displayName: 'Orpheus',
    );
    if (dio != null) s._dio = dio;
    return s;
  }

  final TorrentSourceId source;
  final String siteLink;
  final String prefsKey;
  final String Function(String key) authHeaderValue;
  final String displayName;
  Dio _dio;

  static Box get _prefs => Hive.box('AppPrefs');

  String? get apiKey {
    final v = _prefs.get(prefsKey);
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  bool get isConfigured => apiKey != null;

  Future<void> saveApiKey(String key) async {
    await _prefs.put(prefsKey, key.trim());
  }

  Future<void> clearApiKey() async {
    await _prefs.delete(prefsKey);
  }

  Map<String, dynamic> get _authHeaders {
    final key = apiKey;
    if (key == null) return {};
    return {'Authorization': authHeaderValue(key)};
  }

  Future<void> verify() async {
    final key = apiKey;
    if (key == null) throw StateError('$displayName API key missing');
    final res = await _dio.get(
      '${siteLink}ajax.php',
      queryParameters: {'action': 'index'},
      options: Options(
        headers: _authHeaders,
        responseType: ResponseType.json,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw StateError('$displayName auth failed');
    }
    final data = res.data;
    if (data is Map && '${data['status']}' == 'failure') {
      throw StateError('${data['error'] ?? 'auth failed'}');
    }
  }

  /// Music + audiobooks (Gazelle cats 1 and 4).
  Future<List<TorrentHit>> search(String query) async {
    final q = query.trim();
    final key = apiKey;
    if (q.isEmpty || key == null) return [];

    final res = await _dio.get(
      '${siteLink}ajax.php',
      queryParameters: {
        'action': 'browse',
        'searchstr': q,
        'order_by': 'time',
        'order_way': 'desc',
        'filter_cat[1]': '1',
        'filter_cat[4]': '1',
      },
      options: Options(
        headers: _authHeaders,
        responseType: ResponseType.json,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw StateError('$displayName auth failed');
    }
    final data = res.data;
    if (data is! Map) return [];
    if ('${data['status']}' == 'failure') {
      throw StateError('${data['error'] ?? 'search failed'}');
    }
    final response = data['response'];
    if (response is! Map) return [];
    final results = response['results'];
    if (results is! List) return [];

    final hits = <TorrentHit>[];
    for (final raw in results) {
      if (raw is! Map) continue;
      final group = Map<String, dynamic>.from(raw);
      final artist = '${group['artist'] ?? ''}'.trim();
      final groupName = '${group['groupName'] ?? ''}'.trim();
      final year = '${group['groupYear'] ?? group['year'] ?? ''}'.trim();
      final releaseType = '${group['releaseType'] ?? ''}'.trim();
      final groupId = '${group['groupId'] ?? ''}'.trim();

      var baseTitle = groupName;
      if (artist.isNotEmpty) baseTitle = '$artist - $groupName';
      if (year.isNotEmpty && year != '0') baseTitle = '$baseTitle [$year]';
      if (releaseType.isNotEmpty && releaseType != 'Unknown') {
        baseTitle = '$baseTitle [$releaseType]';
      }

      final torrents = group['torrents'];
      if (torrents is List) {
        for (final tRaw in torrents) {
          if (tRaw is! Map) continue;
          final hit = _parseTorrent(
            Map<String, dynamic>.from(tRaw),
            baseTitle: baseTitle,
            groupId: groupId,
          );
          if (hit != null) hits.add(hit);
        }
      } else {
        final hit = _parseTorrent(group, baseTitle: baseTitle, groupId: groupId);
        if (hit != null) hits.add(hit);
      }
    }
    return hits;
  }

  TorrentHit? _parseTorrent(
    Map<String, dynamic> t, {
    required String baseTitle,
    required String groupId,
  }) {
    final torrentId = '${t['torrentId'] ?? ''}'.trim();
    if (torrentId.isEmpty) return null;

    final format = '${t['format'] ?? ''}'.trim();
    final encoding = '${t['encoding'] ?? ''}'.trim();
    final media = '${t['media'] ?? ''}'.trim();
    final flags = <String>[
      if (format.isNotEmpty) format,
      if (encoding.isNotEmpty) encoding,
      if (media.isNotEmpty) media,
    ];
    final name = flags.isEmpty ? baseTitle : '$baseTitle [${flags.join(' / ')}]';

    final size = _asInt(t['size']);
    final seeders = _asInt(t['seeders']);
    final leechers = _asInt(t['leechers']);
    final snatched = _asInt(t['snatched']);
    final time = '${t['time'] ?? ''}'.trim();
    final dateLabel = time.isEmpty ? '—' : time.split(' ').first;

    final details = groupId.isNotEmpty
        ? '${siteLink}torrents.php?id=$groupId&torrentid=$torrentId'
        : '${siteLink}torrents.php?torrentid=$torrentId';
    final downloadUrl =
        '${siteLink}ajax.php?action=download&id=$torrentId';

    return TorrentHit(
      name: name,
      infoHash: '',
      magnet: '',
      sizeLabel: size > 0 ? TorrentsDiggerService.formatSize(size) : '—',
      dateLabel: dateLabel,
      seeders: seeders,
      leechers: leechers,
      downloads: snatched,
      source: source,
      downloadUrl: downloadUrl,
      detailsUrl: details,
      needsAuthDownload: true,
    );
  }

  /// Fetch .torrent bytes with API key (for qBittorrent multipart upload).
  Future<List<int>> fetchTorrentBytes(String downloadUrl) async {
    final key = apiKey;
    if (key == null) throw StateError('$displayName API key missing');
    final res = await _dio.get<List<int>>(
      downloadUrl,
      options: Options(
        headers: _authHeaders,
        responseType: ResponseType.bytes,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (res.statusCode != 200 || res.data == null || res.data!.isEmpty) {
      throw StateError('$displayName download failed');
    }
    // Reject HTML error pages.
    if (res.data!.length > 4) {
      final head = String.fromCharCodes(res.data!.take(16));
      if (head.contains('<') || head.toLowerCase().contains('failure')) {
        throw StateError('$displayName download failed');
      }
    }
    return res.data!;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v'.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }
}

/// 1337x — public, Music category only.
class X1337TorrentService {
  X1337TorrentService({Dio? dio}) : _dio = dio ?? _publicDio();

  final Dio _dio;
  static const _hosts = [
    'https://1337x.to',
    'https://1337x.st',
    'https://x1337x.ws',
  ];

  Future<List<TorrentHit>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final encoded = Uri.encodeComponent(q).replaceAll('%20', '+');
    Object? lastError;
    for (final host in _hosts) {
      try {
        final url = '$host/category-search/$encoded/Music/1/';
        final res = await _dio.get<String>(url);
        if (res.statusCode != 200 || res.data == null) continue;
        final hits = _parseListing(res.data!, host);
        if (hits.isNotEmpty) return hits;
        // Empty can be valid; still accept if page parsed cleanly.
        if (res.data!.contains('coll-1') || res.data!.contains('/torrent/')) {
          return hits;
        }
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    return [];
  }

  List<TorrentHit> _parseListing(String body, String host) {
    final doc = html_parser.parse(body);
    final rows = doc.querySelectorAll('tr');
    final hits = <TorrentHit>[];
    for (final row in rows) {
      final link = row.querySelector('a[href^="/torrent/"]');
      if (link == null) continue;
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      var name = link.text.trim();
      if (name.contains('...')) {
        // Prefer slug from URL path.
        final parts = href.split('/');
        if (parts.length > 3) {
          final slug = Uri.decodeComponent(parts[3]).replaceAll('-', ' ');
          if (slug.isNotEmpty) name = slug;
        }
      }
      if (name.isEmpty) continue;

      final seedsText =
          row.querySelector('td[class^="coll-2"]')?.text.trim() ?? '0';
      final leechText =
          row.querySelector('td[class^="coll-3"]')?.text.trim() ?? '0';
      final sizeText =
          row.querySelector('td[class^="coll-4"]')?.text.trim() ?? '—';
      final dateText =
          row.querySelector('td[class^="coll-date"]')?.text.trim() ?? '—';

      hits.add(
        TorrentHit(
          name: name,
          infoHash: '',
          magnet: '',
          sizeLabel: sizeText.split('\n').first.trim(),
          dateLabel: dateText,
          seeders: int.tryParse(seedsText.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
          leechers:
              int.tryParse(leechText.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
          downloads: 0,
          source: TorrentSourceId.x1337,
          detailsUrl: '$host$href',
        ),
      );
    }
    return hits;
  }

  Future<String?> fetchMagnet(String detailsUrl) async {
    final res = await _dio.get<String>(detailsUrl);
    if (res.statusCode != 200 || res.data == null) return null;
    final doc = html_parser.parse(res.data);
    final a = doc.querySelector('a[href^="magnet:"]');
    final href = a?.attributes['href']?.trim();
    if (href != null && href.startsWith('magnet:')) return href;
    // Fallback: scan raw HTML.
    final m = RegExp(r'href="(magnet:\?[^"]+)"').firstMatch(res.data!);
    return m?.group(1);
  }
}

/// AudioBook Bay — public audiobook index.
class AudioBookBayService {
  AudioBookBayService({Dio? dio}) : _dio = dio ?? _publicDio();

  final Dio _dio;
  static const _hosts = [
    'https://audiobookbay.lu',
    'http://audiobookbay.lu',
    'http://audiobookbay.fi',
    'http://audiobookbay.se',
  ];

  Future<List<TorrentHit>> search(String query) async {
    final q = query.trim().toLowerCase().replaceAll(RegExp(r'[\W]+'), ' ').trim();
    if (q.isEmpty) return [];
    Object? lastError;
    for (final host in _hosts) {
      try {
        final res = await _dio.get<String>(
          host,
          queryParameters: {'s': q, 'tt': '1'},
        );
        if (res.statusCode != 200 || res.data == null) continue;
        final hits = _parseListing(res.data!, host);
        if (hits.isNotEmpty) return hits;
        if (res.data!.contains('postTitle') || res.data!.contains('post')) {
          return hits;
        }
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    return [];
  }

  List<TorrentHit> _parseListing(String body, String host) {
    final doc = html_parser.parse(body);
    final posts = doc.querySelectorAll('div.post');
    final hits = <TorrentHit>[];
    for (final post in posts) {
      final titleEl = post.querySelector('div.postTitle');
      if (titleEl == null) continue;
      final a = titleEl.querySelector('a');
      final href = a?.attributes['href']?.trim() ?? '';
      final name = (a?.text ?? titleEl.text).trim();
      if (name.isEmpty || href.isEmpty) continue;

      final content = post.querySelector('div.postContent')?.text ?? '';
      final sizeMatch =
          RegExp(r'File Size:\s*(.+?)(?:s?\s*$)', caseSensitive: false)
              .firstMatch(content);
      final dateMatch =
          RegExp(r'Posted:\s*(\d{1,2}\s+\w{3}\s+\d{4})', caseSensitive: false)
              .firstMatch(content);
      final details = href.startsWith('http')
          ? href
          : '$host/${href.replaceFirst(RegExp(r'^/'), '')}';

      hits.add(
        TorrentHit(
          name: name,
          infoHash: '',
          magnet: '',
          sizeLabel: sizeMatch?.group(1)?.trim() ?? '—',
          dateLabel: dateMatch?.group(1)?.trim() ?? '—',
          seeders: 1,
          leechers: 0,
          downloads: 0,
          source: TorrentSourceId.audioBookBay,
          detailsUrl: details,
        ),
      );
    }
    return hits;
  }

  Future<String?> fetchMagnet(String detailsUrl) async {
    final res = await _dio.get<String>(detailsUrl);
    if (res.statusCode != 200 || res.data == null) return null;
    final doc = html_parser.parse(res.data);
    final magnetA = doc.querySelector('a[href^="magnet:"]');
    final direct = magnetA?.attributes['href']?.trim();
    if (direct != null && direct.startsWith('magnet:')) return direct;

    // Info Hash cell → build public magnet.
    String? hash;
    for (final td in doc.querySelectorAll('td')) {
      if (td.text.toLowerCase().contains('info hash')) {
        final next = td.nextElementSibling?.text.trim();
        if (next != null && RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(next)) {
          hash = next.toLowerCase();
          break;
        }
      }
    }
    hash ??= RegExp(r'\b([a-fA-F0-9]{40})\b').firstMatch(res.data!)?.group(1)
        ?.toLowerCase();
    if (hash == null) return null;
    final title =
        doc.querySelector('div.postTitle h1')?.text.trim() ?? 'audiobook';
    return 'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(title)}';
  }
}

/// RuTracker.org — semi-private; music + audiobook forums. Optional session cookie.
class RuTrackerTorrentService {
  RuTrackerTorrentService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
                'Accept': 'text/html',
              },
              responseType: ResponseType.bytes,
              validateStatus: (s) => s != null && s < 500,
            ));

  final Dio _dio;
  static const _prefsKey = 'rutrackerCookie';
  static const _site = 'https://rutracker.org';

  /// Parent music + audiobook forum IDs (Jackett top-level Audio* mappings).
  static const _musicForums = [
    409, 1125, 1849, 408, 1760, 416, 1215, 782, 2495, 2497, 2499, 2267, 2268,
    2269, 1698, 1716, 1732, 722, 1821, 1807, 1808, 1809, 1810, 1811, 1299, 2219,
    860, 413, 2403, 2507, 2400, 518, 2236, 2413, 2326, 2389, 2327, 2324, 2328,
  ];

  static Box get _prefs => Hive.box('AppPrefs');

  static String? get cookie {
    final v = _prefs.get(_prefsKey);
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  static bool get isConfigured => cookie != null;

  static Future<void> saveCookie(String value) async {
    await _prefs.put(_prefsKey, value.trim());
  }

  static Future<void> clearCookie() async {
    await _prefs.delete(_prefsKey);
  }

  Future<void> verify() async {
    final c = cookie;
    if (c == null) throw StateError('RuTracker cookie missing');
    final res = await _dio.get(
      '$_site/forum/tracker.php',
      queryParameters: {'nm': 'test', 'f': '409'},
      options: Options(headers: {'Cookie': c}),
    );
    final body = _decode(res.data);
    if (body.contains('login.php') && !body.contains('logged-in-username')) {
      throw StateError('RuTracker auth failed');
    }
  }

  Future<List<TorrentHit>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    // Wildcard special chars like Jackett.
    final nm = q.replaceAll(RegExp(r'[^a-zA-Zа-яА-ЯёЁ0-9]+'), '%');
    final headers = <String, dynamic>{};
    final c = cookie;
    if (c != null) headers['Cookie'] = c;

    final res = await _dio.get(
      '$_site/forum/tracker.php',
      queryParameters: {
        'nm': nm,
        'f': _musicForums.join(','),
      },
      options: Options(headers: headers),
    );
    final body = _decode(res.data);
    return _parseListing(body);
  }

  List<TorrentHit> _parseListing(String body) {
    final doc = html_parser.parse(body);
    final rows = doc.querySelectorAll('table#tor-tbl > tbody > tr');
    final hits = <TorrentHit>[];
    for (final row in rows) {
      final titleA = row.querySelector('td.t-title-col a.tLink') ??
          row.querySelector('a.tLink');
      if (titleA == null) continue;
      final name = titleA.text.trim();
      final href = titleA.attributes['href'] ?? '';
      if (name.isEmpty) continue;

      final dl = row.querySelector('td.tor-size a.tr-dl');
      final sizeAttr = row.querySelector('td.tor-size')?.attributes['data-ts_text'];
      final sizeBytes = int.tryParse(sizeAttr ?? '') ?? 0;
      final sizeText = row.querySelector('td.tor-size')?.text.trim() ?? '—';

      final seedCell = row.querySelector('td:nth-child(7)');
      final seeders = int.tryParse(
            seedCell?.querySelector('b')?.text.trim() ??
                seedCell?.text.replaceAll(RegExp(r'[^0-9]'), '') ??
                '0',
          ) ??
          0;
      final leechers = int.tryParse(
            row
                    .querySelector('td:nth-child(8)')
                    ?.text
                    .replaceAll(RegExp(r'[^0-9]'), '') ??
                '0',
          ) ??
          0;
      final grabs = int.tryParse(
            row
                    .querySelector('td:nth-child(9)')
                    ?.text
                    .replaceAll(RegExp(r'[^0-9]'), '') ??
                '0',
          ) ??
          0;
      final dateTs = row.querySelector('td:nth-child(10)')?.attributes['data-ts_text'];
      final dateUnix = int.tryParse(dateTs ?? '') ?? 0;

      final detailsUrl = href.startsWith('http')
          ? href
          : '$_site/forum/${href.replaceFirst(RegExp(r'^/'), '')}';
      String? downloadUrl;
      if (dl != null) {
        final dh = dl.attributes['href'] ?? '';
        if (dh.isNotEmpty) {
          downloadUrl = dh.startsWith('http')
              ? dh
              : '$_site/forum/${dh.replaceFirst(RegExp(r'^/'), '')}';
        }
      }

      hits.add(
        TorrentHit(
          name: name,
          infoHash: '',
          magnet: '',
          sizeLabel: sizeBytes > 0
              ? TorrentsDiggerService.formatSize(sizeBytes)
              : sizeText,
          dateLabel: dateUnix > 0
              ? TorrentsDiggerService.formatDate(dateUnix)
              : '—',
          seeders: seeders,
          leechers: leechers,
          downloads: grabs,
          source: TorrentSourceId.ruTracker,
          downloadUrl: downloadUrl,
          detailsUrl: detailsUrl,
          needsAuthDownload: cookie != null && downloadUrl != null,
        ),
      );
    }
    return hits;
  }

  Future<String?> fetchMagnet(String detailsUrl) async {
    final headers = <String, dynamic>{};
    final c = cookie;
    if (c != null) headers['Cookie'] = c;
    final res = await _dio.get(detailsUrl, options: Options(headers: headers));
    final body = _decode(res.data);
    final m = RegExp(r'href="(magnet:\?[^"]+)"').firstMatch(body);
    if (m != null) return m.group(1);
    final doc = html_parser.parse(body);
    final a = doc.querySelector('a.magnet-link[href^="magnet:"]') ??
        doc.querySelector('a[href^="magnet:"]');
    return a?.attributes['href']?.trim();
  }

  /// Download .torrent bytes when cookie is configured.
  Future<List<int>> fetchTorrentBytes(String downloadUrl) async {
    final c = cookie;
    if (c == null) throw StateError('RuTracker cookie missing');
    final res = await _dio.get(
      downloadUrl,
      options: Options(
        headers: {'Cookie': c},
        responseType: ResponseType.bytes,
      ),
    );
    final data = res.data;
    if (data is! List<int> || data.isEmpty) {
      throw StateError('RuTracker download failed');
    }
    return data;
  }

  String _decode(dynamic data) {
    if (data is String) return data;
    if (data is List<int>) {
      try {
        return const Latin1Decoder(allowInvalid: true).convert(data);
      } catch (_) {
        return utf8.decode(data, allowMalformed: true);
      }
    }
    return '$data';
  }
}
