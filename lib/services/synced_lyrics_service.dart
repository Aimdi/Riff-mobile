import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:harmonymusic/utils/helper.dart';
import 'package:hive/hive.dart';

import '/services/kugou_lyrics_service.dart';

class SyncedLyricsService {
  static Future<Map<String, dynamic>?> getSyncedLyrics(
      MediaItem song, int durInSec) async {
    final lyricsBox = await Hive.openBox("lyrics");
    // check if lyrics available in local database
    if (lyricsBox.containsKey(song.id)) {
      return Map<String, dynamic>.from(await lyricsBox.get(song.id));
    }

    final dur = song.duration?.inSeconds ?? durInSec;
    try {
      // Provider 1: LRCLIB.
      final url =
          'https://lrclib.net/api/get?artist_name=${song.artist?.replaceAll(" ", "+")}&track_name=${song.title.replaceAll(" ", "+")}&album_name=${song.album?.replaceAll(" ", "+")}&duration=$dur';
      final response = (await Dio().get(url)).data;
      if (response["syncedLyrics"] != null) {
        printINFO("Synced lyrics from LRCLIB");
        final lyricsData = {
          "synced": response["syncedLyrics"],
          "plainLyrics": response["plainLyrics"]
        };
        await lyricsBox.put(song.id, lyricsData);
        await lyricsBox.close();
        return lyricsData;
      }
    } on DioException catch (e) {
      printINFO("LRCLIB miss: ${e.response?.statusCode}");
    }

    // Provider 2: KuGou fallback (ported from RiPlay) — wider coverage.
    try {
      final kugou = await KuGouLyricsService.getSyncedLyrics(
          song.artist ?? "", song.title, dur);
      if (kugou != null) {
        printINFO("Synced lyrics from KuGou");
        final lyricsData = {"synced": kugou, "plainLyrics": null};
        await lyricsBox.put(song.id, lyricsData);
        return lyricsData;
      }
    } catch (e) {
      printINFO("KuGou fallback failed: $e");
    } finally {
      await lyricsBox.close();
    }
    return null;
  }
}
