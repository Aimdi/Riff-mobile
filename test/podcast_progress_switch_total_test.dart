import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/services/podcast_progress_service.dart';

/// Regression: the outgoing podcast episode's position used to be persisted
/// against the *incoming* item's duration.
///
/// `_listenForChangesInDuration` in player_controller.dart overwrote
/// `progressBarStatus.value.total` with the new item's duration and only then
/// called `PodcastProgressService.save(..., progressBarStatus.value.total)`.
/// `ProgressBarState` is mutable and GetX's `Rx.update` mutates in place, so
/// the "old state" reference aliased the object that had just been overwritten.
/// The switch is now funnelled through [retargetProgressBar], which copies the
/// outgoing position/total out by value before touching the shared state.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('podcast_progress_switch');
    Hive.init(p.join(tmp.path, 'hive'));
    await Hive.openBox('PodcastProgress');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  MediaItem episode(String id, Duration duration) => MediaItem(
        id: id,
        title: 'Episode $id',
        artist: 'Show',
        duration: duration,
        extras: const {'url': 'https://example.com/ep.mp3', 'isPodcast': true},
      );

  /// The controller's media-item switch, reduced to the part under test.
  void switchItem(ProgressBarState bar, MediaItem? outgoing, MediaItem incoming,
      {required int nowMs}) {
    final outgoingProgress = retargetProgressBar(bar, incoming.duration);
    PodcastProgressService.save(
        outgoing, outgoingProgress.position, outgoingProgress.total,
        nowMs: nowMs);
  }

  test('retargetProgressBar snapshots the outgoing totals by value', () {
    final bar = ProgressBarState(
      current: const Duration(minutes: 30),
      buffered: const Duration(minutes: 31),
      total: const Duration(hours: 2),
    );

    final snap = retargetProgressBar(bar, const Duration(minutes: 3));

    // Snapshot describes the item we are leaving...
    expect(snap.position, const Duration(minutes: 30));
    expect(snap.total, const Duration(hours: 2));
    // ...while the shared, mutable bar now describes the incoming item.
    expect(bar.total, const Duration(minutes: 3));
  });

  test('retargetProgressBar treats a duration-less incoming item as zero', () {
    final bar = ProgressBarState(
      current: const Duration(minutes: 5),
      buffered: Duration.zero,
      total: const Duration(minutes: 40),
    );

    final snap = retargetProgressBar(bar, null);

    expect(snap.total, const Duration(minutes: 40));
    expect(bar.total, Duration.zero);
  });

  test('long episode -> short track keeps the resume point', () {
    final outgoing = episode('podcast_long', const Duration(hours: 2));
    final bar = ProgressBarState(
      current: const Duration(minutes: 30),
      buffered: const Duration(minutes: 31),
      total: const Duration(hours: 2),
    );

    // User taps a 3-minute song. With the incoming duration as denominator,
    // 30min >= 3min - 20s, so the episode was treated as finished and deleted.
    switchItem(bar, outgoing,
        episode('podcast_short_song', const Duration(minutes: 3)),
        nowMs: 1000);

    expect(PodcastProgressService.positionMs('podcast_long'),
        const Duration(minutes: 30).inMilliseconds);
    expect(PodcastProgressService.progress('podcast_long'), closeTo(0.25, 0.001));
  });

  test('short episode -> long episode stores the outgoing duration', () {
    final outgoing = episode('podcast_short', const Duration(minutes: 20));
    final bar = ProgressBarState(
      current: const Duration(minutes: 10),
      buffered: const Duration(minutes: 11),
      total: const Duration(minutes: 20),
    );

    switchItem(
        bar, outgoing, episode('podcast_big', const Duration(hours: 2)),
        nowMs: 2000);

    // Denominator must be the 20-minute episode, not the 2-hour one.
    expect(PodcastProgressService.progress('podcast_short'),
        closeTo(0.5, 0.001));
  });

  test('a nearly finished short episode is still recognised as finished', () {
    final outgoing = episode('podcast_done', const Duration(minutes: 20));
    final bar = ProgressBarState(
      current: const Duration(minutes: 19, seconds: 50),
      buffered: const Duration(minutes: 20),
      total: const Duration(minutes: 20),
    );

    switchItem(
        bar, outgoing, episode('podcast_next', const Duration(hours: 2)),
        nowMs: 3000);

    // Against the incoming 2h duration this would have been stored as ~16%
    // played instead of being dropped from the Continue row.
    expect(PodcastProgressService.positionMs('podcast_done'), isNull);
  });
}
