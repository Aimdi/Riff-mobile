import 'package:audio_service/audio_service.dart';

/// Helpers for distinguishing YouTube Music *songs* from actual *videos*.
///
/// Songs (ATV) keep the classic square album-art player. Videos (OMV / UGC /
/// Search → Videos) can show an in-player 16:9 surface.
///
/// YouTube **podcast** episodes (YTM shows + channel-as-podcast) can also show
/// video when [canShowPlayerVideo] is true — RSS audio podcasts never do.
extension MediaItemVideoX on MediaItem {
  /// True for YouTube music videos / regular videos — not songs or podcasts.
  bool get isYoutubeVideo {
    final vt = '${extras?['videoType'] ?? ''}';
    if (vt.contains('PODCAST')) return false;
    if (vt == 'MUSIC_VIDEO_TYPE_ATV') return false;
    if (vt.isNotEmpty) return true;
    final rt = '${extras?['resultType'] ?? ''}'.toLowerCase();
    return rt == 'video';
  }

  /// Whether the in-player 16:9 surface may load for this item.
  ///
  /// True only for music videos — NOT podcasts.
  ///
  /// Podcasts (RSS or YouTube-sourced) are audio-first: the in-player video
  /// surface is never engaged for them. Resolving a separate video stream
  /// for a long episode made playback sit "loading" instead of just playing
  /// the audio — a podcast should start instantly as audio.
  bool get canShowPlayerVideo {
    if (id.startsWith('podcast_')) return false;
    if (extras?['isPodcast'] == true) return false;
    final source = '${extras?['podcastSource'] ?? ''}';
    if (source == 'yt_channel' || source == 'yt_music_podcast') return false;
    return isYoutubeVideo;
  }
}

/// Same logic for maps / seeds that are not yet MediaItems.
bool looksLikeYoutubeVideo({String? videoType, String? resultType}) {
  final vt = videoType ?? '';
  if (vt.contains('PODCAST')) return false;
  if (vt == 'MUSIC_VIDEO_TYPE_ATV') return false;
  if (vt.isNotEmpty) return true;
  return (resultType ?? '').toLowerCase() == 'video';
}
