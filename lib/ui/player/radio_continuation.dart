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
