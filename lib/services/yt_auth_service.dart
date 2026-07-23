import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

/// Optional YouTube account connection (same cookie/SAPISID mechanism as
/// Metrolist and RiPlay). Connecting personalizes the YT Music feed
/// (Listen again, your mixes, your library); everything else in Riff
/// keeps working anonymously and nothing is sent anywhere but YouTube.
class YtAuthService {
  YtAuthService._();

  static const _channel = MethodChannel('riff/newpipe');
  static const _origin = 'https://music.youtube.com';

  static String? get cookie => Hive.box('AppPrefs').get('ytAuthCookie');

  static bool get isConnected =>
      cookie != null && cookie!.contains('SAPISID');

  /// Reads the WebView's cookies after a login and stores them when they
  /// carry an authenticated session. Returns true when connected.
  static Future<bool> captureFromWebView() async {
    final cookies =
        await _channel.invokeMethod<String>('getCookies', {'url': _origin});
    if (cookies != null && cookies.contains('SAPISID')) {
      await Hive.box('AppPrefs').put('ytAuthCookie', cookies);
      return true;
    }
    return false;
  }

  static Future<void> disconnect() async {
    await Hive.box('AppPrefs').delete('ytAuthCookie');
    try {
      await _channel.invokeMethod('clearCookies');
    } catch (_) {}
  }

  /// Per-request auth headers (the SAPISIDHASH is time-based).
  /// [origin] must match the site the request is made against
  /// (`music.youtube.com` for browse, `www.youtube.com` for player/streams).
  static Map<String, String> authHeaders(
      {String origin = _origin}) {
    final c = cookie;
    if (c == null) return {};
    final sapisid =
        RegExp(r'SAPISID=([^;]+)').firstMatch(c)?.group(1) ??
            RegExp(r'__Secure-3PAPISID=([^;]+)').firstMatch(c)?.group(1);
    if (sapisid == null) return {};
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final hash = sha1.convert(utf8.encode('$ts $sapisid $origin')).toString();
    return {
      'cookie': c,
      'authorization': 'SAPISIDHASH ${ts}_$hash',
      'x-origin': origin,
      'x-goog-authuser': '0',
    };
  }

  /// Headers for NewPipe / youtube_explode player requests.
  static Map<String, String> streamAuthHeaders() =>
      authHeaders(origin: 'https://www.youtube.com');
}

