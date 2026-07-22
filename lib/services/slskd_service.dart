import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// One audio file hit from a Soulseek search via slskd.
class SoulseekHit {
  const SoulseekHit({
    required this.username,
    required this.filename,
    required this.size,
    required this.uploadSpeed,
    required this.queueLength,
    this.bitRate,
    this.lengthSeconds,
    this.extension,
  });

  final String username;
  final String filename;
  final int size;
  final int uploadSpeed;
  final int queueLength;
  final int? bitRate;
  final int? lengthSeconds;
  final String? extension;

  String get displayName {
    final parts = filename.replaceAll('/', '\\').split('\\');
    final base = parts.isEmpty ? filename : parts.last;
    return base.trim().isEmpty ? filename : base;
  }

  String get sizeLabel {
    if (size <= 0) return '—';
    const kb = 1000.0;
    const mb = kb * 1000;
    const gb = mb * 1000;
    if (size >= gb) return '${(size / gb).toStringAsFixed(2)} GB';
    if (size >= mb) return '${(size / mb).toStringAsFixed(1)} MB';
    if (size >= kb) return '${(size / kb).toStringAsFixed(0)} KB';
    return '$size B';
  }

  String get metaLabel {
    final bits = <String>[sizeLabel];
    if (bitRate != null && bitRate! > 0) bits.add('${bitRate}kbps');
    if (lengthSeconds != null && lengthSeconds! > 0) {
      final m = lengthSeconds! ~/ 60;
      final s = lengthSeconds! % 60;
      bits.add('$m:${s.toString().padLeft(2, '0')}');
    }
    bits.add(username);
    return bits.join(' · ');
  }
}

/// Client for a self-hosted [slskd](https://github.com/slskd/slskd) instance —
/// the headless Soulseek client with a REST API. This is how Riff can search
/// the Soulseek network in-app (embedding Seeker's full protocol stack is not
/// practical in Flutter).
class SlskdService extends GetxController {
  SlskdService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _urlKey = 'slskdUrl';
  static const _keyKey = 'slskdApiKey';

  static const _audioExt = {
    'mp3',
    'flac',
    'm4a',
    'aac',
    'ogg',
    'opus',
    'wav',
    'wma',
    'aiff',
    'alac',
  };

  final isConnected = false.obs;
  final host = ''.obs;
  final soulseekLoggedIn = false.obs;
  final soulseekUser = ''.obs;
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
      verifyConnection().then((_) {}, onError: (_) {});
    }
  }

  String _normalizeHost(String raw) {
    var h = raw.trim();
    if (h.endsWith('/')) h = h.substring(0, h.length - 1);
    return h;
  }

  String? get _apiKey => (_prefs.get(_keyKey) ?? '').toString();

  Options _authOptions({Duration? receiveTimeout}) {
    final key = _apiKey ?? '';
    return Options(
      headers: {
        'X-API-Key': key,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      receiveTimeout: receiveTimeout ?? const Duration(seconds: 30),
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
      throw Exception('slskdMissingFields');
    }
    host.value = normalized;
    await _prefs.put(_urlKey, normalized);
    await _prefs.put(_keyKey, key);
    await verifyConnection(throwOnFail: true);
    isConnected.value = true;
  }

  Future<void> disconnect() async {
    await _prefs.delete(_urlKey);
    await _prefs.delete(_keyKey);
    host.value = '';
    isConnected.value = false;
    soulseekLoggedIn.value = false;
    soulseekUser.value = '';
    statusMessage.value = '';
  }

  /// GET /api/v0/application — confirms API key and Soulseek login state.
  Future<Map<String, dynamic>> verifyConnection({bool throwOnFail = false}) async {
    if (host.value.isEmpty || (_apiKey ?? '').isEmpty) {
      isConnected.value = false;
      if (throwOnFail) throw Exception('slskdNotConfigured');
      return {};
    }
    try {
      final res = await _dio.get(
        '${host.value}/api/v0/application',
        options: _authOptions(),
      );
      if (res.statusCode == 401 || res.statusCode == 403) {
        isConnected.value = false;
        statusMessage.value = 'slskdAuthFailed'.tr;
        if (throwOnFail) throw Exception('slskdAuthFailed');
        return {};
      }
      if (res.statusCode != 200 || res.data is! Map) {
        isConnected.value = false;
        statusMessage.value = 'slskdConnectFailed'.tr;
        if (throwOnFail) throw Exception('slskdConnectFailed');
        return {};
      }
      final body = Map<String, dynamic>.from(res.data as Map);
      final server = body['server'];
      if (server is Map) {
        soulseekLoggedIn.value = server['isLoggedIn'] == true;
        soulseekUser.value = '${server['username'] ?? ''}';
      }
      isConnected.value = true;
      statusMessage.value = soulseekLoggedIn.value
          ? ''
          : 'slskdNotLoggedIn'.tr;
      return body;
    } catch (e) {
      isConnected.value = false;
      statusMessage.value = 'slskdConnectFailed'.tr;
      if (throwOnFail) rethrow;
      return {};
    }
  }

  /// Search the Soulseek network through slskd.
  ///
  /// POST /api/v0/searches waits until the search completes (or times out),
  /// then we pull file responses.
  Future<List<SoulseekHit>> search(
    String query, {
    int responseLimit = 40,
    int fileLimit = 200,
    int searchTimeoutSec = 12,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    if (host.value.isEmpty || (_apiKey ?? '').isEmpty) {
      throw Exception('slskdNotConfigured');
    }

    final post = await _dio.post(
      '${host.value}/api/v0/searches',
      data: {
        'searchText': q,
        'responseLimit': responseLimit,
        'fileLimit': fileLimit,
        'searchTimeout': searchTimeoutSec,
        'filterResponses': true,
      },
      options: _authOptions(receiveTimeout: const Duration(seconds: 90)),
    );

    if (post.statusCode == 401 || post.statusCode == 403) {
      throw Exception('slskdAuthFailed');
    }
    if (post.statusCode == 429) {
      throw Exception('slskdBusy');
    }
    if (post.statusCode == 409) {
      throw Exception('slskdNotLoggedIn');
    }
    if (post.statusCode != 200 || post.data is! Map) {
      throw Exception('slskdSearchFailed');
    }

    final search = Map<String, dynamic>.from(post.data as Map);
    final id = '${search['id'] ?? ''}';
    if (id.isEmpty) throw Exception('slskdSearchFailed');

    // Prefer responses embedded on the search; otherwise fetch them.
    dynamic responsesRaw = search['responses'];
    if (responsesRaw is! List || responsesRaw.isEmpty) {
      // Poll briefly in case the POST returned while still in progress.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final st = await _dio.get(
          '${host.value}/api/v0/searches/$id',
          queryParameters: {'includeResponses': false},
          options: _authOptions(),
        );
        if (st.statusCode != 200 || st.data is! Map) break;
        final state = '${(st.data as Map)['state'] ?? ''}';
        if (!state.contains('InProgress')) break;
      }
      final res = await _dio.get(
        '${host.value}/api/v0/searches/$id/responses',
        options: _authOptions(receiveTimeout: const Duration(seconds: 45)),
      );
      if (res.statusCode != 200) throw Exception('slskdSearchFailed');
      responsesRaw = res.data;
    }

    final hits = <SoulseekHit>[];
    if (responsesRaw is! List) return hits;

    for (final raw in responsesRaw) {
      if (raw is! Map) continue;
      final peer = Map<String, dynamic>.from(raw);
      final username = '${peer['username'] ?? ''}'.trim();
      if (username.isEmpty) continue;
      final uploadSpeed = _asInt(peer['uploadSpeed']);
      final queueLength = _asInt(peer['queueLength']);
      final files = peer['files'];
      if (files is! List) continue;
      for (final f in files) {
        if (f is! Map) continue;
        final file = Map<String, dynamic>.from(f);
        final filename = '${file['filename'] ?? ''}'.trim();
        if (filename.isEmpty) continue;
        final ext = _extensionOf(filename, file['extension']?.toString());
        if (!_audioExt.contains(ext)) continue;
        hits.add(
          SoulseekHit(
            username: username,
            filename: filename,
            size: _asInt(file['size']),
            uploadSpeed: uploadSpeed,
            queueLength: queueLength,
            bitRate: _asIntOrNull(file['bitRate']),
            lengthSeconds: _asIntOrNull(file['length']),
            extension: ext,
          ),
        );
      }
    }

    // Prefer free-slot peers and higher bitrate first.
    hits.sort((a, b) {
      final br = (b.bitRate ?? 0).compareTo(a.bitRate ?? 0);
      if (br != 0) return br;
      return b.uploadSpeed.compareTo(a.uploadSpeed);
    });
    return hits;
  }

  /// Queue a download on the slskd server.
  /// POST /api/v0/transfers/downloads/{username}
  Future<void> enqueueDownload(SoulseekHit hit) async {
    final encodedUser = Uri.encodeComponent(hit.username);
    final res = await _dio.post(
      '${host.value}/api/v0/transfers/downloads/$encodedUser',
      data: [
        {'filename': hit.filename, 'size': hit.size},
      ],
      options: _authOptions(),
    );
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('slskdAuthFailed');
    }
    // 201 created; some versions return 200
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('slskdDownloadFailed');
    }
  }

  static String _extensionOf(String filename, String? provided) {
    final fromProvided = (provided ?? '').trim().toLowerCase().replaceAll('.', '');
    if (fromProvided.isNotEmpty) return fromProvided;
    final base = filename.replaceAll('/', '\\').split('\\').last;
    final dot = base.lastIndexOf('.');
    if (dot < 0 || dot == base.length - 1) return '';
    return base.substring(dot + 1).toLowerCase();
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static int? _asIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }
}
