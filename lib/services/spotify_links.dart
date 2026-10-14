/// Spotify links shared to Riff or pasted into its search: a track's plays
/// its YouTube Music match, an album's or a playlist's opens Import from
/// Spotify with the link.
library;

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '/utils/helper.dart';
import 'spotify_auth_service.dart';
import 'spotify_connect.dart';
import 'spotify_import_service.dart';

enum SpotifyLinkKind { track, album, playlist }

class SpotifyLink {
  const SpotifyLink(this.kind, this.id);
  final SpotifyLinkKind kind;
  final String id;

  /// Its address on open.spotify.com.
  String get url => 'https://open.spotify.com/${kind.name}/$id';
}

SpotifyLinkKind _kind(String name) =>
    SpotifyLinkKind.values.byName(name.toLowerCase());

final _spotifyUri =
    RegExp(r'^spotify:(track|album|playlist):([A-Za-z0-9]{22})$');
final _spotifyPath = RegExp(
    r'^/(?:intl-[a-z]{2}(?:-[a-z]{2})?/)?(?:embed/)?(track|album|playlist)/([A-Za-z0-9]{22})',
    caseSensitive: false);

/// The Spotify track, album or playlist [link] names (open.spotify.com's,
/// with or without a language, play.spotify.com's, or a spotify: URI);
/// null for anything else.
SpotifyLink? spotifyLinkFrom(String link) {
  final s = link.trim();
  final asUri = _spotifyUri.firstMatch(s);
  if (asUri != null) {
    return SpotifyLink(_kind(asUri.group(1)!), asUri.group(2)!);
  }
  final uri = Uri.tryParse(s);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host != 'open.spotify.com' && host != 'play.spotify.com') return null;
  final path = _spotifyPath.firstMatch(uri.path);
  return path == null
      ? null
      : SpotifyLink(_kind(path.group(1)!), path.group(2)!);
}

/// Whether [link] is one of Spotify's short share links (spotify.link/…),
/// which lead to an open.spotify.com one.
bool isSpotifyShortLink(String link) =>
    Uri.tryParse(link.trim())?.host.toLowerCase() == 'spotify.link';

/// Where a spotify.link short link leads, or null when it can't be
/// followed.
Future<SpotifyLink?> followSpotifyShortLink(String link, {Dio? dio}) async {
  try {
    final res = await (dio ?? Dio()).get<String>(link.trim(),
        options: Options(
            followRedirects: true,
            maxRedirects: 5,
            responseType: ResponseType.plain,
            validateStatus: (_) => true));
    final landed = spotifyLinkFrom(res.realUri.toString());
    if (landed != null) return landed;
    // A page that sends you on: the first open.spotify.com link in it.
    final inPage = RegExp(r'https://open\.spotify\.com/[^"\s<>]+')
        .firstMatch(res.data ?? '');
    return inPage == null ? null : spotifyLinkFrom(inPage.group(0)!);
  } catch (e) {
    printERROR('Spotify short link failed ($link): $e');
    return null;
  }
}

/// The YouTube Music song for Spotify's track [id], matched as imports
/// match tracks: what Spotify says of it (its Web API when you're signed
/// in to Spotify, which gives the ISRC; else its public embed page). Null
/// when it can't be read or nothing matches.
Future<MediaItem?> spotifyTrackOnYouTubeMusic(String id) async {
  if (!Get.isRegistered<SpotifyImportService>()) {
    Get.put(SpotifyImportService(), permanent: false);
  }
  final importer = Get.find<SpotifyImportService>();
  SpotifyTrackRef? track;
  if (SpotifyAuthService.isConnected) {
    try {
      track = await SpotifyConnect.api.fetchTrack(id);
    } catch (e) {
      printERROR('Spotify track $id from the Web API failed: $e');
    }
  }
  try {
    track ??= await importer.fetchPublicTrack(id);
    return track == null ? null : await importer.resolveTrack(track);
  } catch (e) {
    printERROR('Spotify track $id failed: $e');
    return null;
  }
}
