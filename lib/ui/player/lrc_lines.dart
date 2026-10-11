/// Timed lines of an LRC text, for the one-line lyric preview under the
/// player title.
library;

/// One sung line and when it starts.
typedef LrcLine = ({Duration at, String text});

final _stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _wordStamp = RegExp(r'<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>');

/// Parses [lrc] into lines sorted by time. A line with several stamps
/// ("[00:12.00][01:30.00] chorus") appears once per stamp; metadata tags
/// ("[ar: …]"), word-timing stamps and blank lines are dropped.
List<LrcLine> parseLrc(String lrc) {
  final lines = <LrcLine>[];
  for (final raw in lrc.split('\n')) {
    final stamps = <Duration>[];
    var rest = raw.trim();
    while (true) {
      final m = _stamp.matchAsPrefix(rest);
      if (m == null) break;
      final frac = m.group(3) ?? '0';
      // ".5" is half a second, ".05" five hundredths, ".005" milliseconds.
      final ms = (int.parse(frac) * [100, 10, 1][frac.length - 1]);
      stamps.add(Duration(
        minutes: int.parse(m.group(1)!),
        seconds: int.parse(m.group(2)!),
        milliseconds: ms,
      ));
      rest = rest.substring(m.end).trimLeft();
    }
    final text = rest.replaceAll(_wordStamp, '').trim();
    if (stamps.isEmpty || text.isEmpty) continue;
    for (final at in stamps) {
      lines.add((at: at, text: text));
    }
  }
  lines.sort((a, b) => a.at.compareTo(b.at));
  return lines;
}

/// Index of the line playing at [position], or -1 before the first line.
int lrcLineAt(List<LrcLine> lines, Duration position) {
  var lo = 0, hi = lines.length - 1, found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].at <= position) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found;
}
