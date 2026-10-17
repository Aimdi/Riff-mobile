/// Settings › Remove downloaded songs, as Spotify's Remove all downloads
/// and YouTube Music's Delete downloads: every downloaded song's file
/// and cover go, and the songs play online again. Podcast episodes keep
/// their downloads.
library;

import 'dart:io';

import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'downloader.dart';
import 'pending_downloads.dart';
import 'smart_downloads.dart';

/// Removes every downloaded song: its file, its cover in [supportDir] and
/// its entry. Returns the ids removed.
Future<List<String>> removeAllSongDownloads(
    {required String supportDir}) async {
  if (!Hive.isBoxOpen('SongDownloads')) return const [];
  // What's waiting to download goes too, or it would fill the room again
  // (and come back after a restart).
  if (Get.isRegistered<Downloader>()) {
    final downloader = Get.find<Downloader>();
    downloader.playlistQueue.clear();
    downloader.songQueue.clear();
  }
  if (Hive.isBoxOpen(PendingDownloads.boxName)) {
    await Hive.box(PendingDownloads.boxName).clear();
  }
  final box = Hive.box('SongDownloads');
  final ids = [for (final key in box.keys) '$key'];
  for (final entry in box.toMap().entries) {
    final raw = entry.value;
    final path = raw is Map ? '${raw['url'] ?? ''}' : '';
    await _delete(path.startsWith('file://') ? path.substring(7) : path);
    await _delete('$supportDir/thumbnails/${entry.key}.png');
  }
  await box.clear();
  // Smart downloads start afresh: what they'd downloaded wasn't deleted
  // one by one (which would keep them from downloading it again).
  await SmartDownloads.forgetDownloads();
  return ids;
}

Future<void> _delete(String path) async {
  if (path.isEmpty || path.startsWith('http')) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}
