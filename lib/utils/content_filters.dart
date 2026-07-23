import 'package:audio_service/audio_service.dart';

import '/utils/media_item_video.dart';

/// song.link / Odesli share helpers.
class SongLinkShare {
  SongLinkShare._();

  /// Universal Song.link URL for a YouTube Music / YouTube video id.
  static String urlForVideoId(String videoId) {
    final id = videoId.trim();
    return 'https://song.link/https://youtube.com/watch?v=$id';
  }

  static String shareText(MediaItem song) {
    final link = urlForVideoId(song.id);
    final artist = (song.artist ?? '').trim();
    if (artist.isEmpty) return '${song.title}\n$link';
    return '${song.title} — $artist\n$link';
  }
}

/// Home / search content filters (Echo-style hide video & Shorts).
class ContentFilters {
  ContentFilters._();

  static bool isShortsItem(MediaItem item) {
    final url = '${item.extras?['url'] ?? ''}';
    if (url.contains('/shorts/')) return true;
    final vt = '${item.extras?['videoType'] ?? ''}';
    return vt.toUpperCase().contains('SHORT');
  }

  static bool isVideoSong(MediaItem item) => item.isYoutubeVideo;

  static List<MediaItem> apply(
    List<MediaItem> items, {
    required bool hideVideos,
    required bool hideShorts,
  }) {
    if (!hideVideos && !hideShorts) return items;
    return items.where((m) {
      if (hideShorts && isShortsItem(m)) return false;
      if (hideVideos && isVideoSong(m)) return false;
      return true;
    }).toList();
  }
}
