import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/artist.dart';
import '../../models/media_Item_builder.dart';
import '../../models/playling_from.dart';
import '../../services/music_service.dart';
import '../../services/piped_service.dart';
import '../../services/playlist_mix_service.dart';
import '../player/play_queue_order.dart';
import '../player/player_controller.dart';

bool isSystemLibraryPlaylistId(String id) =>
    id == 'LIBRP' ||
    id == 'LIBFAV' ||
    id == 'SongsCache' ||
    id == 'SongDownloads';

/// Album, playlist, and artist tiles play on the body tap.
/// Long-press still opens Play / Shuffle / View.
bool shouldPlayCollectionOnTap() => true;

/// Load album/playlist tracks from Hive, Piped, or MusicServices.
Future<List<MediaItem>> loadCollectionPlayTracks({
  required bool isAlbum,
  required String id,
  bool isLibraryItem = false,
  bool isPipedPlaylist = false,
  bool isCloudPlaylist = true,
}) async {
  if (id.isEmpty) return const [];

  if (isAlbum) {
    if (isLibraryItem) {
      final local = await tracksFromOpenBox(id);
      if (local.isNotEmpty) return local;
    }
    if (!Get.isRegistered<MusicServices>()) return const [];
    final result =
        await Get.find<MusicServices>().getPlaylistOrAlbumSongs(albumId: id);
    return List<MediaItem>.from(result['tracks'] ?? const []);
  }

  if (isPipedPlaylist && Get.isRegistered<PipedServices>()) {
    return Get.find<PipedServices>().getPlaylistSongs(id);
  }

  final tryLocal =
      isLibraryItem || !isCloudPlaylist || isSystemLibraryPlaylistId(id);
  if (tryLocal) {
    final local = await tracksFromOpenBox(id);
    if (local.isNotEmpty) {
      return id == 'LIBRP' ? local.reversed.toList() : local;
    }
    if (isSystemLibraryPlaylistId(id) || !isCloudPlaylist) {
      return const [];
    }
  }

  if (!Get.isRegistered<MusicServices>()) return const [];
  final result =
      await Get.find<MusicServices>().getPlaylistOrAlbumSongs(playlistId: id);
  return List<MediaItem>.from(result['tracks'] ?? const []);
}

Future<List<MediaItem>> tracksFromOpenBox(String id) async {
  try {
    if (!Hive.isBoxOpen(id)) {
      await Hive.openBox(id);
    }
    final tracks = <MediaItem>[];
    for (final raw in Hive.box(id).values) {
      try {
        final item = MediaItemBuilder.fromJson(raw);
        if (item.id.isNotEmpty) tracks.add(item);
      } catch (_) {}
    }
    return tracks;
  } catch (_) {
    return const [];
  }
}

/// Play an album/playlist immediately. Returns false when there is nothing
/// to play so the caller can open the detail screen instead.
Future<bool> playCollection({
  required bool isAlbum,
  required String id,
  required String title,
  bool shuffle = false,
  bool isLibraryItem = false,
  bool isPipedPlaylist = false,
  bool isCloudPlaylist = true,
}) async {
  final tracks = await loadCollectionPlayTracks(
    isAlbum: isAlbum,
    id: id,
    isLibraryItem: isLibraryItem,
    isPipedPlaylist: isPipedPlaylist,
    isCloudPlaylist: isCloudPlaylist,
  );
  if (tracks.isEmpty || !Get.isRegistered<PlayerController>()) return false;
  if (Get.isRegistered<PlaylistMixService>()) {
    Get.find<PlaylistMixService>().deactivatePlayback();
  }
  await Get.find<PlayerController>().playPlayListSong(
    playQueueFrom(tracks, shuffle: shuffle),
    0,
    playfrom: PlaylingFrom(
      name: title,
      type: isAlbum ? PlaylingFromType.ALBUM : PlaylingFromType.PLAYLIST,
    ),
  );
  return true;
}

/// Top tracks from [MusicServices.getArtist] (or the remapped Songs key).
List<MediaItem> artistTopSongsFromResponse(Map<String, dynamic> artist) {
  final section = artist['Top songs'] ?? artist['Songs'];
  if (section is Map && section['content'] is List) {
    return (section['content'] as List).whereType<MediaItem>().toList();
  }
  if (section is List) {
    return section.whereType<MediaItem>().toList();
  }
  return const [];
}

/// Play an artist's top songs, or start their radio. Returns false when the
/// caller should open the artist screen instead.
Future<bool> playArtist(
  Artist artist, {
  bool shuffle = false,
  bool radio = false,
}) async {
  if (!Get.isRegistered<PlayerController>()) return false;
  final player = Get.find<PlayerController>();
  final radioId = artist.radioId?.trim() ?? '';

  if (radio && radioId.isNotEmpty) {
    await player.startRadio(null, playlistid: radioId);
    return true;
  }

  if (!Get.isRegistered<MusicServices>()) return false;
  final data = await Get.find<MusicServices>().getArtist(artist.browseId);
  final songs = artistTopSongsFromResponse(data);
  if (songs.isEmpty) return false;

  if (radio) {
    await player.startRadio(songs.first);
    return true;
  }

  await player.playPlayListSong(
    playQueueFrom(songs, shuffle: shuffle),
    0,
    playfrom: PlaylingFrom(
      name: artist.name,
      type: PlaylingFromType.ARTIST,
    ),
  );
  return true;
}
