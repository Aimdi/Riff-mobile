import 'package:dio/dio.dart';

/// A single torrent hit from a Torrents Digger–style search.
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
