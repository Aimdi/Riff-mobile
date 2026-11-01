import 'package:dio/dio.dart';

import '/utils/helper.dart' show printERROR;

/// One caption track a video offers, as YouTube's player lists it.
class YoutubeCaptionTrack {
  const YoutubeCaptionTrack(
      {required this.url, required this.lang, required this.auto});

  final String url;

  /// Its language code ("en", "de", "pt-BR").
  final String lang;

  /// Made by YouTube's speech recognition, not by a person.
  final bool auto;
}

/// YouTube captions read from the player API with clients that still list
/// them and serve them without a proof-of-origin token. Since 2025 the web
/// watch page's tracks need one, so youtube_explode_dart's caption client
/// finds none and podcast transcripts from YouTube came up empty.
class YoutubeCaptions {
  YoutubeCaptions._();

  static const _playerUrl =
      'https://www.youtube.com/youtubei/v1/player?prettyPrint=false';

  /// Tried in order until one lists captions: the Android client without
  /// an SDK version the stream resolver leads with (it isn't asked for a
  /// proof-of-origin token), then VR and iOS.
  static const _clients =
      <({String id, String ua, Map<String, Object> client})>[
    (
      id: '3',
      ua: 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
      client: {
        'clientName': 'ANDROID',
        'clientVersion': '20.10.38',
        'userAgent':
            'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
        'osName': 'Android',
        'osVersion': '11',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    ),
    (
      id: '28',
      ua: 'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; '
          'Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      client: {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.65.10',
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'osName': 'Android',
        'osVersion': '12L',
        'androidSdkVersion': 32,
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    ),
    (
      id: '5',
      ua: 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 '
          'like Mac OS X;)',
      client: {
        'clientName': 'IOS',
        'clientVersion': '20.10.4',
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone16,2',
        'osName': 'iPhone',
        'osVersion': '18.3.2.22D82',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    ),
  ];

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// The tracks [videoId] offers, with the user agent of the client that
  /// listed them (their files are fetched with it); empty when none does.
  static Future<({List<YoutubeCaptionTrack> tracks, String ua})> tracks(
      String videoId) async {
    for (final c in _clients) {
      try {
        final res = await _dio.post<Map<String, dynamic>>(
          _playerUrl,
          data: {
            'context': {'client': c.client},
            'videoId': videoId,
            'contentCheckOk': true,
            'racyCheckOk': true,
          },
          options: Options(
            responseType: ResponseType.json,
            headers: {
              'User-Agent': c.ua,
              'X-YouTube-Client-Name': c.id,
              'X-YouTube-Client-Version': c.client['clientVersion'],
              'Content-Type': 'application/json',
            },
          ),
        );
        final found = parseCaptionTracks(res.data);
        if (found.isNotEmpty) return (tracks: found, ua: c.ua);
        // Why not: the video has none, or YouTube wants a sign-in.
        final status = res.data?['playabilityStatus'];
        printERROR('Caption tracks (${c.client['clientName']}, $videoId): '
            'none; ${status is Map ? '${status['status']} '
                '${status['reason'] ?? ''}' : 'no status'}');
      } catch (e) {
        printERROR('Caption tracks (${c.client['clientName']}, $videoId): $e');
      }
    }
    return (tracks: const <YoutubeCaptionTrack>[], ua: '');
  }

  /// [track] as WebVTT; null when YouTube sends none.
  static Future<String?> vtt(YoutubeCaptionTrack track, {String? ua}) async {
    try {
      final res = await _dio.get<String>(
        withVttFormat(track.url),
        options: Options(
          responseType: ResponseType.plain,
          headers: {if (ua != null && ua.isNotEmpty) 'User-Agent': ua},
        ),
      );
      final body = res.data?.trim() ?? '';
      if (body.startsWith('WEBVTT')) return body;
      printERROR('Caption file: HTTP ${res.statusCode}, '
          '${body.length} chars, not WebVTT');
      return null;
    } catch (e) {
      printERROR('Caption file failed: $e');
      return null;
    }
  }
}

/// The caption tracks in a player response
/// (`captions.playerCaptionsTracklistRenderer.captionTracks`).
List<YoutubeCaptionTrack> parseCaptionTracks(Object? player) {
  final captions = player is Map ? player['captions'] : null;
  final renderer =
      captions is Map ? captions['playerCaptionsTracklistRenderer'] : null;
  final list = renderer is Map ? renderer['captionTracks'] : null;
  if (list is! List) return const [];
  return [
    for (final t in list)
      if (t is Map &&
          t['baseUrl'] is String &&
          (t['baseUrl'] as String).isNotEmpty &&
          t['languageCode'] is String)
        YoutubeCaptionTrack(
          url: t['baseUrl'] as String,
          lang: t['languageCode'] as String,
          auto: t['kind'] == 'asr',
        ),
  ];
}

/// A caption track's address asking for WebVTT, its other parameters kept.
String withVttFormat(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  return uri.replace(queryParameters: {
    ...uri.queryParametersAll,
    'fmt': ['vtt'],
  }).toString();
}
