import 'package:audio_service/audio_service.dart';

import '/models/media_item_extras.dart';

/// ListenBrainz / Last.fm rule: a track counts as listened once it played
/// for half its length or 4 minutes, whichever comes first. Tracks under
/// 30 s, podcast episodes and audiobooks are never scrobbled.
bool shouldScrobble({
  required MediaItem item,
  required Duration listened,
  Duration? total,
}) {
  if (item.isPodcastEpisode || item.isAudiobookshelf) return false;
  const cap = Duration(minutes: 4);
  final t = total ?? item.duration;
  if (t == null || t <= Duration.zero) return listened >= cap;
  if (t < const Duration(seconds: 30)) return false;
  final half = Duration(milliseconds: t.inMilliseconds ~/ 2);
  return listened >= (half < cap ? half : cap);
}
