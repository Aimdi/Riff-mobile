import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import 'helper.dart';

/// Sensitive values that must not live in plaintext Hive `AppPrefs`.
///
/// Sync getters read an in-memory cache populated by [init]. Writes go to
/// secure storage (+ cache) and delete the legacy Hive key when present.
class SecureCredentials {
  SecureCredentials._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static final Map<String, String> _cache = {};
  static bool ready = false;
  static Future<Map<String, String>>? _prefetched;

  /// Starts the secure-storage read now so it overlaps other cold-start
  /// work (main() opens the Hive boxes meanwhile); [init] uses its result.
  static void prefetch() {
    if (ready) return;
    // ignore(): a failure is reported where init() awaits it, not as an
    // unhandled error while nobody is listening yet.
    _prefetched ??= _storage.readAll()..ignore();
  }

  /// Flat AppPrefs keys migrated into secure storage.
  static const flatKeys = <String>[
    'ytAuthCookie',
    'soulseekPass',
    'mamId',
    'qbitPass',
    'listenBrainzToken',
    'spotifyAccessToken',
    'spotifyRefreshToken',
  ];

  /// Nested map fields stored as `mapKey.field` in secure storage.
  static const nestedSecrets = <String, String>{
    'cloudMusic': 'password',
    'audiobookshelf': 'token',
    'webdavSync': 'password',
  };

  static Future<void> init() async {
    if (ready) return;
    try {
      // One platform-channel round trip instead of a read per key (twice,
      // with the migration pass) — this sits on the cold-start path.
      final stored = await (_prefetched ?? _storage.readAll());
      for (final key in [
        ...flatKeys,
        for (final e in nestedSecrets.entries) '${e.key}.${e.value}',
      ]) {
        final v = stored[key];
        if (v != null && v.isNotEmpty) _cache[key] = v;
      }
      // Migration only touches in-memory Hive data unless a plaintext secret
      // is actually present (e.g. an old install or a restored backup), so it
      // costs nothing on a normal launch and needs no "done" flag.
      if (Hive.isBoxOpen('AppPrefs')) {
        final prefs = Hive.box('AppPrefs');
        for (final key in flatKeys) {
          await _migrateFlat(prefs, key);
        }
        for (final entry in nestedSecrets.entries) {
          await _migrateNested(prefs, entry.key, entry.value);
        }
      }
    } catch (e) {
      printERROR('SecureCredentials.init failed: $e');
    }
    _prefetched = null;
    ready = true;
  }

  @visibleForTesting
  static void resetForTest() {
    _cache.clear();
    _prefetched = null;
    ready = false;
  }

  static Future<void> _migrateFlat(Box prefs, String key) async {
    if (!prefs.containsKey(key)) return;
    if (_cache[key]?.isNotEmpty ?? false) {
      await prefs.delete(key);
      return;
    }
    final hive = prefs.get(key);
    if (hive is String && hive.isNotEmpty) {
      await _storage.write(key: key, value: hive);
      _cache[key] = hive;
      await prefs.delete(key);
    }
  }

  static Future<void> _migrateNested(
      Box prefs, String mapKey, String field) async {
    final secureKey = '$mapKey.$field';
    final cfg = prefs.get(mapKey);
    if (cfg is! Map || cfg[field] == null) return;
    if (!(_cache[secureKey]?.isNotEmpty ?? false)) {
      final secret = cfg[field]?.toString();
      if (secret == null || secret.isEmpty) return;
      await _storage.write(key: secureKey, value: secret);
      _cache[secureKey] = secret;
    }
    final copy = Map<String, dynamic>.from(cfg);
    copy.remove(field);
    await prefs.put(mapKey, copy);
  }

  static String? get(String key) {
    final v = _cache[key];
    if (v == null || v.isEmpty) return null;
    return v;
  }

  static Future<void> set(String key, String value) async {
    _cache[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      printERROR('SecureCredentials.set($key) failed: $e');
    }
    if (Hive.isBoxOpen('AppPrefs') && flatKeys.contains(key)) {
      await Hive.box('AppPrefs').delete(key);
    }
  }

  static Future<void> delete(String key) async {
    _cache.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (e) {
      printERROR('SecureCredentials.delete($key) failed: $e');
    }
    if (Hive.isBoxOpen('AppPrefs') && flatKeys.contains(key)) {
      await Hive.box('AppPrefs').delete(key);
    }
  }

  static String? nested(String mapKey, String field) =>
      get('$mapKey.$field');

  static Future<void> setNested(
      String mapKey, String field, String? value) async {
    final key = '$mapKey.$field';
    if (value == null || value.isEmpty) {
      await delete(key);
      return;
    }
    await set(key, value);
  }
}
