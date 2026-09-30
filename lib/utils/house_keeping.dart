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
    final expiredKeys = songsUrlCacheBox.keys
        .whereType<String>()
        .where((key) => songsUrlCacheEntryExpired(songsUrlCacheBox.get(key)))
        .toList();
    // One batched delete instead of a disk write per expired entry.
    if (expiredKeys.isNotEmpty) await songsUrlCacheBox.deleteAll(expiredKeys);
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
    for (final song in downloadedSongs) {
      // A malformed entry (no url / not a map) must be skipped, not throw:
      // the catch below would abort cleanup for every remaining song.
      if (song is! Map) continue;
      final songKey = song['videoId'];
      final songUrl = song['url'];
      if (songKey is! String || songUrl is! String || songUrl.isEmpty) {
        continue;
      }
      try {
        if (await File(songUrl).exists() == false) {
          await songDownloadsBox.delete(songKey);
          await librarySongsController.removeSong(
              MediaItemBuilder.fromJson(song), true);
          final thumbNailPath = "$supportDir/thumbnails/$songKey.png";
          if (await File(thumbNailPath).exists()) {
            await File(thumbNailPath).delete();
          }
        }
      } catch (e) {
        printERROR("House keeping skipped $songKey: $e");
      }
    }
  } catch (e) {
    printERROR("Error in removeDeletedOfflineSongsFromDb: $e");
  }
}
