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
  static const _ttlMs = 12 * 3600 * 1000;

  static String? currentJson;

  /// Loads the cached config immediately and refreshes it from the repo
  /// when older than the TTL. Never throws.
  static Future<void> init() async {
    final box = Hive.box('AppPrefs');
    currentJson = box.get('streamClientsJson');
    final fetchedAt = box.get('streamClientsFetchedAt') ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - fetchedAt;
    if (currentJson != null && age < _ttlMs) return;
    try {
      final res = await Dio().get(_url,
          options: Options(
              responseType: ResponseType.plain,
              receiveTimeout: const Duration(seconds: 10)));
      if (res.statusCode == 200 && (res.data as String).contains('attempts')) {
        currentJson = res.data;
        box.put('streamClientsJson', currentJson);
        box.put('streamClientsFetchedAt',
            DateTime.now().millisecondsSinceEpoch);
        printINFO("Stream client config refreshed from repo");
      }
    } catch (e) {
      printERROR("Stream client config refresh failed: $e");
    }
  }
}
