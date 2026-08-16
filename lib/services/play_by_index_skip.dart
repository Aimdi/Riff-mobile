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

/// Shuffle cursor → queue index. Missing IDs are -1 (never Dart's last item).
int resolveShuffledQueueIndex({
  required List<String> queueIds,
  required String? shuffledId,
}) {
  if (shuffledId == null || shuffledId.isEmpty || queueIds.isEmpty) {
    return -1;
  }
  return queueIds.indexWhere((id) => id == shuffledId);
}

bool isValidQueueIndex(int index, int length) =>
    index >= 0 && index < length;

/// A superseded playByIndex must drop the loading spinner.
bool shouldClearLoadingOnStalePlayByIndex({
  required int requestedIndex,
  required int currentIndex,
}) =>
    requestedIndex != currentIndex;

/// Cloud items store `cloud_{serverId}` — refresh uses the server id.
String cloudServerSongId(String songId) {
  if (songId.startsWith('cloud_')) return songId.substring(6);
  return songId;
}

/// playByIndex customAction result: true started, false hard-failed,
/// null superseded by a newer playByIndex.
bool playByIndexDidStart(dynamic result) => result == true;

/// Hard fail only — a stale/superseded result is not a user-facing failure.
bool playByIndexHardFailed(dynamic result) => result == false;

/// Hive / JSON may store playByIndex as a num or string.
int coercePlayByIndex(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw') ?? -1;
}

/// Arm EOF advance once per track so position ticks cannot double-skip.
bool shouldArmEofAdvance({
  required String? currentId,
  required String? lastArmedId,
}) =>
    currentId != null &&
    currentId.isNotEmpty &&
    currentId != lastArmedId;
