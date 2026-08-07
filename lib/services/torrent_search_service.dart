import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '/utils/secure_credentials.dart';
import 'torrent_extra_sources.dart';

/// Identifiers for torrent search backends (qBittorrent search-plugin style).
enum TorrentSourceId {
  torrentsCsv,
  myAnonamouse,
  redacted,
  orpheus,
  x1337,
  ruTracker,
  audioBookBay,
}

extension TorrentSourceIdX on TorrentSourceId {
  String get prefsKey {
    switch (this) {
      case TorrentSourceId.torrentsCsv:
        return 'torrents_csv';
      case TorrentSourceId.myAnonamouse:
        return 'myanonamouse';
      case TorrentSourceId.redacted:
        return 'redacted';
      case TorrentSourceId.orpheus:
        return 'orpheus';
      case TorrentSourceId.x1337:
        return '1337x';
      case TorrentSourceId.ruTracker:
        return 'rutracker';
      case TorrentSourceId.audioBookBay:
        return 'audiobookbay';
    }
  }

  String get labelKey {
    switch (this) {
      case TorrentSourceId.torrentsCsv:
        return 'torrentSourceTorrentsCsv';
      case TorrentSourceId.myAnonamouse:
        return 'torrentSourceMam';
      case TorrentSourceId.redacted:
        return 'torrentSourceRedacted';
      case TorrentSourceId.orpheus:
        return 'torrentSourceOrpheus';
      case TorrentSourceId.x1337:
        return 'torrentSource1337x';
      case TorrentSourceId.ruTracker:
        return 'torrentSourceRuTracker';
      case TorrentSourceId.audioBookBay:
        return 'torrentSourceAbb';
    }
  }

  static TorrentSourceId? fromPrefs(String key) {
    switch (key) {
      case 'torrents_csv':
        return TorrentSourceId.torrentsCsv;
      case 'myanonamouse':
        return TorrentSourceId.myAnonamouse;
      case 'redacted':
        return TorrentSourceId.redacted;
      case 'orpheus':
        return TorrentSourceId.orpheus;
      case '1337x':
        return TorrentSourceId.x1337;
      case 'rutracker':
        return TorrentSourceId.ruTracker;
      case 'audiobookbay':
        return TorrentSourceId.audioBookBay;
      default:
        return null;
    }
  }
}

/// A single torrent hit from any configured source.
class TorrentHit {
  const TorrentHit({
    required this.name,
    required this.infoHash,
    required this.magnet,
    required this.sizeLabel,
    required this.dateLabel,
    required this.seeders,
    required this.leechers,
    required this.downloads,
    required this.source,
    this.downloadUrl,
    this.detailsUrl,
    this.needsAuthDownload = false,
  });

  final String name;
  final String infoHash;
  final String magnet;
  final String sizeLabel;
  final String dateLabel;
  final int seeders;
  final int leechers;
  final int downloads;
  final TorrentSourceId source;

  /// Auth-aware or hash download URL (MAM / Gazelle / RuTracker).
  final String? downloadUrl;

  /// Details page used to scrape a magnet (1337x, ABB, RuTracker).
  final String? detailsUrl;

  /// When true, [downloadUrl] must be fetched with source credentials.
  final bool needsAuthDownload;

  bool get hasMagnet => magnet.startsWith('magnet:');
  bool get hasDownloadUrl =>
      downloadUrl != null && downloadUrl!.trim().isNotEmpty;

  /// Best URI to hand to an external client / qBittorrent.
  String get openUrl {
    if (hasMagnet) return magnet;
    if (hasDownloadUrl && !needsAuthDownload) return downloadUrl!.trim();
    return detailsUrl?.trim() ?? downloadUrl?.trim() ?? '';
  }

  TorrentHit copyWith({
    String? name,
    String? infoHash,
    String? magnet,
    String? sizeLabel,
    String? dateLabel,
    int? seeders,
    int? leechers,
    int? downloads,
    TorrentSourceId? source,
    String? downloadUrl,
    String? detailsUrl,
    bool? needsAuthDownload,
  }) {
    return TorrentHit(
      name: name ?? this.name,
      infoHash: infoHash ?? this.infoHash,
      magnet: magnet ?? this.magnet,
      sizeLabel: sizeLabel ?? this.sizeLabel,
      dateLabel: dateLabel ?? this.dateLabel,
      seeders: seeders ?? this.seeders,
      leechers: leechers ?? this.leechers,
      downloads: downloads ?? this.downloads,
      source: source ?? this.source,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      detailsUrl: detailsUrl ?? this.detailsUrl,
      needsAuthDownload: needsAuthDownload ?? this.needsAuthDownload,
    );
  }
}

/// A single torrent hit from a Torrents Digger–style search.
/// Search torrents using the same public Torrents.csv API that
/// [Torrents Digger](https://gitlab.com/ForTheCommunity/torrentsdigger) uses.
///
/// Riff does not host torrent content — this only queries a public index and
/// returns magnet links the user can open in their own torrent client.
class TorrentsDiggerService {
  TorrentsDiggerService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const _root = 'https://torrents-csv.com';

  /// Search [query]. Optional [after] is the pagination cursor from a prior
  /// response (`next` field).
  Future<({List<TorrentHit> torrents, int? next})> search(
    String query, {
    int? after,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return (torrents: <TorrentHit>[], next: null);
    }

    final params = <String, dynamic>{'q': q};
    if (after != null) params['after'] = after;

    final res = await _dio.get<Map<String, dynamic>>(
      '$_root/service/search',
      queryParameters: params,
      options: Options(
        responseType: ResponseType.json,
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 15),
      ),
    );

    final root = res.data ?? const <String, dynamic>{};
    final list = (root['torrents'] as List? ?? const []);
    final next = root['next'] is int
        ? root['next'] as int
        : int.tryParse('${root['next'] ?? ''}');

    final torrents = list
        .map((e) => _parseHit(Map<String, dynamic>.from(e as Map)))
        .whereType<TorrentHit>()
        .toList();

    return (torrents: torrents, next: next);
  }

  TorrentHit? _parseHit(Map<String, dynamic> json) {
    final infoHash = '${json['infohash'] ?? ''}'.trim();
    final name = '${json['name'] ?? ''}'.trim();
    if (infoHash.isEmpty || name.isEmpty) return null;

    final sizeBytes = _asInt(json['size_bytes']);
    final createdUnix = _asInt(json['created_unix']);
    final seeders = _asInt(json['seeders']);
    final leechers = _asInt(json['leechers']);
    final completed = _asInt(json['completed']);

    final encodedName = Uri.encodeComponent(name);
    final magnet = 'magnet:?xt=urn:btih:$infoHash&dn=$encodedName';

    return TorrentHit(
      name: name,
      infoHash: infoHash,
      magnet: magnet,
      sizeLabel: formatSize(sizeBytes),
      dateLabel: formatDate(createdUnix),
      seeders: seeders,
      leechers: leechers,
      downloads: completed,
      source: TorrentSourceId.torrentsCsv,
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static String formatSize(int bytes) {
    if (bytes <= 0) return '—';
    const kb = 1000.0;
    const mb = kb * 1000;
    const gb = mb * 1000;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  static String formatDate(int unix) {
    if (unix <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// MyAnonamouse JSON search (optional private source).
/// Auth: dedicated `mam_id` session cookie from Preferences → Security.
/// Cookie may rotate on each response — we persist the latest value.
class MamTorrentService {
  MamTorrentService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              headers: {
                'User-Agent': 'RiffMobile/1.0',
                'Accept': 'application/json',
              },
            ));

  final Dio _dio;
  static const _searchUrl =
      'https://www.myanonamouse.net/tor/js/loadSearchJSONbasic.php';
  static const _prefsKey = 'mamId';

  static String? get mamId {
    final v = SecureCredentials.get(_prefsKey);
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  static bool get isConfigured => mamId != null;

  static Future<void> saveMamId(String id) async {
    await SecureCredentials.set(_prefsKey, id.trim());
  }

  static Future<void> clearMamId() async {
    await SecureCredentials.delete(_prefsKey);
  }

  Future<void> _persistRotatedCookie(Response res) async {
    final setCookie = res.headers.map['set-cookie'];
    if (setCookie == null) return;
    for (final line in setCookie) {
      final m = RegExp(r'mam_id=([^;]+)').firstMatch(line);
      if (m != null) {
        final next = Uri.decodeComponent(m.group(1)!).trim();
        if (next.isNotEmpty) await saveMamId(next);
        return;
      }
    }
  }

  /// Soft auth check — tiny search. Throws on failure.
  Future<void> verify() async {
    final id = mamId;
    if (id == null) throw StateError('mam_id missing');
    final res = await _dio.get(
      _searchUrl,
      queryParameters: {
        'tor[text]': 'test',
        'tor[srchIn][title]': 'true',
        'tor[searchType]': 'all',
        'tor[searchIn]': 'torrents',
        'tor[cat][]': '0',
        'perpage': '5',
        'startNumber': '0',
      },
      options: Options(
        headers: {'Cookie': 'mam_id=$id'},
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    await _persistRotatedCookie(res);
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw StateError('MAM auth failed');
    }
    if (res.data is String &&
        '${res.data}'.toLowerCase().contains('login')) {
      throw StateError('MAM auth failed');
    }
  }

  Future<List<TorrentHit>> search(String query, {int start = 0}) async {
    final q = query.trim();
    final id = mamId;
    if (q.isEmpty || id == null) return [];

    final res = await _dio.get(
      _searchUrl,
      queryParameters: {
        'tor[text]': q,
        'tor[srchIn][title]': 'true',
        'tor[srchIn][author]': 'true',
        'tor[srchIn][narrator]': 'true',
        'tor[searchType]': 'all',
        'tor[searchIn]': 'torrents',
        'tor[cat][]': '0',
        'tor[sortType]': 'default',
        'tor[startNumber]': '$start',
        'perpage': '50',
        'thumbnail': 'true',
      },
      options: Options(
        headers: {'Cookie': 'mam_id=$id'},
        responseType: ResponseType.json,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    await _persistRotatedCookie(res);
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw StateError('MAM auth failed');
    }

    final data = res.data;
    Map<String, dynamic>? root;
    if (data is Map) {
      root = Map<String, dynamic>.from(data);
    } else if (data is String) {
      // Sometimes mislabeled content-type.
      return [];
    }
    if (root == null) return [];

    final list = root['data'] ?? root['torrents'] ?? root['results'];
    if (list is! List) return [];

    return list
        .map((e) => e is Map
            ? _parseHit(Map<String, dynamic>.from(e))
            : null)
        .whereType<TorrentHit>()
        .toList();
  }

  TorrentHit? _parseHit(Map<String, dynamic> json) {
    final title = '${json['title'] ?? json['name'] ?? ''}'.trim();
    if (title.isEmpty) return null;

    final tid = '${json['id'] ?? json['tid'] ?? ''}'.trim();
    final hash = '${json['hash'] ?? json['infohash'] ?? json['infoHash'] ?? ''}'
        .trim()
        .toLowerCase();
    final dlHash = '${json['dl'] ?? json['dlLink'] ?? ''}'.trim();

    String magnet = '';
    if (hash.isNotEmpty && RegExp(r'^[a-f0-9]{40}$').hasMatch(hash)) {
      magnet =
          'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(title)}';
    }

    String? downloadUrl;
    if (dlHash.isNotEmpty) {
      downloadUrl = 'https://www.myanonamouse.net/tor/download.php/$dlHash';
    } else if (tid.isNotEmpty) {
      downloadUrl = 'https://www.myanonamouse.net/tor/download.php?tid=$tid';
    }

    final sizeBytes = _asInt(json['size'] ?? json['sizebytes'] ?? json['filesize']);
    final seeders = _asInt(json['seeders'] ?? json['seeds']);
    final leechers = _asInt(json['leechers'] ?? json['leeches']);
    final snatched = _asInt(json['times_completed'] ?? json['snatched'] ?? json['completed']);
    final added = '${json['added'] ?? json['cat'] ?? json['updated'] ?? ''}'.trim();

    return TorrentHit(
      name: title,
      infoHash: hash,
      magnet: magnet,
      sizeLabel: sizeBytes > 0
          ? TorrentsDiggerService.formatSize(sizeBytes)
          : '${json['size'] ?? '—'}',
      dateLabel: added.isEmpty ? '—' : added.split(' ').first,
      seeders: seeders,
      leechers: leechers,
      downloads: snatched,
      source: TorrentSourceId.myAnonamouse,
      downloadUrl: downloadUrl,
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = '$v'.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(s) ?? 0;
  }
}

/// Optional qBittorrent WebUI client — add magnets / download URLs remotely.
class QBittorrentService {
  QBittorrentService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const _urlKey = 'qbitUrl';
  static const _userKey = 'qbitUser';
  static const _passKey = 'qbitPass';

  static Box get _prefs => Hive.box('AppPrefs');

  static String? get baseUrl {
    final v = _prefs.get(_urlKey);
    if (v is String && v.trim().isNotEmpty) {
      return v.trim().replaceAll(RegExp(r'/+$'), '');
    }
    return null;
  }

  static String get username => '${_prefs.get(_userKey) ?? 'admin'}';
  static String get password => SecureCredentials.get(_passKey) ?? '';
  static bool get isConfigured => baseUrl != null && password.isNotEmpty;

  static Future<void> save({
    required String url,
    required String username,
    required String password,
  }) async {
    await _prefs.put(_urlKey, url.trim());
    await _prefs.put(_userKey, username.trim());
    await SecureCredentials.set(_passKey, password);
  }

  static Future<void> clear() async {
    await _prefs.delete(_urlKey);
    await _prefs.delete(_userKey);
    await SecureCredentials.delete(_passKey);
  }

  static String? _sidFromResponse(Response res) {
    final setCookie = res.headers.map['set-cookie'];
    if (setCookie == null) return null;
    for (final line in setCookie) {
      final m = RegExp(r'SID=([^;]+)').firstMatch(line);
      if (m != null) return m.group(1);
    }
    // Some setups also send SID in Cookie header echo
    final cookie = res.headers.value('set-cookie');
    if (cookie != null) {
      final m = RegExp(r'SID=([^;]+)').firstMatch(cookie);
      if (m != null) return m.group(1);
    }
    return null;
  }

  /// Login and return session SID. Throws on failure.
  Future<String> login() async {
    final root = baseUrl;
    if (root == null) throw StateError('qBittorrent URL missing');
    final res = await _dio.post(
      '$root/api/v2/auth/login',
      data: 'username=${Uri.encodeQueryComponent(username)}'
          '&password=${Uri.encodeQueryComponent(password)}',
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (res.statusCode != 200 || '${res.data}'.trim() != 'Ok.') {
      throw StateError('qBittorrent login failed');
    }
    final sid = _sidFromResponse(res);
    if (sid == null || sid.isEmpty) {
      // Some reverse proxies omit Set-Cookie; still treat Ok. as success.
      return '';
    }
    return sid;
  }

  /// Add a magnet or http(s) torrent URL to qBittorrent.
  Future<void> addUrl(String url) async {
    final u = url.trim();
    if (u.isEmpty) throw StateError('empty url');
    final root = baseUrl;
    if (root == null) throw StateError('qBittorrent URL missing');
    final sid = await login();
    final headers = <String, dynamic>{};
    if (sid.isNotEmpty) headers['Cookie'] = 'SID=$sid';
    final res = await _dio.post(
      '$root/api/v2/torrents/add',
      data: FormData.fromMap({'urls': u}),
      options: Options(
        headers: headers,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (res.statusCode != 200) {
      throw StateError('qBittorrent add failed (${res.statusCode})');
    }
  }

  /// Upload a .torrent file (for private trackers that need authenticated download).
  Future<void> addTorrentFile(List<int> bytes, {String filename = 'file.torrent'}) async {
    if (bytes.isEmpty) throw StateError('empty torrent');
    final root = baseUrl;
    if (root == null) throw StateError('qBittorrent URL missing');
    final sid = await login();
    final headers = <String, dynamic>{};
    if (sid.isNotEmpty) headers['Cookie'] = 'SID=$sid';
    final res = await _dio.post(
      '$root/api/v2/torrents/add',
      data: FormData.fromMap({
        'torrents': MultipartFile.fromBytes(bytes, filename: filename),
      }),
      options: Options(
        headers: headers,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (res.statusCode != 200) {
      throw StateError('qBittorrent add failed (${res.statusCode})');
    }
  }
}

/// Facade: search selected sources (qBittorrent-style multi-indexer).
class TorrentSearchFacade {
  TorrentSearchFacade({
    TorrentsDiggerService? torrentsCsv,
    MamTorrentService? mam,
    GazelleTorrentService? redacted,
    GazelleTorrentService? orpheus,
    X1337TorrentService? x1337,
    RuTrackerTorrentService? ruTracker,
    AudioBookBayService? abb,
  })  : _csv = torrentsCsv ?? TorrentsDiggerService(),
        _mam = mam ?? MamTorrentService(),
        _redacted = redacted ?? GazelleTorrentService.redacted(),
        _orpheus = orpheus ?? GazelleTorrentService.orpheus(),
        _x1337 = x1337 ?? X1337TorrentService(),
        _ruTracker = ruTracker ?? RuTrackerTorrentService(),
        _abb = abb ?? AudioBookBayService();

  final TorrentsDiggerService _csv;
  final MamTorrentService _mam;
  final GazelleTorrentService _redacted;
  final GazelleTorrentService _orpheus;
  final X1337TorrentService _x1337;
  final RuTrackerTorrentService _ruTracker;
  final AudioBookBayService _abb;

  static const _sourcesKey = 'torrentSearchSources';

  static Set<TorrentSourceId> enabledSources() {
    final raw = Hive.box('AppPrefs').get(_sourcesKey);
    if (raw is List && raw.isNotEmpty) {
      final out = <TorrentSourceId>{};
      for (final e in raw) {
        final id = TorrentSourceIdX.fromPrefs('$e');
        if (id != null) out.add(id);
      }
      if (out.isNotEmpty) return out;
    }
    return {TorrentSourceId.torrentsCsv};
  }

  static Future<void> setEnabledSources(Set<TorrentSourceId> sources) async {
    final list = sources.map((e) => e.prefsKey).toList();
    if (list.isEmpty) list.add(TorrentSourceId.torrentsCsv.prefsKey);
    await Hive.box('AppPrefs').put(_sourcesKey, list);
  }

  Future<({List<TorrentHit> torrents, int? csvNext, String? error})> search(
    String query, {
    required Set<TorrentSourceId> sources,
    int? csvAfter,
  }) async {
    final q = query.trim();
    if (q.isEmpty || sources.isEmpty) {
      return (torrents: <TorrentHit>[], csvNext: null, error: null);
    }

    int? csvNext;
    final errors = <String>[];
    final parts = <List<TorrentHit>>[];

    final futures = <Future>[];

    void addSource(
      bool enabled,
      String label,
      Future<List<TorrentHit>> Function() run, {
      bool Function()? configured,
    }) {
      if (!enabled) return;
      futures.add(() async {
        if (configured != null && !configured()) {
          errors.add('$label (not configured)');
          return;
        }
        try {
          parts.add(await run());
        } catch (_) {
          errors.add(label);
        }
      }());
    }

    if (sources.contains(TorrentSourceId.torrentsCsv)) {
      futures.add(() async {
        try {
          final res = await _csv.search(q, after: csvAfter);
          parts.add(res.torrents);
          csvNext = res.next;
        } catch (_) {
          errors.add('Torrents.csv');
        }
      }());
    }

    addSource(
      sources.contains(TorrentSourceId.myAnonamouse),
      'MyAnonamouse',
      () => _mam.search(q),
      configured: () => MamTorrentService.isConfigured,
    );
    addSource(
      sources.contains(TorrentSourceId.redacted),
      'Redacted',
      () => _redacted.search(q),
      configured: () => _redacted.isConfigured,
    );
    addSource(
      sources.contains(TorrentSourceId.orpheus),
      'Orpheus',
      () => _orpheus.search(q),
      configured: () => _orpheus.isConfigured,
    );
    addSource(
      sources.contains(TorrentSourceId.x1337),
      '1337x',
      () => _x1337.search(q),
    );
    addSource(
      sources.contains(TorrentSourceId.ruTracker),
      'RuTracker',
      () => _ruTracker.search(q),
    );
    addSource(
      sources.contains(TorrentSourceId.audioBookBay),
      'AudioBook Bay',
      () => _abb.search(q),
    );

    await Future.wait(futures);

    final results = <TorrentHit>[for (final p in parts) ...p];
    results.sort((a, b) => b.seeders.compareTo(a.seeders));

    return (
      torrents: results,
      csvNext: csvNext,
      error: errors.isEmpty ? null : errors.join(', '),
    );
  }

  /// Resolve magnet / openable URL for sources that only return a details page.
  Future<TorrentHit> resolve(TorrentHit hit) async {
    if (hit.hasMagnet) return hit;
    final details = hit.detailsUrl?.trim();
    if (details == null || details.isEmpty) return hit;

    String? magnet;
    switch (hit.source) {
      case TorrentSourceId.x1337:
        magnet = await _x1337.fetchMagnet(details);
        break;
      case TorrentSourceId.audioBookBay:
        magnet = await _abb.fetchMagnet(details);
        break;
      case TorrentSourceId.ruTracker:
        magnet = await _ruTracker.fetchMagnet(details);
        break;
      default:
        break;
    }
    if (magnet == null || !magnet.startsWith('magnet:')) return hit;
    return hit.copyWith(magnet: magnet);
  }

  /// Send hit to qBittorrent — magnets/URLs, or authenticated .torrent upload.
  Future<void> sendToQbit(TorrentHit hit) async {
    final qbit = QBittorrentService();
    if (hit.needsAuthDownload && hit.hasDownloadUrl) {
      final bytes = await _fetchAuthTorrent(hit);
      await qbit.addTorrentFile(bytes, filename: '${hit.source.prefsKey}.torrent');
      return;
    }
    final resolved = await resolve(hit);
    final url = resolved.openUrl;
    if (url.isEmpty) throw StateError('no link');
    await qbit.addUrl(url);
  }

  Future<List<int>> _fetchAuthTorrent(TorrentHit hit) async {
    final url = hit.downloadUrl!.trim();
    switch (hit.source) {
      case TorrentSourceId.redacted:
        return _redacted.fetchTorrentBytes(url);
      case TorrentSourceId.orpheus:
        return _orpheus.fetchTorrentBytes(url);
      case TorrentSourceId.ruTracker:
        return _ruTracker.fetchTorrentBytes(url);
      default:
        throw StateError('auth download unsupported for ${hit.source}');
    }
  }
}
