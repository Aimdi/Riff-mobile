import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// A track hit from SoulSync's public search API.
class SoulSyncTrack {
  const SoulSyncTrack({
    required this.id,
    required this.name,
    required this.artists,
    this.album,
    this.durationMs,
    this.imageUrl,
    this.source,
  });

  final String id;
  final String name;
  final List<String> artists;
  final String? album;
  final int? durationMs;
  final String? imageUrl;
  final String? source;

  String get artistLabel => artists.where((a) => a.trim().isNotEmpty).join(', ');

  String get requestQuery {
    final a = artistLabel;
    if (a.isEmpty) return name;
    return '$a - $name';
  }

  factory SoulSyncTrack.fromJson(Map<String, dynamic> json) {
    final artistsRaw = json['artists'];
    List<String> artists = [];
    if (artistsRaw is List) {
      artists = artistsRaw.map((e) => e.toString()).toList();
    } else if (artistsRaw is String && artistsRaw.isNotEmpty) {
      artists = [artistsRaw];
    }
    return SoulSyncTrack(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? json['title'] ?? ''}',
      artists: artists,
      album: json['album']?.toString(),
      durationMs: json['duration_ms'] is int
          ? json['duration_ms'] as int
          : int.tryParse('${json['duration_ms'] ?? ''}'),
      imageUrl: (json['image_url'] ?? json['imageUrl'])?.toString(),
      source: json['source']?.toString(),
    );
  }
}

/// Client for a self-hosted [SoulSync](https://www.ssync.net/) instance
/// (https://github.com/Nezreka/SoulSync). Uses the public `/api/v1` REST API
/// with a Bearer API key — same pattern as Discord bots / curl integrations.
class SoulSyncService extends GetxController {
  SoulSyncService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _urlKey = 'soulSyncUrl';
  static const _keyKey = 'soulSyncApiKey';

  final isConnected = false.obs;
  final host = ''.obs;
  final statusMessage = ''.obs;

  Box get _prefs => Hive.box('AppPrefs');

  @override
  void onInit() {
    super.onInit();
    final url = (_prefs.get(_urlKey) ?? '').toString();
    final key = (_prefs.get(_keyKey) ?? '').toString();
    if (url.isNotEmpty && key.isNotEmpty) {
      host.value = _normalizeHost(url);
      isConnected.value = true;
      // Soft probe — don't block startup if the server is offline.
      verifyConnection().then((_) {}, onError: (_) => <String, dynamic>{});
    }
  }

  String _normalizeHost(String raw) {
    var h = raw.trim();
    if (h.endsWith('/')) h = h.substring(0, h.length - 1);
    return h;
  }

  String? get _apiKey => (_prefs.get(_keyKey) ?? '').toString();

  Options _authOptions() {
    final key = _apiKey ?? '';
    return Options(
      headers: {
        'Authorization': 'Bearer $key',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      receiveTimeout: const Duration(seconds: 25),
      sendTimeout: const Duration(seconds: 15),
      validateStatus: (s) => s != null && s < 500,
    );
  }

  Future<void> connect({
    required String serverUrl,
    required String apiKey,
  }) async {
    final normalized = _normalizeHost(serverUrl);
    final key = apiKey.trim();
    if (normalized.isEmpty || key.isEmpty) {
      throw Exception('soulSyncMissingFields');
    }
    host.value = normalized;
    await _prefs.put(_urlKey, normalized);
    await _prefs.put(_keyKey, key);
    await verifyConnection(throwOnFail: true);
    isConnected.value = true;
    statusMessage.value = '';
  }

  Future<void> disconnect() async {
    await _prefs.delete(_urlKey);
    await _prefs.delete(_keyKey);
    host.value = '';
    isConnected.value = false;
    statusMessage.value = '';
  }

  /// GET /api/v1/system/status
  Future<Map<String, dynamic>> verifyConnection({bool throwOnFail = false}) async {
    if (host.value.isEmpty || (_apiKey ?? '').isEmpty) {
      isConnected.value = false;
      if (throwOnFail) throw Exception('soulSyncNotConfigured');
      return {};
    }
    try {
      final res = await _dio.get(
        '${host.value}/api/v1/system/status',
        options: _authOptions(),
      );
      final body = _unwrap(res.data);
      if (res.statusCode == 401 || res.statusCode == 403) {
        isConnected.value = false;
        statusMessage.value = 'soulSyncAuthFailed'.tr;
        if (throwOnFail) throw Exception('soulSyncAuthFailed');
        return {};
      }
      if (res.statusCode != 200 || body == null) {
        isConnected.value = false;
        statusMessage.value = 'soulSyncConnectFailed'.tr;
        if (throwOnFail) throw Exception('soulSyncConnectFailed');
        return {};
      }
      isConnected.value = true;
      statusMessage.value = '';
      return body;
    } catch (e) {
      isConnected.value = false;
      statusMessage.value = 'soulSyncConnectFailed'.tr;
      if (throwOnFail) rethrow;
      return {};
    }
  }

  /// POST /api/v1/search/tracks
  Future<List<SoulSyncTrack>> searchTracks(String query, {int limit = 25}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final res = await _dio.post(
      '${host.value}/api/v1/search/tracks',
      data: {'query': q, 'source': 'auto', 'limit': limit},
      options: _authOptions(),
    );
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('soulSyncAuthFailed');
    }
    final data = _unwrap(res.data) ?? {};
    final list = (data['tracks'] as List?) ?? const [];
    return list
        .map((e) => SoulSyncTrack.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((t) => t.name.isNotEmpty)
        .toList();
  }

  /// POST /api/v1/request — queues SoulSync's search→download pipeline
  /// (Soulseek / configured sources on the server).
  Future<String> requestDownload(String query) async {
    final q = query.trim();
    if (q.isEmpty) throw Exception('soulSyncEmptyQuery');
    final res = await _dio.post(
      '${host.value}/api/v1/request',
      data: {'query': q},
      options: _authOptions(),
    );
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('soulSyncAuthFailed');
    }
    // 202 Accepted is success
    final data = _unwrap(res.data) ?? {};
    return '${data['request_id'] ?? data['status'] ?? 'queued'}';
  }

  /// GET /api/v1/downloads
  Future<List<Map<String, dynamic>>> listDownloads({int limit = 30}) async {
    final res = await _dio.get(
      '${host.value}/api/v1/downloads',
      queryParameters: {'limit': limit},
      options: _authOptions(),
    );
    final data = _unwrap(res.data) ?? {};
    final list = (data['downloads'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Map<String, dynamic>? _unwrap(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map['success'] == false) return null;
    final data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    // Some endpoints may return the payload at the root.
    return map;
  }
}
