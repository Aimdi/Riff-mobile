import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'podcast_playback_profile.dart';

/// One progress tick's worth of listening: wall-clock time that passed and
/// how far the episode moved. Faster playback moves the episode further
/// than the clock; the difference is time saved by speed.
typedef ListenDelta = ({int wallMs, int contentMs});

/// What a tick adds, or null when it shouldn't count: paused, the first
/// tick, a seek (the position jumped further than any speed explains), or
/// a long gap (the app slept).
ListenDelta? listenDelta({
  required int? prevPosMs,
  required int posMs,
  required int? prevWallMs,
  required int wallMs,
  required bool playing,
  double maxSpeed = 3.5,
}) {
  if (!playing || prevPosMs == null || prevWallMs == null) return null;
  final wall = wallMs - prevWallMs;
  final content = posMs - prevPosMs;
  if (wall <= 0 || wall > 3000) return null;
  if (content <= 0 || content > wall * maxSpeed + 250) return null;
  return (wallMs: wall, contentMs: content);
}

/// `yyyy-mm-dd` for a local day.
String statsDayKey(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

/// Days in a row with listening, counting back from today (or from
/// yesterday, so a streak isn't lost before today's listen).
int listeningStreak(Set<String> days, DateTime today) {
  var day = DateTime(today.year, today.month, today.day);
  if (!days.contains(statsDayKey(day))) {
    day = day.subtract(const Duration(days: 1));
  }
  var n = 0;
  while (days.contains(statsDayKey(day))) {
    n++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return n;
}

/// A show's listening total, for the top shows list.
class ShowListening {
  const ShowListening(this.key, this.title, this.ms, {this.artUri});
  final String key;
  final String title;
  final int ms;
  final String? artUri;
}

/// Most listened shows first; [limit] of them.
List<ShowListening> topShows(Iterable<ShowListening> all, {int limit = 5}) =>
    (all.where((s) => s.ms > 0).toList()..sort((a, b) => b.ms.compareTo(a.ms)))
        .take(limit)
        .toList();

/// "12 h 5 min", "42 min", "under a minute" style numbers for the stats
/// page; the words come from l10n.
({int hours, int minutes}) splitDuration(Duration d) =>
    (hours: d.inHours, minutes: d.inMinutes.remainder(60));

/// Podcast listening totals, in box `PodcastStats` (shared with the segment
/// "time saved" counter). Music never reaches this.
class PodcastStatsService {
  PodcastStatsService._();

  static const box = 'PodcastStats';
  static const _wallKey = 'listenWallMs';
  static const _contentKey = 'listenContentMs';
  static const _daysKey = 'listenDays';
  static const _showsKey = 'listenShows';

  /// Bumped after each save, for Obx.
  static final rev = 0.obs;

  static Box? get _box => Hive.isBoxOpen(box) ? Hive.box(box) : null;

  static int? _prevPos;
  static int? _prevWall;
  static String? _prevId;

  // Unsaved since the last flush.
  static int _pendWall = 0;
  static int _pendContent = 0;
  static final Map<String, int> _pendDays = {};
  static final Map<String, ({String title, String? art, int ms})> _pendShows =
      {};
  static int _lastFlush = 0;

  /// One progress tick of a podcast episode.
  static void tick(MediaItem item, Duration position,
      {required bool playing, DateTime? now}) {
    final t = now ?? DateTime.now();
    final wall = t.millisecondsSinceEpoch;
    // Paused: save what's pending so nothing is lost if the app is closed.
    if (!playing && _pendWall > 0) flush(now: t);
    if (_prevId != item.id) {
      _prevId = item.id;
      _prevPos = null;
      _prevWall = null;
    }
    final d = listenDelta(
      prevPosMs: _prevPos,
      posMs: position.inMilliseconds,
      prevWallMs: _prevWall,
      wallMs: wall,
      playing: playing,
    );
    _prevPos = position.inMilliseconds;
    _prevWall = wall;
    if (d == null) return;
    _pendWall += d.wallMs;
    _pendContent += d.contentMs;
    final day = statsDayKey(t);
    _pendDays[day] = (_pendDays[day] ?? 0) + d.wallMs;
    final show = podcastShowKey(item) ?? 'show:${item.artist ?? ''}';
    final prev = _pendShows[show];
    _pendShows[show] = (
      title: item.artist ?? '',
      art: item.artUri?.toString(),
      ms: (prev?.ms ?? 0) + d.wallMs,
    );
    if (wall - _lastFlush >= 30000) flush(now: t);
  }

  /// Write pending totals (also on pause, so nothing is lost).
  static void flush({DateTime? now}) {
    _lastFlush = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final b = _box;
    if (b == null || (_pendWall == 0 && _pendContent == 0)) return;
    b.put(_wallKey, _int(b.get(_wallKey)) + _pendWall);
    b.put(_contentKey, _int(b.get(_contentKey)) + _pendContent);
    final days = _map(b.get(_daysKey));
    _pendDays.forEach((k, v) => days[k] = _int(days[k]) + v);
    b.put(_daysKey, days);
    final shows = _map(b.get(_showsKey));
    _pendShows.forEach((k, v) {
      final old = shows[k] is Map ? shows[k] as Map : const {};
      shows[k] = {
        'title': v.title.isNotEmpty ? v.title : (old['title'] ?? ''),
        'art': v.art ?? old['art'],
        'ms': _int(old['ms']) + v.ms,
      };
    });
    b.put(_showsKey, shows);
    _pendWall = 0;
    _pendContent = 0;
    _pendDays.clear();
    _pendShows.clear();
    rev.value++;
  }

  static int _int(dynamic v) => v is int ? v : 0;
  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static Duration get listened =>
      Duration(milliseconds: _int(_box?.get(_wallKey)) + _pendWall);

  /// Time saved by listening faster than 1×.
  static Duration get savedBySpeed {
    final content = _int(_box?.get(_contentKey)) + _pendContent;
    final wall = _int(_box?.get(_wallKey)) + _pendWall;
    return Duration(milliseconds: content > wall ? content - wall : 0);
  }

  static Set<String> get days => {
        ..._map(_box?.get(_daysKey)).keys,
        ..._pendDays.keys,
      };

  static int streak({DateTime? today}) =>
      listeningStreak(days, today ?? DateTime.now());

  static List<ShowListening> top({int limit = 5}) {
    final shows = _map(_box?.get(_showsKey));
    return topShows([
      for (final e in shows.entries)
        if (e.value is Map)
          ShowListening(e.key, '${(e.value as Map)['title'] ?? ''}',
              _int((e.value as Map)['ms']),
              artUri: (e.value as Map)['art'] as String?)
    ], limit: limit);
  }

  /// Test hook.
  static void resetSession() {
    _prevPos = null;
    _prevWall = null;
    _prevId = null;
    _pendWall = 0;
    _pendContent = 0;
    _pendDays.clear();
    _pendShows.clear();
    _lastFlush = 0;
  }
}
