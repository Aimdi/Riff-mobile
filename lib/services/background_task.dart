import 'dart:core';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:harmonymusic/services/stream_service.dart';

Future<Map<String, dynamic>> getStreamInfo(String songId, dynamic token,
    {String? clientConfigJson, bool fetchLoudness = false}) async {
  if (songId.substring(0, 4) == "MPED") {
    songId = songId.substring(4);
  }
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final playerResponse =
      (await StreamProvider.fetch(songId, clientConfigJson: clientConfigJson));
  final data = playerResponse.hmStreamingData;
  // Loudness used to always hit youtubei /player after resolve — that added a
  // full network RTT to every cache-miss play. Only fetch when normalization
  // is enabled (caller passes fetchLoudness: true).
  if (playerResponse.playable && fetchLoudness) {
    final loudnessDb = await _fetchLoudnessDb(songId);
    for (final key in ["lowQualityAudio", "highQualityAudio"]) {
      if (data[key] != null) data[key]["loudnessDb"] = loudnessDb;
    }
  }
  return data;
}

/// Fetches the track's perceptual loudness for volume normalization
/// (playerConfig.audioConfig.loudnessDb) with a lightweight player call.
/// -5.0 means "reference loudness / no adjustment" on failure.
Future<double> _fetchLoudnessDb(String songId) async {
  try {
    final res = await Dio().post(
      'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
      options: Options(
          headers: {'content-type': 'application/json'},
          receiveTimeout: const Duration(seconds: 6)),
      data: {
        'context': {
          'client': {
            'clientName': 'ANDROID_VR',
            'clientVersion': '1.65.10',
            'osName': 'Android',
            'osVersion': '12L',
            'androidSdkVersion': 32,
            'userAgent':
                'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
            'hl': 'en',
          },
        },
        'videoId': songId,
      },
    );
    final v = res.data?['playerConfig']?['audioConfig']?['loudnessDb'];
    if (v is num) return v.toDouble();
    return -5.0;
  } catch (_) {
    return -5.0;
  }
}
