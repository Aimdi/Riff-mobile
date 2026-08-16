/// Spotify-style Home title from the local clock.
String homeGreetingKey(DateTime now) {
  final hour = now.hour;
  if (hour < 12) return 'goodMorning';
  if (hour < 17) return 'goodAfternoon';
  return 'goodEvening';
}

/// Status-bar inset plus a small gap — not an 80px empty band.
double homeFeedTopPadding({
  required bool isDesktop,
  required bool isLandscape,
  required double statusBar,
}) {
  if (isDesktop) return 85;
  if (isLandscape) return statusBar + 8;
  return statusBar + 12;
}
