/// Chapters from an episode's show notes, as YouTube and Spotify make
/// chapters of a description that lists its parts by their start:
///
///     00:00 Intro
///     (04:12) The interview
///     1:02:03 - Wrap-up
///
/// for episodes whose feed and file carry no chapters of their own, so
/// the chapter list, the previous / next chapter buttons and chapter
/// skipping work for them too.
library;

import 'podcast_service.dart' show PodcastChapter;
import 'show_notes_links.dart' show showNotesWithoutAddresses;

/// A timestamp: "1:02:03", "12:34" or "2:05".
const _stamp = r'(?:(\d{1,2}):)?(\d{1,2}):(\d{2})';

/// A line opening with its timestamp (after a bullet, maybe in brackets),
/// its title after it.
final _opening = RegExp(
    '^[\\s\\-–—•*·>]*[\\[(]?\\s*$_stamp\\s*[\\])]?\\s*[-–—:|.•]*\\s*(.*)\$');

/// A line ending with its timestamp, its title before it.
final _closing =
    RegExp('^(.*?)[\\s\\-–—:|•]*[\\[(]?\\s*$_stamp\\s*[\\])]?\\s*\$');

/// What's left around a title: bullets, dashes, colons, brackets.
final _edges = RegExp(r'^[\s\-–—•*·:|>]+|[\s\-–—•*·:|]+$');

/// The fewest timestamps that make a list of chapters, as YouTube asks.
const minChapters = 3;

/// The shortest chapter, as YouTube asks: closer timestamps aren't a list
/// of the episode's parts.
const minChapterSec = 10;

int? _seconds(String? h, String m, String s) {
  final hours = h == null ? 0 : int.parse(h);
  final minutes = int.parse(m);
  final secs = int.parse(s);
  if (secs > 59 || (h != null && minutes > 59)) return null;
  return hours * 3600 + minutes * 60 + secs;
}

/// The chapters [notes] lists: lines that open (or, in notes where none
/// does, end) with a timestamp and say what starts there, at least
/// [minChapters] of them, in order and [minChapterSec] apart, within
/// [length] when it's known. None when the notes don't list the episode's
/// parts so (timestamps in the text, out of order, or past its end).
List<PodcastChapter> showNotesChapters(String notes, {Duration? length}) {
  final maxSec =
      length == null || length <= Duration.zero ? null : length.inSeconds;
  final opening = <(int, String)>[];
  final closing = <(int, String)>[];
  void add(
      List<(int, String)> to, String? h, String? m, String? s, String? title) {
    if (m == null || s == null) return;
    final sec = _seconds(h, m, s);
    final name = (title ?? '').replaceAll(_edges, '').trim();
    if (sec != null && name.isNotEmpty) to.add((sec, name));
  }

  for (final raw in showNotesWithoutAddresses(notes).split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.length > 200) continue;
    final open = _opening.firstMatch(line);
    if (open != null) {
      add(opening, open.group(1), open.group(2), open.group(3), open.group(4));
      continue;
    }
    final close = _closing.firstMatch(line);
    if (close != null) {
      add(closing, close.group(2), close.group(3), close.group(4),
          close.group(1));
    }
  }
  final found = opening.length >= minChapters ? opening : closing;
  if (found.length < minChapters) return const [];
  for (var i = 0; i < found.length; i++) {
    final sec = found[i].$1;
    if (maxSec != null && sec >= maxSec) return const [];
    if (i > 0 && sec - found[i - 1].$1 < minChapterSec) return const [];
  }
  return [
    for (final (sec, name) in found)
      PodcastChapter(startSec: sec.toDouble(), title: name, fromNotes: true),
  ];
}
