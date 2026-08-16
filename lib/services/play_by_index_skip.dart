/// Spotify-like previous: restart the current track after this many ms.
const int skipToPreviousRestartMs = 3000;

/// Restart now-playing when we've passed [thresholdMs]; otherwise go previous.
bool shouldRestartOnPrevious(
  Duration position, {
  int thresholdMs = skipToPreviousRestartMs,
}) =>
    position.inMilliseconds > thresholdMs;

/// After playByIndex's generateNewUrl retry still fails, skip once when the
/// next index is a different track and loop-one is off. Gated by a consecutive
/// fail count so a chain of dead URLs cannot recurse forever.
bool shouldSkipAfterUnresolvableTrack({
  required int consecutiveFails,
  required int maxConsecutiveFails,
  required int currentIndex,
  required int nextIndex,
  required bool loopOne,
}) {
  if (loopOne) return false;
  if (consecutiveFails > maxConsecutiveFails) return false;
  return nextIndex != currentIndex;
}
