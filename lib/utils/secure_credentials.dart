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

  /// Flat AppPrefs keys migrated into secure storage.
  static const flatKeys = <String>[
    'ytAuthCookie',
    'soulseekPass',
    'mamId',
    'qbitPass',
    'listenBrainzToken',
  ];

  /// Nested map fields stored as `mapKey.field` in secure storage.
  static const nestedSecrets = <String, String>{
    'cloudMusic': 'password',
    'audiobookshelf': 'token',
  };

  static Future<void> init() async {
    if (ready) return;
    try {
      if (Hive.isBoxOpen('AppPrefs')) {
        final prefs = Hive.box('AppPrefs');
        for (final key in flatKeys) {
          await _migrateFlat(prefs, key);
        }
        for (final entry in nestedSecrets.entries) {
          await _migrateNested(prefs, entry.key, entry.value);
        }
      }
      // Load anything already in secure storage (fresh install / prior migrate).
      for (final key in flatKeys) {
        _cache[key] ??= (await _storage.read(key: key)) ?? '';
        if (_cache[key]!.isEmpty) _cache.remove(key);
      }
      for (final entry in nestedSecrets.entries) {
        final sk = '${entry.key}.${entry.value}';
        _cache[sk] ??= (await _storage.read(key: sk)) ?? '';
        if (_cache[sk]!.isEmpty) _cache.remove(sk);
      }
    } catch (e) {
      printERROR('SecureCredentials.init failed: $e');
    }
    ready = true;
  }

  static Future<void> _migrateFlat(Box prefs, String key) async {
    final existing = await _storage.read(key: key);
    if (existing != null && existing.isNotEmpty) {
      _cache[key] = existing;
      if (prefs.containsKey(key)) await prefs.delete(key);
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
    final existing = await _storage.read(key: secureKey);
    if (existing != null && existing.isNotEmpty) {
      _cache[secureKey] = existing;
      final cfg = prefs.get(mapKey);
      if (cfg is Map && cfg[field] != null) {
        final copy = Map<String, dynamic>.from(cfg);
        copy.remove(field);
        await prefs.put(mapKey, copy);
      }
      return;
    }
    final cfg = prefs.get(mapKey);
    if (cfg is Map) {
      final secret = cfg[field]?.toString();
      if (secret != null && secret.isNotEmpty) {
        await _storage.write(key: secureKey, value: secret);
        _cache[secureKey] = secret;
        final copy = Map<String, dynamic>.from(cfg);
        copy.remove(field);
        await prefs.put(mapKey, copy);
      }
    }
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
