/// How a show's episode list is shown, kept per show as Pocket Casts and
/// AntennaPod keep it: oldest first (for series heard in order) and
/// played episodes hidden.
library;

import 'package:hive/hive.dart';

class PodcastShowViewPrefs {
  PodcastShowViewPrefs._();

  /// AppPrefs keys: the shows (their playback keys) that list oldest
  /// first, those set back to newest first, and those that hide played
  /// episodes.
  static const oldestFirstKey = 'podcastShowsOldestFirst';
  static const newestFirstKey = 'podcastShowsNewestFirst';
  static const hidePlayedKey = 'podcastShowsHidePlayed';

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// Oldest first: as set for [show], else as its feed says it's heard: a
  /// [serial] show from its start, as Apple Podcasts lists one.
  static bool oldestFirst(String? show, {bool serial = false}) =>
      _has(oldestFirstKey, show) || (serial && !_has(newestFirstKey, show));
  static bool hidePlayed(String? show) => _has(hidePlayedKey, show);

  static Future<void> setOldestFirst(String show, bool on) async {
    await _set(oldestFirstKey, show, on);
    await _set(newestFirstKey, show, !on);
  }

  static Future<void> setHidePlayed(String show, bool on) =>
      _set(hidePlayedKey, show, on);

  static Set<String> _shows(String key) {
    final raw = _prefs?.get(key);
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  static bool _has(String key, String? show) =>
      show != null && _shows(key).contains(show);

  static Future<void> _set(String key, String show, bool on) async {
    final shows = _shows(key);
    on ? shows.add(show) : shows.remove(show);
    await _prefs?.put(key, shows.toList());
  }
}

/// The feed-order indexes (newest first) of a show's [count] episodes as
/// listed: reversed when [oldestFirst], and without those [hidden] says to
/// leave out.
List<int> showEpisodeOrder(int count,
    {required bool oldestFirst, bool Function(int index)? hidden}) {
  final order = [
    for (var i = 0; i < count; i++)
      if (hidden == null || !hidden(i)) i,
  ];
  return oldestFirst ? order.reversed.toList() : order;
}
