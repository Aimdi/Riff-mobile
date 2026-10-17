/// Photos people give their own playlists, like Spotify's "Change image":
/// a square JPEG each, made the way folder photos are ([FolderCoverStore]),
/// kept on this device by playlist id. A photo wins over any other art.
library;

import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'folder_cover.dart';

class PlaylistCovers {
  PlaylistCovers._();

  /// AppPrefs key of the playlist id → photo path map.
  static const key = 'playlistCovers';

  /// Folder of the photos, beside the folder photos.
  static const subdir = 'playlist_covers';

  /// Bumped on every change, for Obx.
  static final rev = 0.obs;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static Map<String, String> get _all {
    final raw = _prefs?.get(key);
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        if (e.key is String && e.value is String && e.value != '')
          e.key as String: e.value as String,
    };
  }

  /// The photo of playlist [id], if it has one.
  static String? pathFor(String id) => _all[id];

  /// Makes [original] the photo of playlist [id] (the old one's file goes).
  /// False when it isn't a usable image.
  static Future<bool> set(String id, Uint8List original) async {
    final path = await FolderCoverStore.save(
        id.replaceAll(RegExp(r'[^\w-]'), '_'), original,
        subdir: subdir);
    if (path == null) return false;
    await _put(id, path);
    return true;
  }

  /// Takes playlist [id]'s photo away, file and all.
  static Future<void> remove(String id) => _put(id, null);

  static Future<void> _put(String id, String? path) async {
    final prefs = _prefs;
    if (prefs == null) {
      FolderCoverStore.delete(path);
      return;
    }
    final all = _all;
    final old = all.remove(id);
    if (path == null && old == null) return;
    if (path != null) all[id] = path;
    await prefs.put(key, all);
    if (old != path) FolderCoverStore.delete(old);
    rev.value++;
  }
}
