import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:hive/hive.dart';

import '/services/better_lyrics_service.dart';
import '/services/kugou_lyrics_service.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';

class SyncedLyricsService {
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

  /// flutter_lyric's LRC parser mis-handles sub-second stamps shorter than
  /// 3 digits ([mm:ss.47] parses as 47ms instead of 470ms), firing every
  /// line early by a per-line amount — the "lyrics out of sync" bug. All
  /// providers emit 2-digit stamps; padding to 3 digits routes the parser
  /// through its correct branch. Idempotent, applied to cached copies too.
  static String normalizeLrcTimestamps(String lrc) {
    return lrc.replaceAllMapped(
      RegExp(r'\[(\d{1,2}):(\d{2})\.(\d{1,2})\]'),
      (m) => '[${m[1]}:${m[2]}.${m[3]!.padRight(3, '0')}]',
    );
  }

  static Future<Map<String, dynamic>?> getSyncedLyrics(
      MediaItem song, int durInSec) async {
    final r = await _getSyncedLyricsRaw(song, durInSec);
    final synced = r?['synced'];
    if (synced is String && synced.isNotEmpty) {
      r!['synced'] = normalizeLrcTimestamps(synced);
    }
    return r;
  }

  static Future<Map<String, dynamic>?> _getSyncedLyricsRaw(
      MediaItem song, int durInSec) async {
    final lyricsBox = await Hive.openBox("lyrics");
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
        final url =
            'https://lrclib.net/api/get?artist_name=${artist.replaceAll(" ", "+")}&track_name=${title.replaceAll(" ", "+")}&album_name=${album?.replaceAll(" ", "+")}&duration=$dur';
        final response = (await Dio().get(url)).data;
        if (response["syncedLyrics"] != null) {
          printINFO("Synced lyrics from LRCLIB");
          return {
            "synced": response["syncedLyrics"],
            "plainLyrics": response["plainLyrics"],
            "source": "lrclib",
          };
        }
      } on DioException catch (e) {
        printINFO("LRCLIB miss: ${e.response?.statusCode}");
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

    try {
      for (final p in providers) {
        final hit = await p();
        if (hit != null) {
          await lyricsBox.put(song.id, hit);
          await lyricsBox.close();
          return hit;
        }
      }
    } finally {
      if (lyricsBox.isOpen) await lyricsBox.close();
    }
    return null;
  }
}
