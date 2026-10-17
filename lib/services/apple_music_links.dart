/// Apple Music links shared to Riff or pasted into its search: a song's
/// plays its YouTube Music match, an album's or an artist's opens the same
/// album or artist on YouTube Music. What they are comes from Apple's
/// public lookup (the directory Riff's podcast search uses), matched as
/// Spotify imports are.
library;

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

import '/models/album.dart';
import '/models/artist.dart';
import '/utils/helper.dart';
import 'music_service.dart';
import 'podcast_service.dart';
import 'spotify_import_service.dart';
import 'spotify_match.dart';

enum AppleMusicLinkKind { song, album, artist }

class AppleMusicLink {
  const AppleMusicLink(this.kind, this.id);
  final AppleMusicLinkKind kind;

  /// Apple's id for it.
  final String id;
}

/// The Apple Music song, album or artist [link] names (music.apple.com's,
/// or an iTunes Store link's); null for anything else, playlists and
/// podcasts included.
AppleMusicLink? appleMusicLinkFrom(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host != 'music.apple.com' &&
      host != 'itunes.apple.com' &&
      host != 'geo.music.apple.com') {
    return null;
  }
  // /us/album/the-name/1440857781?i=1440857795, /us/song/the-name/1440857795,
  // /us/artist/the-name/136975; iTunes' ids read "id1440857781".
  final segments = uri.pathSegments;
  final kindAt = segments.indexWhere((s) =>
      s == 'album' || s == 'song' || s == 'artist' || s == 'music-video');
  if (kindAt < 0) return null;
  final id = segments
      .skip(kindAt + 1)
      .map((s) => RegExp(r'^(?:id)?(\d+)$').firstMatch(s)?.group(1))
      .whereType<String>()
      .lastOrNull;
  if (id == null) return null;
  final song = uri.queryParameters['i'];
  switch (segments[kindAt]) {
    case 'album':
      return song != null && RegExp(r'^\d+$').hasMatch(song)
          ? AppleMusicLink(AppleMusicLinkKind.song, song)
          : AppleMusicLink(AppleMusicLinkKind.album, id);
    case 'artist':
      return AppleMusicLink(AppleMusicLinkKind.artist, id);
    default:
      return AppleMusicLink(AppleMusicLinkKind.song, id);
  }
}

/// A song as Apple's lookup describes it, to be matched as Spotify tracks
/// are; null when [found] isn't a song.
SpotifyTrackRef? appleMusicSong(Map<String, dynamic>? found) {
  if (found == null || found['wrapperType'] != 'track') return null;
  final title = '${found['trackName'] ?? ''}'.trim();
  if (title.isEmpty) return null;
  final ms = found['trackTimeMillis'];
  return SpotifyTrackRef(
    id: 'applemusic:${found['trackId']}',
    title: title,
    artists: '${found['artistName'] ?? ''}'.trim(),
    durationMs: ms is num && ms > 0 ? ms.toInt() : null,
    album: '${found['collectionName'] ?? ''}'.trim(),
  );
}

/// Of YouTube Music's [albums], the one that's Apple's album [title] by
/// [artist], or null when none is close enough ("- Single" and "- EP" as
/// Apple names singles don't count).
Album? matchingAlbum(String title, String artist, List<Album> albums) =>
    bestMatch<Album>(
      albums,
      score: (a) =>
          similarityOf(title, a.title) * 0.6 +
          similarityOf(
                  artist,
                  (a.artists ?? const [])
                      .map((x) => '${x['name']}')
                      .join(', ')) *
              0.4,
      minScore: 0.6,
    )?.item;

/// Of YouTube Music's [artists], the one named [name], or null.
Artist? matchingArtist(String name, List<Artist> artists) =>
    bestMatch<Artist>(artists,
            score: (a) => similarityOf(name, a.name), minScore: 0.8)
        ?.item;

/// What a link opens: the song to play, or the album or artist to open.
typedef AppleMusicMatch = ({MediaItem? song, Album? album, Artist? artist});

/// YouTube Music's song, album or artist for [link], or null when Apple
/// doesn't say what it is or nothing matches.
Future<AppleMusicMatch?> appleMusicOnYouTubeMusic(AppleMusicLink link) async {
  final found = await PodcastService.directoryLookup(link.id);
  if (found == null) return null;
  final music = Get.find<MusicServices>();
  try {
    switch (link.kind) {
      case AppleMusicLinkKind.song:
        final song = appleMusicSong(found);
        if (song == null) return null;
        if (!Get.isRegistered<SpotifyImportService>()) {
          Get.put(SpotifyImportService(), permanent: false);
        }
        final ranked = await Get.find<SpotifyImportService>()
            .rankCandidates(song, stopAtConfident: true);
        final best = ranked.firstOrNull;
        return best == null || best.score < kMinAcceptableMatch
            ? null
            : (song: best.item, album: null, artist: null);
      case AppleMusicLinkKind.album:
        final title = '${found['collectionName'] ?? ''}'.trim();
        final artist = '${found['artistName'] ?? ''}'.trim();
        if (title.isEmpty) return null;
        final res =
            await music.search('$title $artist', filter: 'albums', limit: 10);
        final album = matchingAlbum(
            title, artist, [...?res['Albums']].whereType<Album>().toList());
        return album == null ? null : (song: null, album: album, artist: null);
      case AppleMusicLinkKind.artist:
        final name = '${found['artistName'] ?? ''}'.trim();
        if (name.isEmpty) return null;
        final res = await music.search(name, filter: 'artists', limit: 10);
        final artist = matchingArtist(
            name, [...?res['Artists']].whereType<Artist>().toList());
        return artist == null
            ? null
            : (song: null, album: null, artist: artist);
    }
  } catch (e) {
    printERROR('Apple Music link ${link.id} failed: $e');
    return null;
  }
}
