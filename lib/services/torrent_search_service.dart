import 'package:dio/dio.dart';

/// A single torrent hit from a public index search.
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
  });

  final String name;
  final String infoHash;
  final String magnet;
  final String sizeLabel;
  final String dateLabel;
  final int seeders;
  final int leechers;
  final int downloads;
}

/// Thrown when a search cannot be performed (validation or API error).
class TorrentSearchException implements Exception {
  TorrentSearchException(this.message, {this.tooShort = false});

  final String message;
  final bool tooShort;

  @override
  String toString() => message;
}

/// Search public torrent indexes via the [Torrents.csv](https://torrents-csv.com)
/// API and return magnet links the user can open in their own client.
///
/// Riff does not host or download torrent payloads.
class TorrentSearchService {
  TorrentSearchService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 25),
                sendTimeout: const Duration(seconds: 15),
                headers: const {
                  'Accept': 'application/json',
                  'User-Agent': 'RiffMobile/1.0 (torrent-search)',
                },
                responseType: ResponseType.json,
                validateStatus: (code) => code != null && code < 500,
              ),
            );

  final Dio _dio;

  static const minQueryLength = 3;
  static const _roots = <String>[
    'https://torrents-csv.com',
    // Fallback mirror used by some self-hosted deployments / older docs.
    'https://torrents-csv.ml',
  ];

  static const _trackers = <String>[
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://open.tracker.cl:1337/announce',
  ];

  /// Search [query]. Optional [after] is the pagination cursor from a prior
  /// response (`next` field). Queries shorter than [minQueryLength] are
  /// rejected — the API returns HTTP 400 for them.
  Future<({List<TorrentHit> torrents, int? next})> search(
    String query, {
    int? after,
    int size = 50,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return (torrents: <TorrentHit>[], next: null);
    }
    if (q.length < minQueryLength) {
      throw TorrentSearchException(
        'Query must be at least $minQueryLength characters',
        tooShort: true,
      );
    }

    final params = <String, dynamic>{
      'q': q,
      'size': size.clamp(1, 100),
    };
    if (after != null) params['after'] = after;

    DioException? lastNetworkError;
    for (final root in _roots) {
      try {
        final res = await _dio.get<dynamic>(
          '$root/service/search',
          queryParameters: params,
        );

        final code = res.statusCode ?? 0;
        if (code == 400) {
          throw TorrentSearchException(
            'Query must be at least $minQueryLength characters',
            tooShort: true,
          );
        }
        if (code < 200 || code >= 300) {
          // Try next mirror.
          lastNetworkError = DioException(
            requestOptions: res.requestOptions,
            response: res,
            type: DioExceptionType.badResponse,
            message: 'HTTP $code',
          );
          continue;
        }

        final rootMap = _asMap(res.data);
        if (rootMap == null) {
          lastNetworkError = DioException(
            requestOptions: res.requestOptions,
            response: res,
            type: DioExceptionType.badResponse,
            message: 'Unexpected response',
          );
          continue;
        }

        final list = rootMap['torrents'];
        final items = list is List ? list : const [];
        final next = rootMap['next'] is int
            ? rootMap['next'] as int
            : int.tryParse('${rootMap['next'] ?? ''}');

        final torrents = items
            .map((e) {
              final m = _asMap(e);
              return m == null ? null : _parseHit(m);
            })
            .whereType<TorrentHit>()
            .toList();

        return (torrents: torrents, next: next);
      } on TorrentSearchException {
        rethrow;
      } on DioException catch (e) {
        lastNetworkError = e;
        // Try next mirror.
      }
    }

    throw TorrentSearchException(
      lastNetworkError?.message ?? 'Search failed',
    );
  }

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
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
    final trackerQs = _trackers
        .map((t) => 'tr=${Uri.encodeComponent(t)}')
        .join('&');
    final magnet =
        'magnet:?xt=urn:btih:$infoHash&dn=$encodedName&$trackerQs';

    return TorrentHit(
      name: name,
      infoHash: infoHash,
      magnet: magnet,
      sizeLabel: _formatSize(sizeBytes),
      dateLabel: _formatDate(createdUnix),
      seeders: seeders,
      leechers: leechers,
      downloads: completed,
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '—';
    const kb = 1000.0;
    const mb = kb * 1000;
    const gb = mb * 1000;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  static String _formatDate(int unix) {
    if (unix <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
