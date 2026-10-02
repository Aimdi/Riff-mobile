import 'package:audio_service/audio_service.dart';

import 'artist.dart';
import 'media_Item_builder.dart';

/// A YouTube Music home shelf made of songs ("Listen again", "Forgotten
/// favourites", …). Album and playlist shelves have their own models.
class SongContent {
  SongContent({required this.title, required this.songs});
  final String title;
  final List<MediaItem> songs;

  factory SongContent.fromJson(Map<dynamic, dynamic> json) => SongContent(
      title: json['title'],
      songs: (json['songs'] as List)
          .map((e) => MediaItemBuilder.fromJson(e))
          .toList());

  Map<String, dynamic> toJson() => {
        "type": "Song Content",
        "title": title,
        "songs": songs.map((e) => MediaItemBuilder.toJson(e)).toList(),
      };
}

/// A home shelf of artists ("Similar artists", "Artists you might like").
class ArtistShelf {
  ArtistShelf({required this.title, required this.artists});
  final String title;
  final List<Artist> artists;

  factory ArtistShelf.fromJson(Map<dynamic, dynamic> json) => ArtistShelf(
      title: json['title'],
      artists:
          (json['artists'] as List).map((e) => Artist.fromJson(e)).toList());

  Map<String, dynamic> toJson() => {
        "type": "Artist Content",
        "title": title,
        "artists": artists.map((e) => e.toJson()).toList(),
      };
}
