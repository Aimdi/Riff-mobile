/// Recently played by day, as Spotify's listening history and YouTube
/// Music's History list it: each song in the LIBRP box keeps when it was
/// played, and the list heads each day with Today, Yesterday or the date.
library;

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

import '/models/media_Item_builder.dart';
import 'podcast_history.dart' show podcastHistoryDay;

/// Beside the song in each Recently played entry: when it was played (ms).
const recentlyPlayedAtKey = 'playedAt';

/// What Recently played keeps for [song] played at [now].
Map<String, dynamic> recentlyPlayedEntry(MediaItem song, DateTime now) =>
    MediaItemBuilder.toJson(song)
      ..[recentlyPlayedAtKey] = now.millisecondsSinceEpoch;

/// When each song in Recently played ([entries], the box's values) was
/// played, by its id; the ones kept before Riff noted it have none.
Map<String, int> recentlyPlayedTimes(Iterable<dynamic> entries) => {
      for (final e in entries)
        if (e is Map && e[recentlyPlayedAtKey] is int)
          '${e['videoId']}': e[recentlyPlayedAtKey] as int
    };

/// The heading over each song of a Recently played list, given when they
/// were played ([playedAt], newest first; null for songs from before Riff
/// noted it): the day where one begins (Today, Yesterday, then the date,
/// as the podcast history has them; Earlier over the songs without a time,
/// which come last), else null. All null when no song has a time, or the
/// list is in another order (sorted, say).
List<String?> recentlyPlayedHeadings(List<int?> playedAt, DateTime now) {
  final none = List<String?>.filled(playedAt.length, null);
  int? newer;
  var untimed = false;
  for (final t in playedAt) {
    if (t == null) {
      untimed = true;
    } else if (untimed || (newer != null && t > newer)) {
      return none;
    } else {
      newer = t;
    }
  }
  if (newer == null) return none;
  final headings = <String?>[];
  String? previous;
  for (final t in playedAt) {
    final day = t == null
        ? 'earlier'.tr
        : podcastHistoryDay(DateTime.fromMillisecondsSinceEpoch(t), now);
    headings.add(day == previous ? null : day);
    previous = day;
  }
  return headings;
}
