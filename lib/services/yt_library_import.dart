import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import '../utils/helper.dart';
import '../utils/hive_boxes.dart';
import 'discovery/discovery_service.dart';
import 'music_service.dart';
import 'podcast_playback_profile.dart' show podcastShowKeyForYoutube;
import 'utils.dart';
import 'yt_auth_service.dart';

/// What came in from YouTube Music: how many playlists, albums, artists
/// and podcasts were added, each null when it couldn't be read.
typedef YtLibraryImported = ({
  int? playlists,
  int? albums,
  int? artists,
  int? podcasts
});

/// Your YouTube Music library in Riff's, as Metrolist brings it in: with
/// your YouTube account connected, the playlists in your YouTube Music
/// library (yours and the ones you saved) are added to Library ›
/// Playlists, its albums to Library › Albums, the artists you subscribe
/// to are followed in Library › Artists (so their new releases reach
/// Release Radar) and the podcasts you follow in Subscriptions, those not
/// there yet. Liked music comes in as your Favorites (YtLikeSync) and Episodes
/// for later isn't music, so neither comes as a playlist.
class YtLibraryImport {
  YtLibraryImport._();

  static const playlistsBox = 'LibraryPlaylists';
  static const albumsBox = 'LibraryAlbums';
  static const artistsBox = 'LibraryArtists';
  static const podcastsBox = 'LibraryPodcasts';

  /// Liked music and Episodes for later.
  static const _notPlaylists = {'LM', 'SE'};

  /// Whether the library is coming in now.
  static final importing = false.obs;

  /// Your YouTube Music library's playlists; tests replace it.
  @visibleForTesting
  static Future<List<Playlist>> Function() fetchPlaylists =
      () => Get.find<MusicServices>().getLibraryPlaylists();

  /// The albums saved in your YouTube Music library; tests replace it.
  @visibleForTesting
  static Future<List<Album>> Function() fetchAlbums =
      () => Get.find<MusicServices>().getLibraryAlbums();

  /// The artists you subscribe to in YouTube Music; tests replace it.
  @visibleForTesting
  static Future<List<Artist>> Function() fetchArtists =
      () => Get.find<MusicServices>().getLibrarySubscriptions();

  /// The podcasts you follow in YouTube Music; tests replace it.
  @visibleForTesting
  static Future<List<Playlist>> Function() fetchPodcasts =
      () => Get.find<MusicServices>().getLibraryPodcasts();

  /// Whether a YouTube account is connected; tests replace it.
  @visibleForTesting
  static bool Function() connected = () => YtAuthService.isConnected;

  /// Brings in the playlists, albums and artists Riff's Library doesn't
  /// have yet;
  /// null without an account (or while they're already coming).
  static Future<YtLibraryImported?> importLibrary() async {
    if (!connected() || importing.value) return null;
    importing.value = true;
    try {
      return (
        playlists: await _guard('playlists', _importPlaylists),
        albums: await _guard('albums', _importAlbums),
        artists: await _guard('artists', _importArtists),
        podcasts: await _guard('podcasts', _importPodcasts),
      );
    } finally {
      importing.value = false;
    }
  }

  static Future<int?> _guard(String what, Future<int> Function() run) async {
    try {
      return await run();
    } catch (e) {
      printERROR('YouTube Music $what not read: $e');
      return null;
    }
  }

  /// Saved under either form of their id (VL… or not) counts as there.
  static Future<int> _importPlaylists() async {
    final playlists = await fetchPlaylists();
    final box = await HiveBoxes.open(playlistsBox);
    bool saved(String id) => box.containsKey(id) || box.containsKey('VL$id');
    final fresh = <String, dynamic>{
      for (final playlist in playlists)
        if (validatePlaylistId(playlist.playlistId) case final id
            when id.isNotEmpty && !_notPlaylists.contains(id) && !saved(id))
          playlist.playlistId: playlist.toJson(),
    };
    if (fresh.isNotEmpty) await box.putAll(fresh);
    return fresh.length;
  }

  /// Saved as saving one in Riff does (its songs are read when it's
  /// opened).
  static Future<int> _importAlbums() async {
    final albums = await fetchAlbums();
    final box = await HiveBoxes.open(albumsBox);
    final fresh = <String, dynamic>{
      for (final album in albums)
        if (album.browseId.isNotEmpty && !box.containsKey(album.browseId))
          album.browseId: album.toJson(),
    };
    if (fresh.isNotEmpty) await box.putAll(fresh);
    return fresh.length;
  }

  /// Followed as following a show in Riff does (Subscriptions' Recently
  /// followed counts from now), unless it is under any form of its id.
  static Future<int> _importPodcasts() async {
    final podcasts = await fetchPodcasts();
    final box = await HiveBoxes.open(podcastsBox);
    final followed = {for (final k in box.keys) podcastShowKeyForYoutube('$k')};
    final now = DateTime.now().millisecondsSinceEpoch;
    final fresh = <String, dynamic>{
      for (final show in podcasts)
        if (podcastShowKeyForYoutube(show.playlistId) case final key?
            when !followed.contains(key))
          show.playlistId: {
            ...show.toJson(),
            'kind': 'podcast',
            'description': show.description ?? 'Podcast',
            'addedAt': now,
          },
    };
    if (fresh.isNotEmpty) await box.putAll(fresh);
    return fresh.length;
  }

  /// Followed as following one in Riff does: in Library › Artists, for
  /// Release Radar, and as a liking of the artist.
  static Future<int> _importArtists() async {
    final artists = await fetchArtists();
    final box = await HiveBoxes.open(artistsBox);
    final fresh = <String, Artist>{
      for (final artist in artists)
        if (artist.browseId.isNotEmpty && !box.containsKey(artist.browseId))
          artist.browseId: artist,
    };
    if (fresh.isEmpty) return 0;
    await box.putAll({
      for (final e in fresh.entries) e.key: e.value.toJson(),
    });
    final discovery = Get.isRegistered<DiscoveryService>()
        ? Get.find<DiscoveryService>()
        : null;
    if (discovery != null) {
      for (final artist in fresh.values) {
        await discovery.repo.followArtist(artist.browseId,
            name: artist.name, thumbnailUrl: artist.thumbnailUrl);
        await discovery.onFollow(artist.name, follow: true);
      }
    }
    return fresh.length;
  }
}
