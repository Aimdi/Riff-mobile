import 'package:audio_service/audio_service.dart' show MediaItem;

import '../models/thumbnail.dart';

class PlaylistContent {
  PlaylistContent({required this.title, required this.playlistList});
  final String title;
  final List<Playlist> playlistList;

  factory PlaylistContent.fromJson(Map<dynamic, dynamic> json) =>
      PlaylistContent(
          title: json['title'],
          playlistList: (json['playlists'] as List)
              .map((e) => Playlist.fromJson(e))
              .toList());
  Map<String, dynamic> toJson() => {
        "type": "Playlist Content",
        "title": title,
        "playlists": playlistList.map((e) => e.toJson()).toList()
      };
}

class Playlist {
  Playlist(
      {required this.title,
      required this.playlistId,
      this.description,
      required this.thumbnailUrl,
      this.songCount,
      this.isPipedPlaylist = false,
      this.isCloudPlaylist = true,
      this.kind});
  final String playlistId;
  String title;
  final bool isPipedPlaylist;
  final String? description;
  String thumbnailUrl;
  final String? songCount;
  final bool isCloudPlaylist;

  /// System mix kind: daily_mix / fresh_finds / release_radar / rediscover.
  final String? kind;
  static const thumbPlaceholderUrl =
      "https://raw.githubusercontent.com/anandnet/Harmony-Music/refs/heads/main/playlist_placeholder.png";

  factory Playlist.fromJson(Map<dynamic, dynamic> json) {
    final thumbs = json["thumbnails"];
    final kind = json["kind"]?.toString();
    final id = (json["playlistId"] ?? json["browseId"] ?? '').toString();
    String thumbUrl = thumbPlaceholderUrl;
    // Prefer square studio/playlist covers over landscape video screenshots.
    final best = Thumbnail.bestUrl(
      thumbs,
      target: 'extraHigh',
      preferSquare: true,
    );
    if (best.isNotEmpty) {
      thumbUrl = best;
    } else if (json["thumbnailUrl"] != null) {
      thumbUrl = Thumbnail(json["thumbnailUrl"].toString()).extraHigh;
    }
    return Playlist(
        title: json["title"] ?? '',
        playlistId: id,
        thumbnailUrl: thumbUrl,
        description: json["description"] ?? "Playlist",
        songCount: json['itemCount']?.toString(),
        isPipedPlaylist: json["isPipedPlaylist"] ?? false,
        isCloudPlaylist: json["isCloudPlaylist"] ?? true,
        kind: kind);
  }

  Map<String, dynamic> toJson() => {
        "title": title,
        "playlistId": playlistId,
        "description": description,
        'thumbnails': [
          {'url': thumbnailUrl}
        ],
        "itemCount": songCount,
        "isPipedPlaylist": isPipedPlaylist,
        "isCloudPlaylist": isCloudPlaylist,
        if (kind != null) "kind": kind,
      };

  Playlist copyWith({String? title, String? thumbnailUrl, String? kind}) {
    return Playlist(
        title: title ?? this.title,
        playlistId: playlistId,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        description: description,
        songCount: songCount,
        isPipedPlaylist: isPipedPlaylist,
        isCloudPlaylist: isCloudPlaylist,
        kind: kind ?? this.kind);
  }

  // Converts this object to a MediaItem object.
  // This is used to display the playlist in Android auto.
  MediaItem toMediaItem() {
    return MediaItem(
        id: playlistId,
        title: title,
        artUri: Uri.parse(thumbnailUrl),
        playable: false);
  }

  set newTitle(String title) {
    this.title = title;
  }
}
