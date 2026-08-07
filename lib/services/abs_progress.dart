// Pure helpers for Audiobookshelf resume / progress math (no Flutter/Get deps).

/// Map ABS book-absolute [currentTimeSec] onto a track index + in-track offset.
(int trackIndex, Duration offset) mapAbsCurrentTimeToTrack(
  double currentTimeSec,
  List<double> trackDurationsSec,
) {
  if (trackDurationsSec.isEmpty) return (0, Duration.zero);
  var remaining = currentTimeSec < 0 ? 0.0 : currentTimeSec;
  for (var i = 0; i < trackDurationsSec.length; i++) {
    final d = trackDurationsSec[i] <= 0 ? 0.0 : trackDurationsSec[i];
    final isLast = i == trackDurationsSec.length - 1;
    if (remaining < d || isLast) {
      final maxMs = (d * 1000).round();
      final ms = (remaining * 1000).round().clamp(0, maxMs > 0 ? maxMs : 0);
      return (i, Duration(milliseconds: ms));
    }
    remaining -= d;
  }
  return (trackDurationsSec.length - 1, Duration.zero);
}

/// Best-effort 0..1 progress from ABS item / media / userMediaProgress shapes.
double? parseAbsProgress(Map r) {
  final ump = r['userMediaProgress'];
  if (ump is Map) {
    final p = (ump['progress'] as num?)?.toDouble();
    if (p != null) return p.clamp(0.0, 1.0);
  }
  final media = r['media'];
  if (media is Map) {
    final pct = media['progressPercentage'] as num?;
    if (pct != null) {
      final v = pct.toDouble();
      return (v > 1.0 ? v / 100.0 : v).clamp(0.0, 1.0);
    }
    final mp = media['progress'];
    if (mp is num) return mp.toDouble().clamp(0.0, 1.0);
    if (mp is Map) {
      final p = (mp['progress'] as num?)?.toDouble();
      if (p != null) return p.clamp(0.0, 1.0);
    }
  }
  final top = r['progress'];
  if (top is num) return top.toDouble().clamp(0.0, 1.0);
  if (top is Map) {
    final p = (top['progress'] as num?)?.toDouble();
    if (p != null) return p.clamp(0.0, 1.0);
  }
  return null;
}
