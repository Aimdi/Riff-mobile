/// Show notes with their timestamps and links picked out, so "12:34" plays
/// the episode from there and a web address opens, as in Pocket Casts,
/// Spotify and YouTube.
library;

/// A piece of the notes: text, a moment of the episode, or a link.
class ShowNotesPart {
  const ShowNotesPart.text(this.text)
      : seconds = null,
        url = null;
  const ShowNotesPart.time(this.text, int this.seconds) : url = null;
  const ShowNotesPart.link(this.text, String this.url) : seconds = null;

  final String text;

  /// Where a timestamp points, in seconds.
  final int? seconds;
  final String? url;

  @override
  bool operator ==(Object other) =>
      other is ShowNotesPart &&
      other.text == text &&
      other.seconds == seconds &&
      other.url == url;

  @override
  int get hashCode => Object.hash(text, seconds, url);

  @override
  String toString() => seconds != null
      ? 'time($text=$seconds)'
      : url != null
          ? 'link($text)'
          : 'text($text)';
}

/// "1:02:03", "12:34" or "2:05", not part of a longer number or time.
final _time = RegExp(r'(?<![\d:.])(?:(\d{1,2}):)?(\d{1,2}):(\d{2})(?![\d:])');
final _link = RegExp(r'''https?://[^\s<>"')\]]+''');

/// A link the feed gave words to, as PodcastService.showNotesText keeps it:
/// "[words](https://…)".
final _namedLink = RegExp(r'\[([^\[\]\n]+)\]\((https?://[^\s()]+)\)');

/// [notes] with each "[words](address)" link down to its words, for
/// previews and search.
String showNotesWithoutAddresses(String notes) =>
    notes.replaceAllMapped(_namedLink, (m) => m.group(1)!);

/// Seconds for a timestamp's parts, or null when it isn't a valid one.
int? _seconds(String? h, String m, String s) {
  final hours = h == null ? 0 : int.parse(h);
  final minutes = int.parse(m);
  final secs = int.parse(s);
  if (secs > 59 || (h != null && minutes > 59)) return null;
  return hours * 3600 + minutes * 60 + secs;
}

/// [notes] split into text, timestamps and links. Timestamps past [length]
/// (when it's known) stay text: a clock time, not a moment of this episode.
List<ShowNotesPart> showNotesParts(String notes, {Duration? length}) {
  final maxSec =
      length == null || length <= Duration.zero ? null : length.inSeconds;
  final found = <(int, int, ShowNotesPart)>[];
  bool taken(int start, int end) =>
      found.any((f) => start < f.$2 && end > f.$1);
  // Links with words show the words.
  for (final m in _namedLink.allMatches(notes)) {
    found.add((m.start, m.end, ShowNotesPart.link(m.group(1)!, m.group(2)!)));
  }
  for (final m in _link.allMatches(notes)) {
    if (taken(m.start, m.end)) continue;
    // A sentence's full stop or comma isn't part of the address.
    var url = m.group(0)!;
    while (url.isNotEmpty && '.,;:!?'.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    found.add((m.start, m.start + url.length, ShowNotesPart.link(url, url)));
  }
  for (final m in _time.allMatches(notes)) {
    if (taken(m.start, m.end)) continue;
    final sec = _seconds(m.group(1), m.group(2)!, m.group(3)!);
    if (sec == null || (maxSec != null && sec > maxSec)) continue;
    found.add((m.start, m.end, ShowNotesPart.time(m.group(0)!, sec)));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  final parts = <ShowNotesPart>[];
  var at = 0;
  for (final (start, end, part) in found) {
    if (start > at) parts.add(ShowNotesPart.text(notes.substring(at, start)));
    parts.add(part);
    at = end;
  }
  if (at < notes.length) parts.add(ShowNotesPart.text(notes.substring(at)));
  return parts;
}
