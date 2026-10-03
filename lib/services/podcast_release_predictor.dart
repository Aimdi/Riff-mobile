import 'package:audio_service/audio_service.dart';

import 'podcast_playback_profile.dart';

/// "Expected today": guesses from a show's recent release times whether a
/// new episode is due today, and roughly when.
class ReleasePrediction {
  const ReleasePrediction({required this.hour, required this.minute});

  /// Local time of day the episode usually lands (median of past releases,
  /// rounded to the quarter hour).
  final int hour;
  final int minute;

  /// Today at the predicted time.
  DateTime on(DateTime day) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  @override
  bool operator ==(Object other) =>
      other is ReleasePrediction && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => 'ReleasePrediction($hour:$minute)';
}

/// How many past releases are looked at, at most.
const releaseHistory = 10;

/// Fewer releases than this and there's no guess.
const releaseMinPoints = 4;

/// Share of past releases that must fall on today's weekday.
const releaseWeekdayShare = 0.6;

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Median of [values] (sorted copy); the lower middle for even counts.
int _median(List<int> values) {
  final v = List<int>.of(values)..sort();
  return v[(v.length - 1) ~/ 2];
}

/// Predict whether a show releases today, from its publish dates.
///
/// Uses the newest [releaseHistory] dates in local time. Needs at least
/// [releaseMinPoints], and either [releaseWeekdayShare] of them on today's
/// weekday or a daily cadence (most gaps about a day). A show that has gone
/// quiet (nothing for over two weeks, or three days for a daily one) gets
/// no guess. The time is the median time of day of the matching releases.
/// Null when there's no pattern, or when today's episode is already out.
ReleasePrediction? predictToday(List<DateTime> pubDates, DateTime now) {
  final local = [for (final d in pubDates) d.toLocal()]
    ..sort((a, b) => b.compareTo(a));
  final today = now.toLocal();
  if (local.any((d) => _sameDay(d, today))) return null;
  final recent = local.where((d) => !d.isAfter(today)).take(releaseHistory).toList();
  if (recent.length < releaseMinPoints) return null;

  final sameWeekday = [for (final d in recent) if (d.weekday == today.weekday) d];
  final sinceLast = today.difference(recent.first);
  List<DateTime>? basis;
  if (sameWeekday.length / recent.length >= releaseWeekdayShare &&
      sinceLast <= const Duration(days: 15)) {
    basis = sameWeekday;
  } else if (_isDaily(recent) &&
      sinceLast <= const Duration(days: 3) &&
      // A weekdays-only show isn't due on a Saturday.
      sameWeekday.isNotEmpty) {
    basis = recent;
  }
  if (basis == null) return null;

  final minutes = _median([for (final d in basis) d.hour * 60 + d.minute]);
  // Quarter-hour precision is all a guess like this deserves.
  final rounded = ((minutes / 15).round() * 15).clamp(0, 23 * 60 + 45);
  return ReleasePrediction(hour: rounded ~/ 60, minute: rounded % 60);
}

/// Daily cadence: at least 3 of every 4 gaps between releases (newest
/// first) are about a day (18–30 h).
bool _isDaily(List<DateTime> newestFirst) {
  var daily = 0;
  for (var i = 0; i + 1 < newestFirst.length; i++) {
    final gapH = newestFirst[i].difference(newestFirst[i + 1]).inMinutes / 60;
    if (gapH >= 18 && gapH <= 30) daily++;
  }
  final gaps = newestFirst.length - 1;
  return gaps > 0 && daily / gaps >= 0.75;
}

/// A followed show expected to release today.
class ExpectedShow {
  const ExpectedShow(
      {required this.showKey,
      required this.title,
      required this.prediction,
      this.artUri});
  final String showKey;
  final String title;
  final ReleasePrediction prediction;
  final String? artUri;
}

/// Shows in a merged Inbox (every followed show's recent episodes) that
/// are due today, earliest first. Episodes without a publish time (most
/// YouTube shelves) can't be used, so those shows never appear.
List<ExpectedShow> expectedShows(List<MediaItem> merged, DateTime now) {
  final byShow = <String, List<MediaItem>>{};
  for (final e in merged) {
    final key = podcastShowKey(e) ?? 'artist:${e.artist ?? ''}';
    (byShow[key] ??= []).add(e);
  }
  final out = <ExpectedShow>[];
  byShow.forEach((key, eps) {
    final dates = [
      for (final e in eps)
        if (e.extras?['pubDateMs'] case final int ms when ms > 0)
          DateTime.fromMillisecondsSinceEpoch(ms)
    ];
    final p = predictToday(dates, now);
    if (p == null) return;
    final first = eps.first;
    out.add(ExpectedShow(
      showKey: key,
      title: first.artist ?? '',
      prediction: p,
      artUri: first.artUri?.toString(),
    ));
  });
  out.sort((a, b) => (a.prediction.hour * 60 + a.prediction.minute)
      .compareTo(b.prediction.hour * 60 + b.prediction.minute));
  return out;
}
