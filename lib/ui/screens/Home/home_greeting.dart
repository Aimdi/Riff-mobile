/// Spotify-style Home title from the local clock.
String homeGreetingKey(DateTime now) {
  final hour = now.hour;
  if (hour < 12) return 'goodMorning';
  if (hour < 17) return 'goodAfternoon';
  return 'goodEvening';
}
