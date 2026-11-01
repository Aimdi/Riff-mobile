/// When each playlist or album was last played from, for the Library's
/// "Recently played" sort (Spotify's Recents) and Home's Recently played
/// shelf, with what that shelf shows of one Riff doesn't keep otherwise.
/// Kept in AppPrefs.
library;

import 'package:hive/hive.dart';

/// A collection played from, as Home's Recently played shows it.
class RecentCollection {
  const RecentCollection(
      {required this.id,
      required this.at,
      this.type,
      this.name = '',
      this.art,
      this.by,
      this.piped = false});

  final String id;

  /// When it was last played from (ms since the epoch).
  final int at;

  /// 'album' or 'playlist'; null when only the time is known (played
  /// before Riff kept more).
  final String? type;
  final String name;
  final String? art;

  /// Who it's by (an album's artist, a playlist's description).
  final String? by;

  /// A playlist of the connected Piped account.
  final bool piped;
}

class CollectionRecents {
  CollectionRecents._();

  static const key = 'collectionLastPlayed';

  /// Collection id → {type, name, art, by}, for Home's Recently played.
  static const infoKey = 'collectionPlayedInfo';

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

  /// Notes that playback started from the playlist or album [id], and
  /// what Home shows of it: its [type] ('album' or 'playlist'), [name],
  /// cover ([art]) and who it's [by]. What a play doesn't say is kept from
  /// the last one (played from a Speed dial pin, Home's long press), and
  /// [fallbackArt] (the song it started with) is the cover only when none
  /// is known.
  static Future<void> markPlayed(String id,
      {DateTime? at,
      String? type,
      String? name,
      String? art,
      String? fallbackArt,
      String? by,
      bool piped = false}) async {
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
    if (type == null) return;
    final info = _info();
    final was = info[id] ?? const {};
    bool given(String? v) => v != null && v.isNotEmpty;
    info[id] = {
      ...was,
      'type': type,
      if (given(name)) 'name': name,
      if (given(art))
        'art': art
      else if (was['art'] == null && given(fallbackArt))
        'art': fallbackArt,
      if (given(by)) 'by': by,
      if (piped) 'piped': true,
    };
    // Forgotten with their time.
    info.removeWhere((k, _) => !all.containsKey(k));
    await prefs.put(infoKey, info);
  }

  /// Forgets [id] (a playlist deleted): Home's Recently played no longer
  /// shows it.
  static Future<void> forget(String id) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final all = snapshot();
    final info = _info();
    final timed = all.remove(id) != null;
    final known = info.remove(id) != null;
    if (!timed && !known) return;
    await prefs.put(key, all);
    await prefs.put(infoKey, info);
  }

  static Map<String, Map> _info() {
    final raw = _prefs?.get(infoKey);
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        if (e.key is String && e.value is Map) e.key as String: e.value as Map,
    };
  }

  /// Every collection played from, latest first, with what's known of it.
  static List<RecentCollection> recent() {
    final times = snapshot();
    final info = _info();
    final ids = times.keys.toList()
      ..sort((a, b) => times[b]!.compareTo(times[a]!));
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    return [
      for (final id in ids)
        RecentCollection(
          id: id,
          at: times[id]!,
          type: text(info[id]?['type']),
          name: text(info[id]?['name']) ?? '',
          art: text(info[id]?['art']),
          by: text(info[id]?['by']),
          piped: info[id]?['piped'] == true,
        ),
    ];
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
