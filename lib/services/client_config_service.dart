import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '/utils/helper.dart';

/// Remotely updatable player-client fleet (the RiPlay approach): when
/// YouTube retires a client, updating stream_clients.json in the repo
/// fixes playback for everyone without shipping a new APK.
///
/// The raw JSON string is kept in [currentJson] so the audio isolate can
/// receive it by value (spawned isolates share no statics or Hive).
class ClientConfigService {
  ClientConfigService._();

  static const _url =
      'https://raw.githubusercontent.com/Aimdi/Riff-mobile/claude/harmony-music-android-fix-pu8w8a/stream_clients.json';

  /// Background freshness window for the cold-start refresh.
  static const ttlMs = 12 * 3600 * 1000;

  /// Minimum gap between two [forceRefresh] network attempts, so a track
  /// that keeps failing cannot hammer the endpoint.
  static const forceRefreshCooldownMs = 5 * 60 * 1000;

  static String? currentJson;

  /// Wall clock of the last [forceRefresh] network attempt (success or
  /// failure). In-memory only: a cold start should always be allowed one.
  static int lastForcedAttemptMs = 0;

  /// True when the cached copy is missing or older than [ttlMs].
  /// Pure — [init]'s only decision, split out so it can be unit-tested.
  static bool shouldRefresh({
    required bool hasCached,
    required int fetchedAtMs,
    required int nowMs,
  }) {
    if (!hasCached) return true;
    return (nowMs - fetchedAtMs) >= ttlMs;
  }

  /// True when a forced refresh is allowed, i.e. the cooldown has elapsed
  /// since [lastAttemptMs]. Pure. [lastAttemptMs] == 0 means "never tried".
  static bool forceRefreshAllowed({
    required int lastAttemptMs,
    required int nowMs,
  }) {
    if (lastAttemptMs <= 0) return true;
    // A clock that jumped backwards must not lock the lever out forever.
    if (nowMs < lastAttemptMs) return true;
    return (nowMs - lastAttemptMs) >= forceRefreshCooldownMs;
  }

  /// Validates a fetched config body before it is trusted / cached.
  ///
  /// Returns null when the body is a usable config, otherwise a short
  /// reason. `contains('attempts')` is not enough: a JSON file with a
  /// typo'd key parses, gets cached, then throws in the resolver and
  /// silently degrades to the built-in attempts — an emergency fix that
  /// ships as a no-op. This mirrors what StreamService actually reads:
  /// `attempts` -> non-empty groups -> entries with `apiUrl` + `payload`.
  static String? validateConfigJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'empty body';
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      return 'malformed JSON';
    }
    if (decoded is! Map) return 'root is not an object';
    final attempts = decoded['attempts'];
    if (attempts == null) return 'missing "attempts"';
    if (attempts is! List) return '"attempts" is not a list';
    if (attempts.isEmpty) return '"attempts" is empty';
    var groups = 0;
    for (final group in attempts) {
      if (group is! List) return 'attempt group is not a list';
      if (group.isEmpty) continue;
      for (final client in group) {
        if (client is! Map) return 'client entry is not an object';
        final apiUrl = client['apiUrl'];
        if (apiUrl is! String || apiUrl.trim().isEmpty) {
          return 'client entry missing "apiUrl"';
        }
        final payload = client['payload'];
        if (payload is! Map) return 'client entry missing "payload"';
        if (payload['context'] is! Map) {
          return 'client payload missing "context"';
        }
      }
      groups++;
    }
    if (groups == 0) return 'no non-empty attempt groups';
    return null;
  }

  /// Loads the cached config immediately and refreshes it from the repo
  /// when older than the TTL. Never throws.
  static Future<void> init() async {
    final box = Hive.box('AppPrefs');
    currentJson = box.get('streamClientsJson');
    final fetchedAt = box.get('streamClientsFetchedAt') ?? 0;
    if (!shouldRefresh(
        hasCached: currentJson != null,
        fetchedAtMs: fetchedAt is int ? fetchedAt : 0,
        nowMs: DateTime.now().millisecondsSinceEpoch)) {
      return;
    }
    await _fetchAndStore();
  }

  /// TTL-bypassing repair lever: pulls a fresh config even when the cached
  /// copy is young. Called from the stream-failure path and on app resume so
  /// a published fix reaches a resident install without waiting out the TTL.
  /// Rate-limited by [forceRefreshCooldownMs]. Never throws.
  ///
  /// Returns true when a network attempt was made (regardless of outcome).
  static Future<bool> forceRefresh() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!forceRefreshAllowed(lastAttemptMs: lastForcedAttemptMs, nowMs: now)) {
      return false;
    }
    lastForcedAttemptMs = now;
    await _fetchAndStore(forced: true);
    return true;
  }

  static Future<void> _fetchAndStore({bool forced = false}) async {
    try {
      final res = await Dio().get(_url,
          options: Options(
              responseType: ResponseType.plain,
              receiveTimeout: const Duration(seconds: 10)));
      if (res.statusCode != 200) {
        printERROR(
            "Stream client config fetch returned HTTP ${res.statusCode}");
        return;
      }
      final body = res.data is String ? res.data as String : null;
      final problem = validateConfigJson(body);
      if (problem != null) {
        printERROR("Stream client config rejected ($problem) — keeping cache");
        return;
      }
      currentJson = body;
      try {
        final box = Hive.box('AppPrefs');
        box.put('streamClientsJson', currentJson);
        box.put('streamClientsFetchedAt', DateTime.now().millisecondsSinceEpoch);
      } catch (e) {
        // Config still applies for this session even if it can't be cached.
        printERROR("Stream client config cache write failed: $e");
      }
      printINFO(forced
          ? "Stream client config force-refreshed from repo"
          : "Stream client config refreshed from repo");
    } catch (e) {
      printERROR("Stream client config refresh failed: $e");
    }
  }
}
