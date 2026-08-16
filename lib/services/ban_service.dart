import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

/// "Never Play This" (ported from Riff desktop, extended with RiPlay's
/// artist-level blacklist): banned songs — and every song by a banned
/// artist — are kept out of radio / up-next suggestions. Explicitly
/// playing a banned item still works; the ban only silences
/// recommendations.
class BanService {
  BanService._();

  static Box get _box => Hive.box("BannedSongs");

  // Tolerate the box not being open (e.g. code paths that run before
  // initHive, or isolates that never opened it): treat as "empty".
  static Box? get _artistBox =>
      Hive.isBoxOpen("BannedArtists") ? Hive.box("BannedArtists") : null;
  static Box? get _collectionBox =>
      Hive.isBoxOpen("BannedCollections")
          ? Hive.box("BannedCollections")
          : null;

  static bool isBanned(String songId) =>
      Hive.isBoxOpen("BannedSongs") && _box.containsKey(songId);

  static Future<void> ban(MediaItem song) => _box.put(song.id, {
        "title": song.title,
        "artist": song.artist ?? "",
      });

  static Future<void> unban(String songId) => _box.delete(songId);

  // --- Artist-level ban (RiPlay-style) ---

  /// Normalizes an artist string so "A, B" and "B, A" don't slip through.
  static String _artistKey(String artist) => artist.trim().toLowerCase();

  static bool isArtistBanned(String? artist) {
    final box = _artistBox;
    if (artist == null || artist.isEmpty || box == null || box.isEmpty) {
      return false;
    }
    // Match any individual artist within a "feat."/multi-artist string.
    for (final part in artist.split(RegExp(r'[,&]'))) {
      if (box.containsKey(_artistKey(part))) return true;
    }
    return false;
  }

  /// Hive box is open and can accept a ban write.
  static bool canWriteBan(Box? box) => box != null;

  static Future<bool> banArtist(String artist) async {
    final box = _artistBox;
    if (!canWriteBan(box)) return false;
    await box!.put(_artistKey(artist), {"name": artist.trim()});
    return true;
  }

  static Future<void> unbanArtist(String key) async =>
      _artistBox?.delete(key);

  /// [{key, name}] of all banned artists.
  static List<Map<String, dynamic>> get allArtists =>
      (_artistBox?.keys ?? [])
          .map((k) => {
                "key": k as String,
                "name": _artistBox!.get(k)["name"] ?? k,
              })
          .toList();

  // --- Album / playlist ban ---

  static bool isCollectionBanned(String? id) =>
      id != null && (_collectionBox?.containsKey(id) ?? false);

  static Future<bool> banCollection(
      String id, String title, String type) async {
    final box = _collectionBox;
    if (!canWriteBan(box)) return false;
    await box!.put(id, {"title": title, "type": type});
    return true;
  }

  static Future<void> unbanCollection(String id) async =>
      _collectionBox?.delete(id);

  /// [{id, title, type}] of all banned albums/playlists.
  static List<Map<String, dynamic>> get allCollections =>
      (_collectionBox?.keys ?? [])
          .map((k) => {
                "id": k as String,
                "title": _collectionBox!.get(k)["title"] ?? "",
                "type": _collectionBox!.get(k)["type"] ?? "",
              })
          .toList();

  /// Filters banned albums/playlists out of a list of Album/Playlist
  /// model objects (Album exposes `browseId`, Playlist `playlistId`).
  static List<T> filterCollections<T>(List<T> items) {
    final box = _collectionBox;
    if (box == null || box.isEmpty) return items;
    return items.where((i) {
      String? id;
      try {
        id = (i as dynamic).browseId;
      } catch (_) {}
      if (id == null) {
        try {
          id = (i as dynamic).playlistId;
        } catch (_) {}
      }
      return id == null || !box.containsKey(id);
    }).toList();
  }

  /// [{id, title, artist}] of all banned songs.
  static List<Map<String, dynamic>> get all => _box.keys
      .map((k) => {
            "id": k as String,
            "title": _box.get(k)["title"] ?? "",
            "artist": _box.get(k)["artist"] ?? "",
          })
      .toList();

  /// Removes banned songs (and songs by banned artists) from a raw track
  /// list (maps with 'videoId' / 'artists'). [keepVideoId] survives the
  /// filter so an explicitly requested song is never dropped from its own
  /// watch playlist.
  static List<dynamic> filterTracks(List<dynamic> tracks,
      {String? keepVideoId}) {
    if (_box.isEmpty && (_artistBox?.isEmpty ?? true)) return tracks;
    return tracks.where((t) {
      if (t['videoId'] == keepVideoId) return true;
      if (_box.containsKey(t['videoId'])) return false;
      final artists = t['artists'];
      if (artists is List) {
        for (final a in artists) {
          if (a is Map && isArtistBanned(a['name']?.toString())) return false;
        }
      }
      return true;
    }).toList();
  }
}
