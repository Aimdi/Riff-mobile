/// Playlists pinned to the top of the Library, like Spotify's Pin: they
/// stay first (after Riff's own four) whatever the sort or search.
library;

import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/playlist.dart';

class LibraryPins {
  LibraryPins._();

  static const key = 'pinnedPlaylists';

  /// Most playlists pinned at once, as in Spotify.
  static const max = 4;

  /// Bumped on every change, for Obx.
  static final rev = 0.obs;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// Pinned playlist ids, the latest pin first.
  static List<String> get ids {
    final raw = _prefs?.get(key);
    return raw is List ? raw.whereType<String>().toList() : <String>[];
  }

  static bool isPinned(String id) => ids.contains(id);

  /// Pins [id] on top of the others, or unpins it. When [max] are pinned,
  /// pins of playlists no longer in [library] make room; false when none
  /// do.
  static Future<bool> toggle(String id, {Set<String>? library}) async {
    final prefs = _prefs;
    if (prefs == null) return false;
    final next = ids;
    if (!next.remove(id)) {
      if (next.length >= max && library != null) {
        next.retainWhere(library.contains);
      }
      if (next.length >= max) return false;
      next.insert(0, id);
    }
    await _save(prefs, next);
    return true;
  }

  /// Drops [id]'s pin, if it has one: the playlist left the library.
  static Future<void> forget(String id) async {
    final prefs = _prefs;
    final next = ids;
    if (prefs == null || !next.remove(id)) return;
    await _save(prefs, next);
  }

  static Future<void> _save(Box prefs, List<String> next) async {
    await prefs.put(key, next);
    rev.value++;
  }
}

/// [playlists] in Library order: the [fixed] ones (Riff's own) first as
/// they are, then the [pins] in pin order, then the rest as they were.
List<Playlist> orderLibraryPlaylists(
    List<Playlist> playlists, List<String> pins, Set<String> fixed) {
  final top = [
    for (final p in playlists)
      if (fixed.contains(p.playlistId)) p
  ];
  final pinned = [
    for (final id in pins)
      for (final p in playlists)
        if (p.playlistId == id && !fixed.contains(id)) p
  ];
  final rest = [
    for (final p in playlists)
      if (!fixed.contains(p.playlistId) && !pins.contains(p.playlistId)) p
  ];
  return [...top, ...pinned, ...rest];
}
