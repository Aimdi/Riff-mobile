import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get/get.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:hive/hive.dart';

import '/services/better_lyrics_service.dart';
import '/services/kugou_lyrics_service.dart';
import '/services/lrclib_query.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';

class SyncedLyricsService {
  // One client for every LRCLIB lookup (was a new, never-closed Dio per
  // song) with a connect timeout, so a dead network can't park the lookup.
  static final _lrclibDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 8),
  ));

  /// The cache entry for an LRCLIB `/api/get` answer, or null when it has
  /// no synced lyrics or isn't the JSON object it should be.
  @visibleForTesting
  static Map<String, dynamic>? lrclibHit(dynamic response) {
    if (response is! Map) return null;
    final synced = response["syncedLyrics"];
    if (synced is! String || synced.isEmpty) return null;
    return {
      "synced": synced,
      "plainLyrics": response["plainLyrics"],
      "source": "lrclib",
    };
  }

  static LyricsSource _preferredSource() {
    if (Get.isRegistered<SettingsScreenController>()) {
      return Get.find<SettingsScreenController>().lyricsSource.value;
    }
    final raw = Hive.box('AppPrefs').get('lyricsSource');
    if (raw is int && raw >= 0 && raw < LyricsSource.values.length) {
      return LyricsSource.values[raw];
    }
    return LyricsSource.auto;
  }

  static Future<Map<String, dynamic>?> getSyncedLyrics(
      MediaItem song, int durInSec) async {
    // Opened once and left open: closing it here raced overlapping lookups
    // (one call closed the box under another's put → HiveError).
    final lyricsBox = Hive.isBoxOpen("lyrics")
        ? Hive.box("lyrics")
        : await Hive.openBox("lyrics");
    if (lyricsBox.containsKey(song.id)) {
      return Map<String, dynamic>.from(await lyricsBox.get(song.id));
    }

    final dur = song.duration?.inSeconds ?? durInSec;
    final artist = song.artist ?? '';
    final title = song.title;
    final album = song.album;
    final source = _preferredSource();

    Future<Map<String, dynamic>?> tryBetter() async {
      final r = await BetterLyricsService.fetch(
        artist: artist,
        title: title,
        album: album,
        durationSec: dur,
      );
      if (r == null) return null;
      return {
        "synced": r.lrc,
        "plainLyrics": r.plain,
        "ttml": r.ttml,
        "source": "betterLyrics",
      };
    }

    Future<Map<String, dynamic>?> tryLrclib() async {
      try {
        final response = (await _lrclibDio.get(
          lrclibGetUrl,
          queryParameters: buildLrclibGetParams(
            artist: artist,
            title: title,
            album: album,
            durationSec: dur,
          ),
        )).data;
        final hit = lrclibHit(response);
        if (hit != null) printINFO("Synced lyrics from LRCLIB");
        return hit;
      } on DioException catch (e) {
        printINFO("LRCLIB miss: ${e.response?.statusCode}");
      } catch (e) {
        // Anything else (an unexpected body) must not end the provider
        // chain: the next provider still gets its turn.
        printINFO("LRCLIB lookup failed: $e");
      }
      return null;
    }

    Future<Map<String, dynamic>?> tryKugou() async {
      try {
        final kugou =
            await KuGouLyricsService.getSyncedLyrics(artist, title, dur);
        if (kugou != null) {
          printINFO("Synced lyrics from KuGou");
          return {"synced": kugou, "plainLyrics": null, "source": "kugou"};
        }
      } catch (e) {
        printINFO("KuGou fallback failed: $e");
      }
      return null;
    }

    final providers = <Future<Map<String, dynamic>?> Function()>[];
    switch (source) {
      case LyricsSource.betterLyrics:
        providers.addAll([tryBetter, tryLrclib, tryKugou]);
        break;
      case LyricsSource.lrclib:
        providers.addAll([tryLrclib, tryKugou]);
        break;
      case LyricsSource.auto:
        providers.addAll([tryLrclib, tryBetter, tryKugou]);
        break;
    }

    for (final p in providers) {
      final hit = await p();
      if (hit != null) {
        await lyricsBox.put(song.id, hit);
        return hit;
      }
    }
    return null;
  }
}
