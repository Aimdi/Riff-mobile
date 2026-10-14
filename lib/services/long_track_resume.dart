/// Long tracks pick up where you left off, as YouTube does for long
/// videos: a mix, a DJ set or a full-album video ([LongTrackResume.minLength]
/// or longer) keeps its place, and plays on from there the next time it
/// starts. Podcasts and audiobooks keep theirs their own way.
library;

import 'package:hive/hive.dart';

class LongTrackResume {
  LongTrackResume._();

  /// AppPrefs: { id: {ms, at} } for the tracks with a place kept.
  static const key = 'longTrackPositions';

  /// Tracks this long or longer keep their place.
  static const minLength = Duration(minutes: 20);

  /// A place this near the start isn't kept; this near the end, the track
  /// starts over.
  static const minPlace = Duration(minutes: 1);
  static const endMargin = Duration(minutes: 2);

  /// The most places kept (the oldest go).
  static const max = 50;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static Map<String, Map> get _places {
    final raw = _prefs?.get(key);
    return raw is Map
        ? {
            for (final e in raw.entries)
              if (e.value is Map) '${e.key}': e.value as Map,
          }
        : {};
  }

  /// Whether a track [length] long keeps its place.
  static bool keepsPlace(Duration? length) =>
      length != null && length >= minLength;

  /// Where the track [id], [length] long (null or zero: not known yet),
  /// plays on from: its kept place, or zero (none kept, or one too near
  /// the start or the end).
  static Duration placeOf(String id, Duration? length) {
    final known = length != null && length > Duration.zero;
    if (known && !keepsPlace(length)) return Duration.zero;
    final ms = _places[id]?['ms'];
    if (ms is! int) return Duration.zero;
    final place = Duration(milliseconds: ms);
    if (place < minPlace || (known && place > length - endMargin)) {
      return Duration.zero;
    }
    return place;
  }

  /// The track [id], [length] long, is at [position]: kept (near its end,
  /// forgotten, so it starts over). [nowMs] orders the places kept.
  static Future<void> save(String id, Duration position, Duration? length,
      {required int nowMs}) async {
    final prefs = _prefs;
    if (prefs == null || !keepsPlace(length)) return;
    final places = _places;
    final done = position > length! - endMargin;
    if (done || position < minPlace) {
      if (places.remove(id) == null) return;
    } else {
      places[id] = {'ms': position.inMilliseconds, 'at': nowMs};
    }
    int at(MapEntry<String, Map> e) {
      final at = e.value['at'];
      return at is int ? at : 0;
    }

    final kept = places.entries.toList()
      ..sort((a, b) => at(b).compareTo(at(a)));
    await prefs.put(key, {
      for (final e in kept.take(max)) e.key: e.value,
    });
  }

  /// Forgets the place kept for [id] (Start over).
  static Future<void> forget(String id) async {
    final places = _places;
    if (places.remove(id) == null) return;
    await _prefs?.put(key, places);
  }
}

/// "23:45" for a place [d] into a track ("1:02:03" past an hour).
String longTrackPlaceLabel(Duration d) {
  final m = d.inMinutes % 60;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${m.toString().padLeft(2, '0')}:$s'
      : '$m:$s';
}
