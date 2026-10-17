/// Index math for undoing Up Next edits (remove a song, clear the queue).
library;

/// Where a song removed from queue position [index] (and [shuffleIndex] in
/// the shuffle order, -1 when shuffle was off) goes back, given the queue
/// as it is now, and where the playing song's cursors end up. Positions
/// are clamped, since the queue may have changed since the removal.
({
  int index,
  int currentIndex,
  int shuffleIndex,
  int currentShuffleIndex,
}) restoreQueuePositions({
  required int queueLength,
  required int currentIndex,
  required int index,
  required int shuffleLength,
  required int currentShuffleIndex,
  required int shuffleIndex,
}) {
  final at = index.clamp(0, queueLength);
  // Going back in before the playing song pushes it one place on.
  final current =
      queueLength > 0 && at <= currentIndex ? currentIndex + 1 : currentIndex;
  final shuffleAt =
      shuffleIndex < 0 ? shuffleLength : shuffleIndex.clamp(0, shuffleLength);
  final currentShuffle = shuffleLength > 0 && shuffleAt <= currentShuffleIndex
      ? currentShuffleIndex + 1
      : currentShuffleIndex;
  return (
    index: at,
    currentIndex: current,
    shuffleIndex: shuffleAt,
    currentShuffleIndex: currentShuffle,
  );
}

/// The queue to restore after an undone "clear": the [snapshot] taken
/// before clearing, plus anything queued since that it doesn't hold.
List<T> mergeRestoredQueue<T>(
    List<T> snapshot, List<T> now, String Function(T) idOf) {
  final ids = {for (final s in snapshot) idOf(s)};
  return [...snapshot, ...now.where((n) => !ids.contains(idOf(n)))];
}
