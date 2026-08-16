/// Songs after [currentIndex] — the Spotify-style "Up next" remainder.
List<T> upcomingAfterIndex<T>(List<T> queue, int currentIndex) {
  if (currentIndex < 0 || currentIndex >= queue.length - 1) {
    return <T>[];
  }
  return queue.sublist(currentIndex + 1);
}

/// Collapsed-strip preview: first upcoming title, plus "· N more" when needed.
String upcomingPreviewLabel(String firstTitle, int upcomingCount) {
  if (upcomingCount <= 0) return '';
  if (upcomingCount == 1) return firstTitle;
  return '$firstTitle · ${upcomingCount - 1} more';
}
