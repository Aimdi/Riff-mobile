/// Spotify's "Allow explicit content" (Apple Music's clean-only setting,
/// YouTube Music's Restricted mode): on by default; turned off, songs
/// marked explicit (the E before their artist) don't play. The player skips
/// them, radio and suggestions leave them out, and their rows are dimmed.
library;

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_item_extras.dart';

class ExplicitContent {
  ExplicitContent._();

  /// AppPrefs key.
  static const key = 'allowExplicit';

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// For the Settings switch and the dimmed rows.
  static final allowed = RxBool(_prefs?.get(key) != false);

  static Future<void> set(bool allow) async {
    allowed.value = allow;
    await _prefs?.put(key, allow);
  }

  /// Whether [song] may not play: it's marked explicit and explicit content
  /// is off.
  static bool blocks(MediaItem? song) =>
      !allowed.value && song != null && song.isExplicit;

  /// [tracks] (songs, or raw track maps) without the ones that may not
  /// play. [keepId], the song asked for, stays where it is: the player skips
  /// it, and a radio from it still plays.
  static List<T> filter<T>(List<T> tracks, {String? keepId}) {
    if (allowed.value) return tracks;
    return [
      for (final t in tracks)
        if (!_explicit(t) || _id(t) == keepId) t
    ];
  }

  static bool _explicit(Object? t) =>
      t is MediaItem ? t.isExplicit : t is Map && t['isExplicit'] == true;

  static String? _id(Object? t) => t is MediaItem
      ? t.id
      : t is Map
          ? t['videoId']?.toString()
          : null;
}

/// Where play goes when the song at [from] may not play: [step] gives the
/// song after one in play order (Next's, or Previous's going back), or the
/// same one at the end of the queue, and [mayPlay] says which may. The
/// first that may; or no index, with [atEnd] when the queue ends first and
/// without it when none of its [length] songs may.
({int? index, bool atEnd}) playableFrom(int from, int length,
    {required int Function(int at) step,
    required bool Function(int index) mayPlay}) {
  var at = from;
  for (var n = 0; n < length; n++) {
    final next = step(at);
    if (next == at) return (index: null, atEnd: true);
    if (mayPlay(next)) return (index: next, atEnd: false);
    at = next;
  }
  return (index: null, atEnd: false);
}
