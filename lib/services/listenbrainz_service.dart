import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '/utils/helper.dart';

/// ListenBrainz scrobbling (ported from Riff desktop). Disabled unless the
/// user saves a token in Settings; failures are logged and never surface
/// to playback.
class ListenBrainzService {
  ListenBrainzService._();

  static const _endpoint = "https://api.listenbrainz.org/1/submit-listens";

  static String get token =>
      Hive.box("AppPrefs").get("listenBrainzToken") ?? "";

  static bool get enabled => token.isNotEmpty;

  static Future<void> setToken(String value) =>
      Hive.box("AppPrefs").put("listenBrainzToken", value.trim());

  static Future<void> submitListen(MediaItem item) async {
    if (!enabled) return;
    try {
      await Dio().post(
        _endpoint,
        options: Options(headers: {
          "Authorization": "Token $token",
          "Content-Type": "application/json",
        }),
        data: {
          "listen_type": "single",
          "payload": [
            {
              "listened_at":
                  DateTime.now().millisecondsSinceEpoch ~/ 1000,
              "track_metadata": {
                "artist_name": item.artist ?? "",
                "track_name": item.title,
                if (item.album != null) "release_name": item.album,
                "additional_info": {
                  "media_player": "Riff",
                  "submission_client": "Riff",
                }
              }
            }
          ]
        },
      );
    } catch (e) {
      printERROR("ListenBrainz submit failed: $e");
    }
  }
}
