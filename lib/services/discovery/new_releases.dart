/// Release Radar, as Spotify's: what the artists you follow put out
/// lately. Their pages list releases newest first, with only the year
/// each came out, so lately is this year (and early in a year, last
/// year's too).
library;

import '/models/album.dart';

/// The year [release] came out: its year, else the one in its subtitle
/// ("EP • 2026"); null when it gives none.
int? releaseYear(Album release) {
  final year = int.tryParse(release.year?.trim() ?? '');
  if (year != null && year > 1900) return year;
  final found =
      RegExp(r'\b(?:19|20)\d{2}\b').firstMatch(release.description ?? '');
  return found == null ? null : int.parse(found.group(0)!);
}

/// The earliest year a release counts as new in, [now]: this year, and
/// until May last year's too.
int newReleaseYear(DateTime now) =>
    now.subtract(const Duration(days: 120)).year;

/// An artist's newest releases out in [sinceYear] or later, from their
/// page ([artist], as MusicServices.getArtist gives it): the newest single
/// or EP, then the newest album.
List<Album> newReleasesOn(Map<String, dynamic> artist,
    {required int sinceYear}) {
  Album? newest(List<String> keys) {
    for (final key in keys) {
      final shelf = artist[key];
      final content = shelf is Map ? shelf['content'] : null;
      if (content is! List) continue;
      for (final release in content.whereType<Album>()) {
        final year = releaseYear(release);
        if (release.browseId.isNotEmpty && year != null && year >= sinceYear) {
          return release;
        }
      }
    }
    return null;
  }

  return [
    newest(const ['Singles & EPs', 'Singles']),
    newest(const ['Albums']),
  ].whereType<Album>().toList();
}

/// [lists] taken in turns, the first of each, then the second of each…,
/// so that no one list fills the start.
List<T> takeInTurns<T>(List<List<T>> lists) {
  final out = <T>[];
  for (var i = 0;; i++) {
    var more = false;
    for (final list in lists) {
      if (i < list.length) {
        out.add(list[i]);
        more = true;
      }
    }
    if (!more) return out;
  }
}

/// Of [ids] (the artists you follow), the [max] to look at this
/// [week] (weeks since the epoch): all of them when they're no more, else
/// the next [max] round the list each week.
List<String> artistsThisWeek(List<String> ids, int week, {int max = 30}) {
  if (ids.length <= max) return ids;
  final start = (week * max) % ids.length;
  return [for (var i = 0; i < max; i++) ids[(start + i) % ids.length]];
}
