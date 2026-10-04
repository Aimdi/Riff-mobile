import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '../models/media_item_extras.dart';
import 'discovery/discovery_math.dart';
import 'discovery/discovery_tag.dart';
import 'discovery/discovery_types.dart';

/// Local listening statistics.
///
/// Play *starts* increment [plays]. Seconds, skips, and partials are written
/// on play *end* from the real listen fraction — not the full track duration.
class StatsService {
  StatsService._();

  static Box get _songs => Hive.box("SongStats");
  static Box get _days => Hive.box("DailyStats");

  static String _dayKey(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  static bool get _ready =>
      Hive.isBoxOpen("SongStats") && Hive.isBoxOpen("DailyStats");

  /// Count a play start. Does not credit duration — that happens in
  /// [recordListenEnd] once we know how much was actually heard.
  static Future<void> recordPlay(MediaItem item) async {
    if (!_ready) return;
    final now = DateTime.now();
    final source = sourceFromMediaItem(item).wireName;
    final prev = _asMap(_songs.get(item.id));

    await _songs.put(item.id, {
      ...prev,
      "title": item.title,
      "artist": item.artist ?? prev["artist"] ?? "",
      "plays": (prev["plays"] as int? ?? 0) + 1,
      "lastPlayed": now.millisecondsSinceEpoch,
      "lastSource": source,
      if (item.isPodcastEpisode)
        "kind": "podcast"
      else if (item.isAudiobook)
        "kind": "audiobook",
    });

    final dk = _dayKey(now);
    final day = _asMap(_days.get(dk));
    await _days.put(dk, {
      ...day,
      "plays": (day["plays"] as int? ?? 0) + 1,
    });
  }

  /// Persist listen fraction / skip after the track ends or is skipped.
  static Future<void> recordListenEnd(
    MediaItem item, {
    required int listenedMs,
    required int totalMs,
    DiscoverySource? source,
  }) async {
    if (!_ready) return;
    final now = DateTime.now();
    final src = source ?? sourceFromMediaItem(item);
    final prev = _asMap(_songs.get(item.id));
    final next = applyListenEnd(
      prev,
      listenedMs: listenedMs,
      totalMs: totalMs,
      source: src,
      title: item.title,
      artist: item.artist ?? '',
      nowMs: now.millisecondsSinceEpoch,
    );
    await _songs.put(item.id, next);

    final dk = _dayKey(now);
    final day = _asMap(_days.get(dk));
    final addedSecs = (listenedMs / 1000).round().clamp(0, 24 * 3600);
    final skipped = next["skips"] != prev["skips"];
    await _days.put(dk, {
      ...day,
      "seconds": (day["seconds"] as int? ?? 0) + addedSecs,
      "skips": (day["skips"] as int? ?? 0) + (skipped ? 1 : 0),
    });
  }

  static int get totalPlays =>
      _songs.values.fold<int>(0, (sum, v) => sum + _intOf(_asMap(v)["plays"]));

  static int get totalSeconds => _songs.values
      .fold<int>(0, (sum, v) => sum + _intOf(_asMap(v)["seconds"]));

  static int get totalSkips =>
      _songs.values.fold<int>(0, (sum, v) => sum + _intOf(_asMap(v)["skips"]));

  static int get uniqueArtists {
    final set = <String>{};
    for (final v in _songs.values) {
      final a = (_asMap(v)["artist"] ?? "") as String;
      if (a.isNotEmpty) set.add(a);
    }
    return set.length;
  }

  /// Gamified listener level from total plays (RiPlay-style).
  /// Levels widen as they climb so early progress feels rewarding.
  static int get listenerLevel {
    final p = totalPlays;
    if (p <= 0) return 0;
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

  /// Top songs by play count: [{id, title, artist, plays, skips, lastSource}].
  static List<Map<String, dynamic>> topSongs([int n = 10]) {
    final list = _songs.keys.map((k) {
      final v = _asMap(_songs.get(k));
      return {
        "id": k,
        "title": v["title"] ?? "",
        "artist": v["artist"] ?? "",
        "plays": _intOf(v["plays"]),
        "skips": _intOf(v["skips"]),
        "lastSource": v["lastSource"] ?? "",
      };
    }).toList();
    list.sort((a, b) => (b["plays"] as int).compareTo(a["plays"] as int));
    return list.take(n).toList();
  }

  /// Top artists by play count: [{artist, plays}]. Music only: podcast
  /// episodes and audiobook chapters are left out (see [rankTopArtists]).
  static List<Map<String, dynamic>> topArtists([int n = 10]) =>
      rankTopArtists(_songs.toMap(), n);

  /// Plays for each of the last [n] days (oldest first):
  /// [{day, plays, seconds, skips}].
  static List<Map<String, dynamic>> lastDays([int n = 7]) {
    final now = DateTime.now();
    return List.generate(n, (i) {
      final d = now.subtract(Duration(days: n - 1 - i));
      final v = _asMap(_days.get(_dayKey(d)));
      return {
        "day": _dayKey(d),
        "plays": _intOf(v["plays"]),
        "seconds": _intOf(v["seconds"]),
        "skips": _intOf(v["skips"]),
      };
    });
  }
}

Map<String, dynamic> _asMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return <String, dynamic>{};
}

int _intOf(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return 0;
}

/// Artist names the feed gives non-music items ("Podcast" for a YouTube
/// episode without a show name).
const _nonMusicArtists = {'podcast', 'podcasts', 'episode', 'audiobook'};

/// True for a SongStats row that isn't a song: a podcast episode or an
/// audiobook chapter, by the kind stored since 1.7.133, the id prefix, the
/// source it was played from, or a placeholder artist.
bool isNonMusicStat(String id, Map<String, dynamic> row) {
  final kind = '${row['kind'] ?? ''}';
  if (kind == 'podcast' || kind == 'audiobook') return true;
  if (id.startsWith('podcast_') ||
      id.startsWith('abs_') ||
      id.startsWith('lv_')) {
    return true;
  }
  final source = '${row['lastSource'] ?? ''}';
  if (source == DiscoverySource.podcast.wireName ||
      source == DiscoverySource.audiobook.wireName) {
    return true;
  }
  final artist = '${row['artist'] ?? ''}'.trim().toLowerCase();
  return _nonMusicArtists.contains(artist);
}

/// Top [n] artists by plays over SongStats rows keyed by item id, music
/// only. Pure for tests.
List<Map<String, dynamic>> rankTopArtists(Map<dynamic, dynamic> rows,
    [int n = 10]) {
  final byArtist = <String, int>{};
  rows.forEach((id, raw) {
    final row = _asMap(raw);
    final artist = '${row["artist"] ?? ""}'.trim();
    if (artist.isEmpty || isNonMusicStat('$id', row)) return;
    byArtist[artist] = (byArtist[artist] ?? 0) + _intOf(row["plays"]);
  });
  final list =
      byArtist.entries.map((e) => {"artist": e.key, "plays": e.value}).toList();
  list.sort((a, b) => (b["plays"] as int).compareTo(a["plays"] as int));
  return list.take(n).toList();
}

/// Pure listen-end merge used by [StatsService.recordListenEnd] and tests.
///
/// Skip: heard under 30% (or under 10s when duration is unknown).
/// Partial: 30-85%. Complete: 85% or more.
Map<String, dynamic> applyListenEnd(
  Map<String, dynamic> prev, {
  required int listenedMs,
  required int totalMs,
  required DiscoverySource source,
  String? title,
  String? artist,
  int? nowMs,
}) {
  final double? fraction =
      totalMs > 0 ? (listenedMs / totalMs).clamp(0.0, 1.0) : null;
  final isQuickSkip = listenedMs < 10000 && (fraction ?? 0.0) < 0.30;
  final addedSecs = (listenedMs / 1000).round().clamp(0, 24 * 3600);

  var skips = _intOf(prev["skips"]);
  var partials = _intOf(prev["partials"]);
  var completes = _intOf(prev["completes"]);

  if (isQuickSkip || (fraction != null && fraction < 0.30)) {
    skips += 1;
  } else if (fraction != null) {
    switch (classifyListen(fraction)) {
      case ListenQuality.weakPositive:
        partials += 1;
        break;
      case ListenQuality.strongPositive:
        completes += 1;
        break;
      case ListenQuality.negative:
        skips += 1;
        break;
    }
  }

  return {
    ...prev,
    if (title != null) "title": title,
    if (artist != null) "artist": artist,
    "seconds": _intOf(prev["seconds"]) + addedSecs,
    "skips": skips,
    "partials": partials,
    "completes": completes,
    "lastFraction": fraction,
    "lastSource": source.wireName,
    if (nowMs != null) "lastPlayed": nowMs,
  };
}
