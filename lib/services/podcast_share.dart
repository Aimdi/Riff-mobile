/// Sharing a podcast episode, as Pocket Casts, Spotify and Apple Podcasts
/// share one, also from the moment playing (Pocket Casts' "current
/// position").
library;

import 'package:audio_service/audio_service.dart';

import 'podcast_progress_service.dart';
import 'podcast_segments.dart' show formatSegmentLength;

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

String? _web(Object? url) {
  final s = '${url ?? ''}'.trim();
  final uri = Uri.tryParse(s);
  return uri != null && (uri.isScheme('http') || uri.isScheme('https'))
      ? s
      : null;
}

/// The link to share [item] with: the YouTube video for a YouTube episode,
/// else the episode's page from its feed, its audio file, or the feed. From
/// [at] where the link can start there (YouTube's `t=`, an audio file's
/// `#t=`).
String? podcastEpisodeShareLink(MediaItem item, {Duration? at}) {
  final sec = at?.inSeconds ?? 0;
  if (!item.id.startsWith('podcast_') && _videoId.hasMatch(item.id)) {
    return 'https://youtu.be/${item.id}${sec > 0 ? '?t=$sec' : ''}';
  }
  final page = _web(item.extras?['link']);
  if (page != null) return page;
  final audio = _web(PodcastProgressService.storableUrl(
    remoteUrl: item.extras?['remoteUrl']?.toString(),
    currentUrl: item.extras?['url']?.toString(),
  ));
  if (audio != null) {
    return sec > 0 && !audio.contains('#') ? '$audio#t=$sec' : audio;
  }
  return _web(item.extras?['feedUrl']);
}

/// "Show, Episode" and its link; from [at]: "Show, Episode @ 12:34", as
/// bookmarks are shared.
String podcastEpisodeShareText(MediaItem item, {Duration? at}) {
  final where = [item.artist ?? '', item.title]
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join(', ');
  final head = at == null
      ? where
      : '$where @ ${formatSegmentLength(at.inMilliseconds / 1000)}';
  final link = podcastEpisodeShareLink(item, at: at);
  return link == null ? head : '$head\n$link';
}
