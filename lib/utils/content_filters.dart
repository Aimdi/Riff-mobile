import 'package:audio_service/audio_service.dart';

import '/services/podcast_share.dart';
import '/utils/media_item_video.dart';

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// song.link / Odesli share helpers.
class SongLinkShare {
  SongLinkShare._();

  /// Universal Song.link URL for a YouTube Music / YouTube video id.
  static String urlForVideoId(String videoId) {
    final id = videoId.trim();
    return 'https://song.link/https://youtube.com/watch?v=$id';
  }

  /// What sharing [song] sends: its title and artist with its song.link
  /// (a song or video from YouTube); a podcast episode as episodes are
  /// shared; just the title and artist for a song on the phone, from your
  /// own server or the like, whose address nobody else can open.
  static String shareText(MediaItem song) {
    if (song.id.startsWith('podcast_') || song.extras?['isPodcast'] == true) {
      return podcastEpisodeShareText(song);
    }
    final artist = (song.artist ?? '').trim();
    final what = artist.isEmpty ? song.title : '${song.title} — $artist';
    if (!_videoId.hasMatch(song.id)) return what;
    return '$what\n${urlForVideoId(song.id)}';
  }

  /// What sharing one of your playlists sends with its M3U file: its name
  /// and a link anyone can open, where YouTube plays its first 50 songs
  /// from YouTube as a playlist; just the name when it has none.
  static String playlistText(String name, Iterable<MediaItem> songs) {
    final ids =
        songs.map((s) => s.id).where(_videoId.hasMatch).take(50).toList();
    if (ids.isEmpty) return name;
    return '$name\nhttps://www.youtube.com/watch_videos?video_ids='
        '${ids.join(',')}';
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
