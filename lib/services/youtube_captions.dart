import 'dart:convert';

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
        'userAgent': 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU '
            'iOS 18_3_2 like Mac OS X;)',
        'platform': 'MOBILE',
        'osName': 'IOS',
        'osVersion': '18.1.0.22B83',
        'hl': 'en',
        'gl': 'US',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    ),
  ];

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static String? _visitorData;

  /// A visitor id, as the iOS app has one: without it YouTube asks
  /// connections it doesn't trust to sign in ("confirm you're not a bot").
  static Future<String?> _visitor() async {
    if (_visitorData != null) return _visitorData;
    try {
      final res = await _dio.get<String>(
        'https://www.youtube.com/sw.js_data',
        options: Options(
          responseType: ResponseType.plain,
          headers: {'User-Agent': _clients.last.ua},
        ),
      );
      return _visitorData = parseVisitorData(res.data);
    } catch (e) {
      printERROR('Visitor id failed: $e');
      return null;
    }
  }

  /// The video's watch page, as a browser opens it, for the cookies and
  /// visitor id YouTube gives it: player requests sent with them aren't
  /// asked to sign in (youtube_explode's stream client does the same).
  static Future<({String cookie, String? visitor})?> _watchPage(
      String videoId) async {
    try {
      final res = await _dio.get<String>(
        'https://www.youtube.com/watch?v=$videoId&bpctr=9999999999'
        '&has_verified=1&hl=en',
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/96.0.4664.18 Safari/537.36',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-us,en;q=0.5',
            'Cookie': 'PREF=hl=en&tz=UTC; SOCS=CAI; GPS=1',
          },
        ),
      );
      return (
        cookie: watchPageCookies(res.headers['set-cookie'] ?? const []),
        visitor: RegExp(r'"VISITOR_DATA":"([^"]+)"')
            .firstMatch(res.data ?? '')
            ?.group(1),
      );
    } catch (e) {
      printERROR('Watch page failed ($videoId): $e');
      return null;
    }
  }

  /// The tracks [videoId] offers, with the user agent of the client that
  /// listed them (their files are fetched with it); empty when none does.
  static Future<({List<YoutubeCaptionTrack> tracks, String ua})> tracks(
      String videoId) async {
    final page = await _watchPage(videoId);
    final visitor = page?.visitor ?? await _visitor();
    for (final c in _clients) {
      try {
        final res = await _dio.post<Map<String, dynamic>>(
          _playerUrl,
          data: {
            'context': {
              'client': {
                ...c.client,
                if (visitor != null) 'visitorData': visitor,
              },
            },
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
              if (visitor != null) 'X-Goog-Visitor-Id': visitor,
              if (page != null) 'Cookie': page.cookie,
              'Origin': 'https://www.youtube.com',
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

/// The cookies a watch page set (its `Set-Cookie` headers), with the
/// consent ones a browser sends, as one `Cookie` header.
String watchPageCookies(List<String> setCookies) {
  final jar = <String, String>{};
  for (final c in setCookies) {
    final pair = c.split(';').first;
    final eq = pair.indexOf('=');
    if (eq <= 0) continue;
    jar[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
  }
  jar.addAll({'PREF': 'hl=en', 'SOCS': 'CAI', 'GPS': '1'});
  return [for (final e in jar.entries) '${e.key}=${e.value}'].join('; ');
}

/// The visitor id in YouTube's `sw.js_data` reply (JSON after a `)]}'`
/// guard); null in another shape.
String? parseVisitorData(String? body) {
  var text = body?.trim() ?? '';
  if (text.startsWith(")]}'")) text = text.substring(4);
  try {
    final v = jsonDecode(text)[0][2][0][0][13];
    return v is String && v.isNotEmpty ? v : null;
  } catch (_) {
    return null;
  }
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
