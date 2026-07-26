import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '/services/yt_auth_service.dart';
import '/utils/helper.dart';

class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;
  StreamProvider(
      {required this.playable, this.audioFormats, this.statusMSG = ""});

  // Clients that return direct (non-ciphered) stream urls and do not
  // require a PO token. Payloads for the first two are transplanted from
  // Metrolist's Jan-2026 client fleet (ANDROID_VR 1.65.10 and the
  // unreleased VISIONOS client), which is what keeps its playback alive;
  // the library's own sdk-less android + ios pair is the last resort.
  static const YoutubeApiClient _androidVrFresh = YoutubeApiClient({
    'context': {
      'client': {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.65.10',
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'osName': 'Android',
        'osVersion': '12L',
        'androidSdkVersion': 32,
        'userAgent':
            'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    },
  }, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

  static const YoutubeApiClient _visionOs = YoutubeApiClient({
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '0.1',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice14,1',
        'osName': 'visionOS',
        'osVersion': '1.3.21O771',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    },
  }, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

  static final List<List<YoutubeApiClient>> _builtInAttempts = [
    [_androidVrFresh],
    [_visionOs],
    [YoutubeApiClient.androidSdkless, YoutubeApiClient.ios],
  ];

  /// Builds the client attempt list from the remote config json (see
  /// stream_clients.json in the repo); falls back to the built-ins on
  /// any parse problem. The library's sdk-less android + ios pair is
  /// always appended as the last resort.
  static List<List<YoutubeApiClient>> _attemptsFromConfig(
      String? configJson) {
    if (configJson == null) return _builtInAttempts;
    try {
      final config = jsonDecode(configJson) as Map<String, dynamic>;
      final attempts = (config['attempts'] as List)
          .map((group) => (group as List)
              .map((c) => YoutubeApiClient(
                  Map<String, dynamic>.from(c['payload']),
                  c['apiUrl'] as String))
              .toList())
          .where((g) => g.isNotEmpty)
          .toList();
      if (attempts.isEmpty) return _builtInAttempts;
      return [
        ...attempts,
        [YoutubeApiClient.androidSdkless, YoutubeApiClient.ios],
      ];
    } catch (e) {
      printERROR("Bad stream client config, using built-ins: $e");
      return _builtInAttempts;
    }
  }

  static const _newPipeChannel = MethodChannel('riff/newpipe');

  /// Budget for the NewPipe platform-channel round trip.
  ///
  /// The Android side runs a handful of HTTP calls inside NewPipeExtractor;
  /// a healthy resolve lands well under 2s on mobile data. 12s covers a slow
  /// but alive extraction while guaranteeing that a wedged extractor costs
  /// one pause, not the whole playback attempt — [fetch] gates the entire
  /// youtube_explode fallback ladder on this call returning.
  static const Duration newPipeTimeout = Duration(seconds: 12);

  /// Cap for the "does this url actually serve bytes" probe. Only two bytes
  /// are requested, so anything past 10s is a stalled read, and the client
  /// already gives up on the connect phase at 8s.
  static const Duration urlProbeTimeout = Duration(seconds: 10);

  /// Awaits [call] but treats a hang exactly like a failure: once [timeout]
  /// elapses the pending result is abandoned and null is returned (with the
  /// [TimeoutException] reported through [onError]), so a caller that falls
  /// through on null reaches its next resolver either way.
  ///
  /// Public so tests can drive it with an injected delay.
  static Future<T?> callWithTimeout<T>(
      Future<T?> Function() call, Duration timeout,
      {void Function(Object error)? onError}) async {
    try {
      return await call().timeout(timeout);
    } catch (e) {
      onError?.call(e);
      return null;
    }
  }

  static bool _looksLikeBotBlock(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('sign in to confirm') ||
        s.contains('login_required') ||
        s.contains('signinconfirmnotbot') ||
        s.contains('not a bot');
  }

  /// Primary resolver on Android: NewPipeExtractor via the platform
  /// channel (the engine RiPlay uses). Returns null when unavailable or
  /// failed so the caller can fall back to youtube_explode_dart.
  ///
  /// When [botBlocked] is set, the caller should prefer an authenticated
  /// retry / clearer error over a generic "unplayable".
  static Future<StreamProvider?> _fetchViaNewPipe(String videoId,
      {Map<String, String>? authHeaders,
      void Function(Object error)? onBotBlocked}) async {
    if (!Platform.isAndroid) return null;
    try {
      final args = <String, dynamic>{'videoId': videoId};
      if (authHeaders != null) {
        if (authHeaders['cookie'] != null) {
          args['cookie'] = authHeaders['cookie'];
        }
        if (authHeaders['authorization'] != null) {
          args['authorization'] = authHeaders['authorization'];
        }
      }
      final res = await callWithTimeout<String>(
        () => _newPipeChannel.invokeMethod<String>('getAudioStreams', args),
        newPipeTimeout,
        onError: (e) {
          printERROR("NewPipe resolver failed ($videoId): $e");
          if (_looksLikeBotBlock(e)) onBotBlocked?.call(e);
        },
      );
      if (res == null) return null;
      final list = jsonDecode(res) as List;
      final formats = list
          .where((e) => (e['url'] ?? '').toString().isNotEmpty)
          .map((e) => Audio(
              itag: e['itag'] ?? 0,
              audioCodec: (e['mimeType'] ?? '').toString().contains('mp4')
                  ? Codec.mp4a
                  : Codec.opus,
              bitrate: e['bitrate'] ?? 0,
              duration: e['durationMs'] ?? 0,
              loudnessDb: 0.0,
              url: e['url'],
              size: e['size'] ?? 0))
          .toList();
      if (formats.isEmpty) return null;
      final provider = StreamProvider(
          playable: true, statusMSG: "OK", audioFormats: formats);
      // Validate before handing to the player (Metrolist does the same):
      // a resolved url can still 403 for this network; fall through to
      // the next resolver instead of letting playback silently fail.
      final checkUrl = provider.highestQualityAudio?.url;
      if (checkUrl != null && !await _urlIsPlayable(checkUrl)) {
        printERROR("NewPipe url failed validation ($videoId)");
        return null;
      }
      return provider;
    } catch (e) {
      printERROR("NewPipe resolver failed ($videoId): $e");
      if (_looksLikeBotBlock(e)) onBotBlocked?.call(e);
      return null;
    }
  }

  static Future<bool> _urlIsPlayable(String url) async {
    // A hiccup — or a read that never finishes — on the check should not
    // discard the stream, but it must not stall the resolver ladder either.
    final ok = await callWithTimeout<bool>(() => _probeUrl(url),
        urlProbeTimeout);
    return ok ?? true;
  }

  static Future<bool> _probeUrl(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      // Prefer a tiny ranged GET — some CDNs reject HEAD with 403/405
      // even when the stream is fine.
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1');
      final res = await req.close();
      await res.drain<void>();
      // 2xx and 206 are success; 403/429 may be IP luck — keep the URL
      // and let the player try rather than discarding a good resolve.
      if (res.statusCode >= 200 && res.statusCode < 300) return true;
      if (res.statusCode == 403 || res.statusCode == 429) return true;
      return false;
    } finally {
      // Runs on every exit path — including after the caller has given up
      // on this probe — so a failed check does not leak the socket.
      client.close(force: true);
    }
  }

  static Future<StreamProvider> fetch(String videoId,
      {String? clientConfigJson, Map<String, String>? authHeaders}) async {
    var sawBotBlock = false;
    void markBot(Object _) => sawBotBlock = true;

    final viaNewPipe = await _fetchViaNewPipe(videoId,
        authHeaders: authHeaders, onBotBlocked: markBot);
    if (viaNewPipe != null) return viaNewPipe;

    final httpClient = _AuthedYoutubeHttpClient(authHeaders ?? const {});
    final yt = YoutubeExplode(httpClient: httpClient);

    try {
      StreamManifest? res;
      Object? lastError;
      for (final clients in _attemptsFromConfig(clientConfigJson)) {
        try {
          res = await yt.videos.streamsClient.getManifest(videoId,
              ytClients: clients, requireWatchPage: false);
          if (res.audioOnly.isNotEmpty) break;
        } catch (e) {
          lastError = e;
          if (_looksLikeBotBlock(e)) sawBotBlock = true;
        }
      }
      if (res == null || res.audioOnly.isEmpty) {
        if (lastError != null) throw lastError;
        throw VideoUnavailableException(
            'Video "$videoId" has no audio streams');
      }
      final audio = res.audioOnly;
      return StreamProvider(
          playable: true,
          statusMSG: "OK",
          audioFormats: audio
              .map((e) => Audio(
                  itag: e.tag,
                  audioCodec:
                      e.audioCodec.contains('mp') ? Codec.mp4a : Codec.opus,
                  bitrate: e.bitrate.bitsPerSecond,
                  duration: 0,
                  loudnessDb: 0.0,
                  url: e.url.toString(),
                  size: e.size.totalBytes))
              .toList());
    } catch (e) {
      if (sawBotBlock || _looksLikeBotBlock(e)) {
        return StreamProvider(
          playable: false,
          statusMSG: "streamBotBlocked",
        );
      } else if (e is SocketException) {
        return StreamProvider(
          playable: false,
          statusMSG: "networkError",
        );
      } else if (e is VideoRequiresPurchaseException) {
        return StreamProvider(
          playable: false,
          statusMSG: "songRequiresPurchase",
        );
      } else if (e is VideoUnavailableException) {
        return StreamProvider(
          playable: false,
          statusMSG: "songUnavailable",
        );
      } else if (e is VideoUnplayableException ||
          e is YoutubeExplodeException) {
        return StreamProvider(
          playable: false,
          statusMSG: "songNotPlayable",
        );
      } else {
        return StreamProvider(
          playable: false,
          statusMSG: "streamUnknownError",
        );
      }
    } finally {
      yt.close();
    }
  }

  /// Convenience for callers that only have the Hive cookie string.
  static Map<String, String>? authHeadersFromSession() {
    try {
      if (!YtAuthService.isConnected) return null;
      final h = YtAuthService.streamAuthHeaders();
      return h.isEmpty ? null : h;
    } catch (_) {
      return null;
    }
  }

  Audio? get highestQualityAudio =>
      audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 140,
          orElse: () => audioFormats!.first);

  Audio? get highestBitrateMp4aAudio =>
      audioFormats?.lastWhere((item) => item.itag == 140 || item.itag == 139,
          orElse: () => audioFormats!.first);

  Audio? get highestBitrateOpusAudio =>
      audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 250,
          orElse: () => audioFormats!.first);

  Audio? get lowQualityAudio =>
      audioFormats?.lastWhere((item) => item.itag == 249 || item.itag == 139,
          orElse: () => audioFormats!.first);

  Map<String, dynamic> get hmStreamingData {
    return {
      "playable": playable,
      "statusMSG": statusMSG,
      "lowQualityAudio": lowQualityAudio?.toJson(),
      "highQualityAudio": highestQualityAudio?.toJson()
    };
  }
}

/// Merges optional YouTube login cookies into explode's default headers.
class _AuthedYoutubeHttpClient extends YoutubeHttpClient {
  _AuthedYoutubeHttpClient(this._extra);
  final Map<String, String> _extra;

  @override
  Map<String, String> get headers {
    final base = Map<String, String>.from(YoutubeHttpClient.defaultHeaders);
    final cookie = _extra['cookie'];
    if (cookie != null && cookie.isNotEmpty) {
      final existing = base['cookie'];
      base['cookie'] =
          (existing == null || existing.isEmpty) ? cookie : '$existing; $cookie';
    }
    final auth = _extra['authorization'];
    if (auth != null && auth.isNotEmpty) {
      base['authorization'] = auth;
      base['x-origin'] = _extra['x-origin'] ?? 'https://www.youtube.com';
    }
    return base;
  }
}

class Audio {
  final int itag;
  final Codec audioCodec;
  final int bitrate;
  final int duration;
  final int size;
  final double loudnessDb;
  final String url;
  Audio(
      {required this.itag,
      required this.audioCodec,
      required this.bitrate,
      required this.duration,
      required this.loudnessDb,
      required this.url,
      required this.size});

  Map<String, dynamic> toJson() => {
        "itag": itag,
        "audioCodec": audioCodec.toString(),
        "bitrate": bitrate,
        "loudnessDb": loudnessDb,
        "url": url,
        "approxDurationMs": duration,
        "size": size
      };

  factory Audio.fromJson(json) {
    if (json == null || json is! Map) {
      throw ArgumentError('Audio.fromJson expected a Map');
    }
    final codecRaw = (json["audioCodec"] ?? '').toString();
    final url = (json['url'] ?? '').toString();
    if (url.isEmpty) {
      throw ArgumentError('Audio.fromJson missing url');
    }
    final loudness = json['loudnessDb'];
    double loudnessDb = 0.0;
    if (loudness is num) {
      loudnessDb = loudness.toDouble();
    } else if (loudness is String) {
      loudnessDb = double.tryParse(loudness) ?? 0.0;
    }
    return Audio(
        audioCodec: codecRaw.contains("mp4a") ? Codec.mp4a : Codec.opus,
        itag: (json['itag'] as num?)?.toInt() ?? 0,
        duration: (json["approxDurationMs"] as num?)?.toInt() ?? 0,
        bitrate: (json["bitrate"] as num?)?.toInt() ?? 0,
        loudnessDb: loudnessDb,
        url: url,
        size: (json["size"] as num?)?.toInt() ?? 0);
  }
}

enum Codec { mp4a, opus }
