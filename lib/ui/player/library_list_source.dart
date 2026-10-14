/// Where playback from a list in your Library comes from, for the player's
/// "Playing from" and what hangs on it: the header opening the list, a
/// playlist left out of your taste profile staying out, Recents, removing
/// a song from the playlist playing.
library;

import '/models/album.dart';
import '/models/playling_from.dart';
import '/models/playlist.dart';
import '/ui/screens/Library/library_controller.dart'
    show LibraryPlaylistsController;
import '/utils/hive_boxes.dart';

/// The Library's own list [id] (Recently played, Favorites, Cached,
/// Downloads) as its page opens; null for any other id. Their pages can't
/// open from the id alone, which would look for them online.
Playlist? libraryOwnList(String id) {
  for (final list in LibraryPlaylistsController.initPlst) {
    if (list.playlistId == id) return list;
  }
  return null;
}

/// What plays from the Library's list [id] comes from: one of its own
/// lists, or a playlist or an album saved in it (as it's named now); null
/// for anything else.
Future<PlaylingFrom?> libraryListSource(String id) async {
  final own = libraryOwnList(id);
  if (own != null) {
    return PlaylingFrom(
        type: PlaylingFromType.PLAYLIST, name: own.title, id: id, item: own);
  }
  try {
    final playlist = (await HiveBoxes.open('LibraryPlaylists')).get(id);
    if (playlist is Map) {
      final saved = Playlist.fromJson(playlist);
      return PlaylingFrom(
          type: PlaylingFromType.PLAYLIST,
          name: saved.title,
          id: id,
          item: saved);
    }
    final album = (await HiveBoxes.open('LibraryAlbums')).get(id);
    if (album is Map) {
      final saved = Album.fromJson(album);
      return PlaylingFrom(
          type: PlaylingFromType.ALBUM, name: saved.title, id: id, item: saved);
    }
  } catch (_) {
    // Storage that won't open: nowhere to say.
  }
  return null;
}
