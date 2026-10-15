/// Last.fm scrobbling, as Spotify, Metrolist and InnerTune have it: the songs
/// you listen to go to your Last.fm profile once they've played half way or
/// 4 minutes (scrobble_rules), the song playing shows there as scrobbling
/// now, and scrobbles that can't go (offline, Last.fm down) are kept and go
/// with the next that can.
///
/// Riff signs in with Last.fm's mobile sign-in (auth.getMobileSession): your
/// username and password go to Last.fm once, over HTTPS, and only the
/// session it gives back is kept, in secure storage. Last.fm's API wants an
/// application's key and secret: the build's (--dart-define LASTFM_API_KEY
/// and LASTFM_SECRET), else your own (last.fm/api/account/create), entered
/// when you connect.
library;

import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/utils/helper.dart';
import '/utils/secure_credentials.dart';

/// An error Last.fm answered with: its code and message.
class LastFmError implements Exception {
  const LastFmError(this.code, this.message);

  final int code;
  final String message;

  /// Wrong username or password.
  bool get badLogin => code == 4;

  /// The API key or secret isn't right: unknown, suspended, or a signature
  /// made with another secret.
  bool get badKey => code == 10 || code == 13 || code == 26;

  /// The session isn't good anymore (access taken back on last.fm).
  bool get sessionGone => code == 9;

  /// Last.fm busy or down for now: worth trying again later.
  bool get passing => code == 11 || code == 16 || code == 29;

  @override
  String toString() => 'LastFmError($code: $message)';
}

class LastFmService {
  LastFmService._();

  static const endpoint = 'https://ws.audioscrobbler.com/2.0/';

  /// Scrobbles kept until they can be sent.
  static const pendingBox = 'LastFmPending';

  /// Where the session, the user's name and their own API key are kept
  /// (SecureCredentials).
  static const sessionKey = 'lastFmSession';
  static const userKey = 'lastFmUser';
  static const apiKeyKey = 'lastFmApiKey';
  static const secretKey = 'lastFmSecret';

  static const _builtInKey = String.fromEnvironment('LASTFM_API_KEY');
  static const _builtInSecret = String.fromEnvironment('LASTFM_SECRET');

  /// Whether this build carries an API key for Riff (else you enter yours
  /// when you connect).
  static bool get hasBuiltInKey =>
      _builtInKey.isNotEmpty && _builtInSecret.isNotEmpty;

  static String get apiKey =>
      hasBuiltInKey ? _builtInKey : SecureCredentials.get(apiKeyKey) ?? '';

  static String get _secret =>
      hasBuiltInKey ? _builtInSecret : SecureCredentials.get(secretKey) ?? '';

  /// Whether a secret of your own is kept (it isn't shown again).
  static bool get hasOwnSecret =>
      (SecureCredentials.get(secretKey) ?? '').isNotEmpty;

  static String get _session => SecureCredentials.get(sessionKey) ?? '';

  static bool get enabled =>
      _session.isNotEmpty && apiKey.isNotEmpty && _secret.isNotEmpty;

  /// The Last.fm user scrobbled to ('' when not connected).
  static String get user => enabled ? SecureCredentials.get(userKey) ?? '' : '';

  /// The Last.fm user last connected, to sign in as again.
  static String get lastUser => SecureCredentials.get(userKey) ?? '';

  /// Bumps when Riff connects to Last.fm or stops scrobbling there.
  static final rev = 0.obs;

  /// Most scrobbles kept (the oldest go first past it), and most sent at
  /// once (Last.fm takes 50).
  @visibleForTesting
  static int maxKept = 1000;
  static const _batch = 50;

  /// Last.fm doesn't take scrobbles older than this.
  static const _takenFor = Duration(days: 14);

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  // Last.fm answers a call it turns down with a 4xx whose JSON says why.
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    validateStatus: (_) => true,
  ));

  /// Posts [form] to Last.fm; its answer (JSON). Throws when Last.fm can't
  /// be reached or is down.
  @visibleForTesting
  static Future<dynamic> Function(Map<String, String> form) transport =
      (form) async {
    final res = await _dio.post(endpoint,
        data: form,
        options: Options(contentType: Headers.formUrlEncodedContentType));
    if ((res.statusCode ?? 0) >= 500) {
      throw DioException(
          requestOptions: res.requestOptions,
          response: res,
          type: DioExceptionType.badResponse);
    }
    final data = res.data;
    return data is String ? jsonDecode(data) : data;
  };

  /// Last.fm's api_sig for [params]: each one's name then value, in order
  /// of name (not format or callback), then the secret, as MD5.
  @visibleForTesting
  static String signature(Map<String, String> params, String secret) {
    final names = params.keys
        .where((name) => name != 'format' && name != 'callback')
        .toList()
      ..sort();
    final text = StringBuffer();
    for (final name in names) {
      text
        ..write(name)
        ..write(params[name]);
    }
    text.write(secret);
    return md5.convert(utf8.encode(text.toString())).toString();
  }

  /// Calls [method] with [params], signed; Last.fm's answer, or throws a
  /// [LastFmError] (or the connection's error).
  static Future<Map<String, dynamic>> _call(
      String method, Map<String, String> params,
      {bool signedIn = true}) async {
    final call = {
      ...params,
      'method': method,
      'api_key': apiKey,
      if (signedIn) 'sk': _session,
    };
    final answer = await transport({
      ...call,
      'api_sig': signature(call, _secret),
      'format': 'json',
    });
    if (answer is! Map) throw const LastFmError(0, 'No answer');
    final error = answer['error'];
    if (error != null) {
      throw LastFmError(error is int ? error : int.tryParse('$error') ?? 0,
          '${answer['message'] ?? ''}');
    }
    return Map<String, dynamic>.from(answer);
  }

  /// Signs in to Last.fm as [username] with [password] (sent once, never
  /// kept) and keeps the session it gives; with your own [apiKey] and
  /// [secret] when the build has none. Throws a [LastFmError] (wrong
  /// username or password, a key Last.fm doesn't take) or the connection's
  /// error.
  static Future<void> connect(String username, String password,
      {String apiKey = '', String secret = ''}) async {
    if (!hasBuiltInKey) {
      // Left empty: the one kept from before.
      if (apiKey.trim().isNotEmpty) {
        await SecureCredentials.set(apiKeyKey, apiKey.trim());
      }
      if (secret.trim().isNotEmpty) {
        await SecureCredentials.set(secretKey, secret.trim());
      }
    }
    final answer = await _call('auth.getMobileSession',
        {'username': username.trim(), 'password': password},
        signedIn: false);
    final session = answer['session'];
    final key = session is Map ? session['key'] : null;
    if (key is! String || key.isEmpty) {
      throw const LastFmError(0, 'No session');
    }
    final name = '${(session as Map)['name'] ?? ''}'.trim();
    await SecureCredentials.set(sessionKey, key);
    await SecureCredentials.set(
        userKey, name.isNotEmpty ? name : username.trim());
    rev.value++;
    unawaited(sendKept());
  }

  /// Stops scrobbling to Last.fm; the scrobbles kept are dropped.
  static Future<void> disconnect() async {
    await SecureCredentials.delete(sessionKey);
    rev.value++;
    await (await _pending())?.clear();
  }

  /// Last.fm took the session back (access taken away on last.fm): not
  /// connected anymore.
  static Future<void> _sessionEnded() async {
    await SecureCredentials.delete(sessionKey);
    rev.value++;
  }

  /// What Last.fm knows a song by: its artist (the first of several, as
  /// Spotify scrobbles), its title, album and length.
  @visibleForTesting
  static Map<String, String> trackOf(MediaItem item) {
    final artists = item.extras?['artists'];
    var artist = '';
    if (artists is List && artists.isNotEmpty && artists.first is Map) {
      artist = '${(artists.first as Map)['name'] ?? ''}'.trim();
    }
    if (artist.isEmpty) artist = (item.artist ?? '').trim();
    // YouTube's channel for an artist ("Name - Topic").
    const topic = ' - Topic';
    if (artist.endsWith(topic)) {
      artist = artist.substring(0, artist.length - topic.length);
    }
    final album = (item.album ?? '').trim();
    final seconds = item.duration?.inSeconds ?? 0;
    return {
      'artist': artist,
      'track': item.title.trim(),
      if (album.isNotEmpty) 'album': album,
      if (seconds > 0) 'duration': '$seconds',
    };
  }

  static bool _named(Map<String, String> track) =>
      track['artist']!.isNotEmpty && track['track']!.isNotEmpty;

  /// [item] started playing: Last.fm shows it as scrobbling now. Not kept
  /// when it can't be sent (it's no news later).
  static Future<void> playingNow(MediaItem item) async {
    if (!enabled) return;
    final track = trackOf(item);
    if (!_named(track)) return;
    try {
      await _call('track.updateNowPlaying', track);
    } catch (e) {
      printINFO('Last.fm playing now failed: $e');
      if (e is LastFmError && e.sessionGone) await _sessionEnded();
      return;
    }
    await sendKept();
  }

  /// [item], played for [listened] up to now: scrobbled as of when it
  /// started.
  static Future<void> scrobble(MediaItem item,
      {required Duration listened}) async {
    if (!enabled) return;
    final track = trackOf(item);
    if (!_named(track)) return;
    final started = clock().subtract(listened);
    final entry = {
      ...track,
      'timestamp': '${started.millisecondsSinceEpoch ~/ 1000}',
    };
    try {
      await _scrobble([entry]);
    } catch (e) {
      printERROR('Last.fm scrobble failed: $e');
      if (e is LastFmError && e.sessionGone) await _sessionEnded();
      if (worthKeeping(e)) await _keep(entry);
      return;
    }
    await sendKept();
  }

  static Future<void> _scrobble(List<Map<String, String>> entries) =>
      _call('track.scrobble', {
        for (final (i, entry) in entries.indexed)
          for (final field in entry.entries) '${field.key}[$i]': field.value,
      });

  /// Whether a scrobble that failed with [error] can go later: no
  /// connection, or Last.fm busy or down. Not one it turned down.
  static bool worthKeeping(Object error) {
    if (error is LastFmError) return error.passing;
    if (error is! DioException) return false;
    final status = error.response?.statusCode;
    return status == null || status == 429 || status >= 500;
  }

  static Future<Box?> _pending() async {
    try {
      return Hive.isBoxOpen(pendingBox)
          ? Hive.box(pendingBox)
          : await Hive.openBox(pendingBox);
    } catch (e) {
      return null;
    }
  }

  static Future<void> _keep(Map<String, String> entry) async {
    final box = await _pending();
    if (box == null) return;
    await box.add(entry);
    final extra = box.length - maxKept;
    if (extra > 0) await box.deleteAll(box.keys.take(extra).toList());
  }

  static Future<void>? _sendingKept;

  /// Sends the scrobbles kept while they couldn't go, oldest first, 50 at a
  /// time; what still can't go stays for next time, what's too old for
  /// Last.fm is let go. One at a time: a song change scrobbles one song and
  /// says the next is playing at once.
  static Future<void> sendKept() =>
      _sendingKept ??= _sendKept().whenComplete(() => _sendingKept = null);

  static Future<void> _sendKept() async {
    if (!enabled) return;
    final box = await _pending();
    if (box == null) return;
    final oldest = clock().subtract(_takenFor).millisecondsSinceEpoch ~/ 1000;
    while (box.isNotEmpty) {
      final keys = box.keys.take(_batch).toList();
      final entries = <Map<String, String>>[];
      for (final key in keys) {
        final kept = box.get(key);
        if (kept is! Map) continue;
        final entry = {
          for (final field in kept.entries) '${field.key}': '${field.value}'
        };
        if ((int.tryParse(entry['timestamp'] ?? '') ?? 0) < oldest) continue;
        entries.add(entry);
      }
      try {
        if (entries.isNotEmpty) await _scrobble(entries);
      } catch (e) {
        printERROR('Last.fm kept scrobbles failed: $e');
        if (e is LastFmError && e.sessionGone) await _sessionEnded();
        // Turned down (not offline): they'd never go; let them go.
        if (!worthKeeping(e)) await box.deleteAll(keys);
        return;
      }
      await box.deleteAll(keys);
    }
  }
}
