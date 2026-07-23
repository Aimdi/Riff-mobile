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

  static Future<Map<String, dynamic>?> getSyncedLyrics(
      MediaItem song, int durInSec) async {
    final lyricsBox = await Hive.openBox("lyrics");
    // check if lyrics available in local database
    if (lyricsBox.containsKey(song.id)) {
      return Map<String, dynamic>.from(await lyricsBox.get(song.id));
    }

    final dur = song.duration?.inSeconds ?? durInSec;
    final artist = song.artist ?? '';
    final title = song.title;
    final album = song.album;
    final source = _preferredSource();

    Future<Map<String, dynamic>?> tryBetter() async {
      final lrc = await BetterLyricsService.getSyncedLyrics(
        artist: artist,
        title: title,
        album: album,
        durationSec: dur,
      );
      if (lrc == null) return null;
      return {"synced": lrc, "plainLyrics": _plainFromLrc(lrc)};
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
            "plainLyrics": response["plainLyrics"]
          };
        }
      } on DioException catch (e) {
        printINFO("LRCLIB miss: ${e.response?.statusCode}");
      }
      return null;
    }

    Future<Map<String, dynamic>?> tryKugou() async {
      try {
        final kugou = await KuGouLyricsService.getSyncedLyrics(
            artist, title, dur);
        if (kugou != null) {
          printINFO("Synced lyrics from KuGou");
          return {"synced": kugou, "plainLyrics": null};
        }
      } catch (e) {
        printINFO("KuGou fallback failed: $e");
      }
      return null;
    }

    // Build provider order from Settings → Lyrics source.
    final providers = <Future<Map<String, dynamic>?> Function()>[];
    switch (source) {
      case LyricsSource.betterLyrics:
        providers.addAll([tryBetter, tryLrclib, tryKugou]);
        break;
      case LyricsSource.lrclib:
        providers.addAll([tryLrclib, tryKugou]);
        break;
      case LyricsSource.auto:
        // Balanced: LRCLIB first, then Better Lyrics, then KuGou.
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

  static String? _plainFromLrc(String lrc) {
    final lines = lrc
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^\[[^\]]+\]'), '').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;
    return lines.join('\n');
  }
}
