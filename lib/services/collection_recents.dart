/// When each playlist or album was last played from, for the Library's
/// "Recently played" sort (Spotify's Recents). Kept in AppPrefs.
library;

import 'package:hive/hive.dart';

class CollectionRecents {
  CollectionRecents._();

  static const key = 'collectionLastPlayed';

  /// Most remembered: past this, the longest unplayed are forgotten.
  static const max = 500;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// Collection id → when it was last played from (ms since the epoch).
  /// Read once per sort, not per comparison.
  static Map<String, int> snapshot() {
    final raw = _prefs?.get(key);
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        if (e.key is String && e.value is int) e.key as String: e.value as int,
    };
  }

  static int? lastPlayed(String id) => snapshot()[id];

  /// Notes that playback started from the playlist or album [id].
  static Future<void> markPlayed(String id, {DateTime? at}) async {
    final prefs = _prefs;
    if (prefs == null || id.isEmpty) return;
    final all = snapshot()
      ..[id] = (at ?? DateTime.now()).millisecondsSinceEpoch;
    if (all.length > max) {
      final oldest = all.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final e in oldest.take(all.length - max)) {
        all.remove(e.key);
      }
    }
    await prefs.put(key, all);
  }
}

/// The comparator of a "Recently played" sort over [played] (a
/// [CollectionRecents.snapshot]): latest played first, never played last,
/// ties by [title].
Comparator<T> byLastPlayed<T>(Map<String, int> played, String Function(T) id,
        String Function(T) title) =>
    (a, b) {
      final x = played[id(a)];
      final y = played[id(b)];
      if (x != null && y != null && x != y) return y.compareTo(x);
      if ((x == null) != (y == null)) return x == null ? 1 : -1;
      return title(a).toLowerCase().compareTo(title(b).toLowerCase());
    };
