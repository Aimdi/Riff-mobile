/// Cache source dropped the HTTP body mid-read — replay the same URL.
bool isCacheConnectionClosedError(Object error) =>
    error.toString().contains('Connection closed while receiving data');

/// Decode / format errors will not be fixed by fetching the same track again.
bool isUnrecoverableDecodeError(Object error) {
  final s = error.toString().toLowerCase();
  return s.contains('unrecognized input') ||
      s.contains('unrecognized format') ||
      s.contains('unsupported format') ||
      s.contains('malformed') ||
      s.contains('decoder') ||
      s.contains('failed to instantiate decoder');
}

/// Expired, blocked, or dropped sources can be fixed with a fresh stream URL.
bool shouldRefreshUrlOnRuntimeError(Object error) {
  if (isCacheConnectionClosedError(error)) return false;
  if (isUnrecoverableDecodeError(error)) return false;
  return true;
}

/// URL-refresh budget for one song. A new song id resets the count.
bool canAutoRetryUrlRefresh({
  required String? songId,
  required String? budgetSongId,
  required int retryCount,
  required int maxRetries,
}) {
  if (songId == null || songId.isEmpty) return false;
  if (maxRetries <= 0) return false;
  if (budgetSongId != songId) return true;
  return retryCount < maxRetries;
}

/// Retry / skip buttons need a live handler and a valid queue index.
bool canRetryOrSkipPlayback({
  required bool audioReady,
  required int queueLength,
  required int index,
}) =>
    audioReady && index >= 0 && index < queueLength;
