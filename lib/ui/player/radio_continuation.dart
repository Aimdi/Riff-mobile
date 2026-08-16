/// Radio fetches the next batch when the current track is last, or when
/// at most 3 songs remain after it. [inFlight] blocks a second request.
bool radioShouldFetchContinuation({
  required bool radioOn,
  required bool inFlight,
  required int queueLength,
  required int currentIndex,
  required bool isLastTrack,
}) {
  if (!radioOn || inFlight || queueLength <= 0) return false;
  if (isLastTrack) return true;
  if (currentIndex < 0) return false;
  final remaining = queueLength - currentIndex - 1;
  return remaining <= 3;
}

/// Last track ended and radio is on — fetch the next batch instead of pausing.
bool radioShouldExtendInsteadOfPause({
  required bool radioOn,
  required bool hasNext,
}) =>
    radioOn && !hasNext;

/// Next stays enabled on the last track when shuffle, queue-loop, or radio
/// can still advance.
bool canSkipNext({
  required bool queueEmpty,
  required bool isLast,
  required bool shuffleOn,
  required bool queueLoopOn,
  required bool radioOn,
}) {
  if (queueEmpty) return false;
  if (shuffleOn || queueLoopOn || radioOn) return true;
  return !isLast;
}

/// Previous is always available while something is queued — first-track
/// press restarts via the 3s rule.
bool canSkipPrevious({required bool hasQueue}) => hasQueue;
