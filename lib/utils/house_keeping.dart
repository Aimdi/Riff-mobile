import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import '/models/media_Item_builder.dart';
import '/services/song_cache_service.dart';
import '/ui/screens/Library/library_controller.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'helper.dart';
import 'hive_boxes.dart';
import 'songs_url_cache.dart';

void startHouseKeeping() {
  removeExpiredSongsUrlFromDb();
  unawaited(evictSongCacheInBackground());
}

/// Size / age pass for auto-cached songs. Downloads and the active
/// queue are never deleted. Cheap: cooldown lives in [SongCacheService].
Future<void> evictSongCacheInBackground({bool force = false}) async {
  try {
    final decision = await SongCacheService().evictIfNeeded(force: force);
    if (decision != null && decision.idsToDelete.isNotEmpty) {
      _removeCachedIdsFromLibrary(decision.idsToDelete);
    }
  } catch (e) {
    printERROR('Error in evictSongCacheInBackground: $e');
  }
}

void _removeCachedIdsFromLibrary(Iterable<String> ids) {
  if (!Get.isRegistered<LibrarySongsController>()) return;
  final remove = ids.toSet();
  if (remove.isEmpty) return;
  Get.find<LibrarySongsController>()
      .librarySongsList
      .removeWhere((s) => remove.contains(s.id));
}

Future<void> removeExpiredSongsUrlFromDb() async {
  try {
    final songsUrlCacheBox = Hive.box(HiveBoxes.songsUrlCache);
    final songsUrlCacheKeysList =
        songsUrlCacheBox.keys.whereType<String>().toList();
    for (var i = 0; i < songsUrlCacheKeysList.length; i++) {
      final songUrlKey = songsUrlCacheKeysList[i];
      final entry = songsUrlCacheBox.get(songUrlKey);
      if (songsUrlCacheEntryExpired(entry)) {
        await songsUrlCacheBox.delete(songUrlKey);
      }
    }
  } catch (e) {
    printERROR("Error in removeExpiredSongsUrlFromDb: $e");
  } finally {
    removeDeletedOfflineSongsFromDb();
  }
}

Future<void> removeDeletedOfflineSongsFromDb() async {
  final supportDir = (await getApplicationSupportDirectory()).path;
  try {
    final songDownloadsBox = Hive.box(HiveBoxes.songDownloads);
    final downloadedSongs = songDownloadsBox.values.toList();
    final LibrarySongsController librarySongsController =
        Get.find<LibrarySongsController>();
    for (var i = 0; i < downloadedSongs.length; i++) {
      final songKey = downloadedSongs[i]['videoId'];
      final songUrl = downloadedSongs[i]['url'];
      if (await File(songUrl).exists() == false) {
        await songDownloadsBox.delete(songKey);
        await librarySongsController.removeSong(
            MediaItemBuilder.fromJson(downloadedSongs[i]), true);
        final thumbNailPath = "$supportDir/thumbnails/$songKey.png";
        if (await File(thumbNailPath).exists()) {
          await File(thumbNailPath).delete();
        }
      }
    }
  } catch (e) {
    printERROR("Error in removeDeletedOfflineSongsFromDb: $e");
  }
}
