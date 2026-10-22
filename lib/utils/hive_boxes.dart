import 'package:hive/hive.dart';

/// Named Hive boxes used across controllers.
///
/// Prefer these accessors over repeating string literals and
/// `isBoxOpen` / `openBox` checks. Boxes listed here are opened at
/// startup in `main.dart` except where noted.
class HiveBoxes {
  static const appPrefs = 'AppPrefs';
  static const libFav = 'LIBFAV';
  static const libRp = 'LIBRP';
  static const songsCache = 'SongsCache';
  static const songDownloads = 'SongDownloads';
  static const songsUrlCache = 'SongsUrlCache';
  static const songStats = 'SongStats';
  static const prevSessionData = 'prevSessionData';

  static Box prefs() => Hive.box(appPrefs);

  static Box? maybe(String name) =>
      Hive.isBoxOpen(name) ? Hive.box(name) : null;

  static Future<Box> open(String name) async {
    final existing = maybe(name);
    if (existing != null) return existing;
    return Hive.openBox(name);
  }

  static Box? favSync() => maybe(libFav);

  static Future<Box> fav() async {
    final box = await open(libFav);
    await repairFavoriteKeys(box);
    return box;
  }

  /// Favorites are kept by song id ([favContains], the hearts, like sync).
  /// Rewriting the box by position (a reorder, an Undo) once keyed them
  /// 0..n-1, which left every heart empty: back to song ids.
  static Future<void> repairFavoriteKeys(Box box) async {
    if (!box.keys.any((k) => k is int)) return;
    await writeFavorites(box, box.values.toList());
  }

  /// Replaces Favorites with [values] (song maps), each under its song id.
  static Future<void> writeFavorites(Box box, List values) async {
    final byId = <String, dynamic>{
      for (final v in values)
        if (v is Map && v['videoId'] is String) v['videoId'] as String: v,
    };
    await box.clear();
    await box.putAll(byId);
  }

  static bool favContains(String songId) =>
      favSync()?.containsKey(songId) ?? false;

  static Box? songsCacheSync() => maybe(songsCache);

  static Future<Box> songsCacheBox() => open(songsCache);

  static Box? songDownloadsSync() => maybe(songDownloads);

  static Future<Box> songDownloadsBox() => open(songDownloads);

  static Box? songStatsSync() => maybe(songStats);
}
