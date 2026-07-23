import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

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

  /// Primary resolver on Android: NewPipeExtractor via the platform
  /// channel (the engine RiPlay uses). Returns null when unavailable or
  /// failed so the caller can fall back to youtube_explode_dart.
  static Future<StreamProvider?> _fetchViaNewPipe(String videoId) async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await _newPipeChannel
          .invokeMethod<String>('getAudioStreams', {'videoId': videoId});
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
      return null;
    }
  }

  static Future<bool> _urlIsPlayable(String url) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await client.headUrl(Uri.parse(url));
      final res = await req.close();
      await res.drain<void>();
      client.close();
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      // Network hiccup on the check should not discard the stream.
      return true;
    }
  }

  static Future<StreamProvider> fetch(String videoId,
      {String? clientConfigJson}) async {
    final viaNewPipe = await _fetchViaNewPipe(videoId);
    if (viaNewPipe != null) return viaNewPipe;

    final yt = YoutubeExplode();

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
      if (e is SocketException) {
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

  factory Audio.fromJson(json) => Audio(
      audioCodec: (json["audioCodec"] as String).contains("mp4a")
          ? Codec.mp4a
          : Codec.opus,
      itag: json['itag'],
      duration: json["approxDurationMs"] ?? 0,
      bitrate: json["bitrate"] ?? 0,
      loudnessDb: (json['loudnessDb'])?.toDouble() ?? 0.0,
      url: json['url'],
      size: json["size"] ?? 0);
}

enum Codec { mp4a, opus }
