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

  static Future<Box> fav() => open(libFav);

  static bool favContains(String songId) =>
      favSync()?.containsKey(songId) ?? false;

  static Box? songsCacheSync() => maybe(songsCache);

  static Future<Box> songsCacheBox() => open(songsCache);

  static Box? songDownloadsSync() => maybe(songDownloads);

  static Future<Box> songDownloadsBox() => open(songDownloads);

  static Box? songStatsSync() => maybe(songStats);
}
