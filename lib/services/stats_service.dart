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
