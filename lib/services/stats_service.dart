import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

/// Local listening statistics (ported from Riff desktop's Stats page).
/// Every song start is recorded in Hive; listening time is approximated
/// by track duration (scrobble-style), so no playback probing is needed.
class StatsService {
  StatsService._();

  static Box get _songs => Hive.box("SongStats");
  static Box get _days => Hive.box("DailyStats");

  static String _dayKey(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  static Future<void> recordPlay(MediaItem item) async {
    final secs = item.duration?.inSeconds ?? 0;
    final now = DateTime.now();

    final prev = _songs.get(item.id);
    await _songs.put(item.id, {
      "title": item.title,
      "artist": item.artist ?? "",
      "plays": (prev?["plays"] ?? 0) + 1,
      "seconds": (prev?["seconds"] ?? 0) + secs,
      "lastPlayed": now.millisecondsSinceEpoch,
    });

    final dk = _dayKey(now);
    final day = _days.get(dk);
    await _days.put(dk, {
      "plays": (day?["plays"] ?? 0) + 1,
      "seconds": (day?["seconds"] ?? 0) + secs,
    });
  }

  static int get totalPlays => _songs.values
      .fold<int>(0, (sum, v) => sum + ((v["plays"] ?? 0) as int));

  static int get totalSeconds => _songs.values
      .fold<int>(0, (sum, v) => sum + ((v["seconds"] ?? 0) as int));

  static int get uniqueArtists {
    final set = <String>{};
    for (final v in _songs.values) {
      final a = (v["artist"] ?? "") as String;
      if (a.isNotEmpty) set.add(a);
    }
    return set.length;
  }

  /// Gamified listener level from total plays (RiPlay-style).
  /// Levels widen as they climb so early progress feels rewarding.
  static int get listenerLevel {
    final p = totalPlays;
    if (p <= 0) return 0;
    // Level n needs 10 * n^1.6 plays cumulatively.
    var level = 0;
    while (10 * ((level + 1) * (level + 1)) <= p * 2) {
      level++;
      if (level > 999) break;
    }
    return level;
  }

  /// Most recently played track as a lightweight [MediaItem], if any.
  static MediaItem? mostRecentSong() {
    if (_songs.isEmpty) return null;
    String? bestId;
    var bestTs = -1;
    Map? bestVal;
    for (final k in _songs.keys) {
      final v = _songs.get(k);
      if (v is! Map) continue;
      final ts = (v['lastPlayed'] as int?) ?? 0;
      if (ts > bestTs) {
        bestTs = ts;
        bestId = k.toString();
        bestVal = v;
      }
    }
    if (bestId == null || bestId.isEmpty || bestVal == null) return null;
    return MediaItem(
      id: bestId,
      title: '${bestVal['title'] ?? bestId}',
      artist: '${bestVal['artist'] ?? ''}',
    );
  }

  /// Top songs by play count: [{id, title, artist, plays}].
  static List<Map<String, dynamic>> topSongs([int n = 10]) {
    final list = _songs.keys
        .map((k) => {
              "id": k,
              "title": _songs.get(k)["title"] ?? "",
              "artist": _songs.get(k)["artist"] ?? "",
              "plays": _songs.get(k)["plays"] ?? 0,
            })
        .toList();
    list.sort((a, b) => (b["plays"] as int).compareTo(a["plays"] as int));
    return list.take(n).toList();
  }

  /// Top artists by play count: [{artist, plays}].
  static List<Map<String, dynamic>> topArtists([int n = 10]) {
    final byArtist = <String, int>{};
    for (final v in _songs.values) {
      final artist = (v["artist"] ?? "") as String;
      if (artist.isEmpty) continue;
      byArtist[artist] = (byArtist[artist] ?? 0) + ((v["plays"] ?? 0) as int);
    }
    final list = byArtist.entries
        .map((e) => {"artist": e.key, "plays": e.value})
        .toList();
    list.sort((a, b) => (b["plays"] as int).compareTo(a["plays"] as int));
    return list.take(n).toList();
  }

  /// Plays for each of the last [n] days (oldest first):
  /// [{day, plays, seconds}].
  static List<Map<String, dynamic>> lastDays([int n = 7]) {
    final now = DateTime.now();
    return List.generate(n, (i) {
      final d = now.subtract(Duration(days: n - 1 - i));
      final v = _days.get(_dayKey(d));
      return {
        "day": _dayKey(d),
        "plays": v?["plays"] ?? 0,
        "seconds": v?["seconds"] ?? 0,
      };
    });
  }
}
