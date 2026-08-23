import '/services/podcast_service.dart';

/// Fractions (0–1) where chapter ticks / gaps belong on a straight seek bar.
///
/// Drops the 0:00 intro mark and anything at/after the end so a single
/// chapter covering the whole episode still renders as one segment.
List<double> podcastChapterMarks(
    Iterable<PodcastChapter> chapters, double durationSec) {
  if (durationSec <= 0) return const [];
  final marks = <double>[];
  for (final c in chapters) {
    if (c.startSec > 0.25 && c.startSec < durationSec - 0.25) {
      marks.add((c.startSec / durationSec).clamp(0.0, 1.0));
    }
  }
  marks.sort();
  return marks;
}
