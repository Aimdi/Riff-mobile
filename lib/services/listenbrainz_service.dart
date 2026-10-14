import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive/hive.dart';

import '/utils/helper.dart';
import '/utils/secure_credentials.dart';

/// ListenBrainz scrobbling (ported from Riff desktop). Disabled unless the
/// user saves a token in Settings; failures are logged and never surface
/// to playback.
///
/// As Spotify's Last.fm scrobbling and Pano Scrobbler do: a listen that
/// can't be sent (offline, ListenBrainz down) is kept and goes with the
/// next one that can; and the song playing shows as "playing now".
class ListenBrainzService {
  ListenBrainzService._();

  static const _endpoint = "https://api.listenbrainz.org/1/submit-listens";

  /// Listens kept until they can be sent.
  static const pendingBox = 'ListenBrainzPending';

  /// Most listens kept (the oldest go first past it), and most sent at once.
  @visibleForTesting
  static int maxKept = 1000;
  static const _batch = 100;

  // One shared client (was a new Dio per scrobble) with timeouts so a hung
  // connection can't pile up pending submissions.
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  static String get token => SecureCredentials.get("listenBrainzToken") ?? "";

  static bool get enabled => token.isNotEmpty;

  static Future<void> setToken(String value) =>
      SecureCredentials.set("listenBrainzToken", value.trim());

  /// Posts a submission to ListenBrainz; throws when it isn't taken.
  @visibleForTesting
  static Future<void> Function(Map<String, dynamic> body) send =
      (body) => _dio.post(
            _endpoint,
            options: Options(headers: {
              "Authorization": "Token $token",
              "Content-Type": "application/json",
            }),
            data: body,
          );

  /// What ListenBrainz knows a song by.
  static Map<String, dynamic> trackMetadata(MediaItem item) => {
        "artist_name": item.artist ?? "",
        "track_name": item.title,
        if (item.album != null) "release_name": item.album,
        "additional_info": {
          "media_player": "Riff",
          "submission_client": "Riff",
        }
      };

  /// [item] listened to at [at].
  static Map<String, dynamic> listen(MediaItem item, DateTime at) => {
        "listened_at": at.millisecondsSinceEpoch ~/ 1000,
        "track_metadata": trackMetadata(item),
      };

  /// Whether a listen that failed with [error] can go later: no connection,
  /// or ListenBrainz busy or down. Not one it turned down (a bad token).
  static bool worthKeeping(Object error) {
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

  static Future<void> submitListen(MediaItem item, {DateTime? now}) async {
    if (!enabled) return;
    final entry = listen(item, now ?? DateTime.now());
    try {
      await send({
        "listen_type": "single",
        "payload": [entry]
      });
    } catch (e) {
      printERROR("ListenBrainz submit failed: $e");
      if (worthKeeping(e)) await _keep(entry);
      return;
    }
    await sendKept();
  }

  /// [item] started playing: ListenBrainz shows it as playing now. Not
  /// kept when it can't be sent (it's no news later).
  static Future<void> playingNow(MediaItem item) async {
    if (!enabled) return;
    try {
      await send({
        "listen_type": "playing_now",
        "payload": [
          {"track_metadata": trackMetadata(item)}
        ]
      });
    } catch (e) {
      printINFO("ListenBrainz playing now failed: $e");
      return;
    }
    await sendKept();
  }

  static Future<void> _keep(Map<String, dynamic> entry) async {
    // ListenBrainz turns down a listen without both names: not one to keep
    // (it would take the rest of its batch down with it).
    final track = entry["track_metadata"];
    if (track is! Map ||
        '${track["artist_name"] ?? ''}'.trim().isEmpty ||
        '${track["track_name"] ?? ''}'.trim().isEmpty) {
      return;
    }
    final box = await _pending();
    if (box == null) return;
    await box.add(entry);
    final extra = box.length - maxKept;
    if (extra > 0) await box.deleteAll(box.keys.take(extra).toList());
  }

  static Future<void>? _sendingKept;

  /// Sends the listens kept while they couldn't go, oldest first, in
  /// batches; what still can't go stays for next time. One at a time: a
  /// song change scrobbles one song and says the next is playing at once.
  static Future<void> sendKept() =>
      _sendingKept ??= _sendKept().whenComplete(() => _sendingKept = null);

  static Future<void> _sendKept() async {
    final box = await _pending();
    if (box == null) return;
    while (box.isNotEmpty) {
      final keys = box.keys.take(_batch).toList();
      final listens = [
        for (final k in keys)
          if (box.get(k) case final Map v) Map<String, dynamic>.from(v)
      ];
      try {
        if (listens.isNotEmpty) {
          await send({"listen_type": "import", "payload": listens});
        }
      } catch (e) {
        printERROR("ListenBrainz kept listens failed: $e");
        // Turned down (not offline): they'd never go; let them go.
        if (!worthKeeping(e)) await box.deleteAll(keys);
        return;
      }
      await box.deleteAll(keys);
    }
  }
}
