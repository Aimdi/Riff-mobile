import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

/// "Never Play This" (ported from Riff desktop, extended with RiPlay's
/// artist-level blacklist): banned songs — and every song by a banned
/// artist — are kept out of radio / up-next suggestions. Explicitly
/// playing a banned item still works; the ban only silences
/// recommendations.
/// Artist names in a raw track map: `artists: [{name}]`, else `artist`.
List<String> trackArtistNames(Map t) {
  final artists = t['artists'];
  if (artists is List) {
    return [
      for (final a in artists)
        if (a is Map && '${a['name'] ?? ''}'.trim().isNotEmpty)
          '${a['name']}'.trim()
        else if (a is String && a.trim().isNotEmpty)
          a.trim()
    ];
  }
  final one = '${t['artist'] ?? ''}'.trim();
  return one.isEmpty ? const [] : [one];
}

/// Album browse id in a raw track map (`album: {id}` or `albumId`).
String? trackAlbumId(Map t) {
  final album = t['album'];
  if (album is Map && album['id'] is String && '${album['id']}'.isNotEmpty) {
    return album['id'] as String;
  }
  final id = t['albumId'];
  return id is String && id.isNotEmpty ? id : null;
}

/// The single artists in a credit like "A, B & C feat. D".
List<String> splitArtistCredit(String credit) => credit
    .split(RegExp(r'\s*(?:,|&|\s(?:feat\.?|ft\.)(?=\s))\s*',
        caseSensitive: false))
    .map((a) => a.trim())
    .where((a) => a.isNotEmpty)
    .toList();

/// Whether a recommendation should be kept out: the song is banned, any of
/// its artists is, or its album is.
bool trackBlocked({
  required String? videoId,
  required Iterable<String> artistNames,
  String? albumId,
  required bool Function(String id) songBanned,
  required bool Function(String artist) artistBanned,
  required bool Function(String id) collectionBanned,
}) {
  if (videoId != null && videoId.isNotEmpty && songBanned(videoId)) {
    return true;
  }
  for (final a in artistNames) {
    if (artistBanned(a)) return true;
  }
  return albumId != null && albumId.isNotEmpty && collectionBanned(albumId);
}

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

  static Future<bool> ban(MediaItem song) async {
    if (!Hive.isBoxOpen("BannedSongs")) return false;
    await _box.put(song.id, {
      "title": song.title,
      "artist": song.artist ?? "",
    });
    return true;
  }

  /// Ban by id with the stored details (Undo in the Never play list).
  static Future<void> banRaw(String id, String title, String artist) async {
    if (!Hive.isBoxOpen("BannedSongs")) return;
    await _box.put(id, {"title": title, "artist": artist});
  }

  static Future<bool> unban(String songId) async {
    if (!Hive.isBoxOpen("BannedSongs")) return false;
    await _box.delete(songId);
    return true;
  }

  // --- Artist-level ban (RiPlay-style) ---

  /// Normalizes an artist string so "A, B" and "B, A" don't slip through.
  static String _artistKey(String artist) => artist.trim().toLowerCase();

  static bool isArtistBanned(String? artist) {
    final box = _artistBox;
    if (artist == null || artist.isEmpty || box == null || box.isEmpty) {
      return false;
    }
    // The whole credit (older bans stored "A, B & C" as one entry), then
    // each artist within a multi-artist / "feat." credit.
    if (box.containsKey(_artistKey(artist))) return true;
    for (final part in splitArtistCredit(artist)) {
      if (box.containsKey(_artistKey(part))) return true;
    }
    return false;
  }

  /// The artist "Never play this artist" bans for [song]: the first credited
  /// artist, not the whole "A, B & C" credit (which would only ever match
  /// that exact combination).
  static String? primaryArtist(MediaItem song) {
    final names = trackArtistNames({
      'artists': song.extras?['artists'],
      'artist': song.artist,
    });
    if (names.isNotEmpty) {
      final parts = splitArtistCredit(names.first);
      return parts.isNotEmpty ? parts.first : names.first;
    }
    return null;
  }

  /// Raw track map (YouTube Music shape) blocked by any ban.
  static bool isTrackBlocked(Map t) => trackBlocked(
        videoId: t['videoId']?.toString(),
        artistNames: trackArtistNames(t),
        albumId: trackAlbumId(t),
        songBanned: isBanned,
        artistBanned: isArtistBanned,
        collectionBanned: isCollectionBanned,
      );

  /// [MediaItem] blocked by any ban.
  static bool isMediaItemBlocked(MediaItem m) => isTrackBlocked({
        'videoId': m.id,
        'artists': m.extras?['artists'],
        'artist': m.artist,
        'album': m.extras?['album'],
      });

  /// Hive box is open and can accept a ban write.
  static bool canWriteBan(Box? box) => box != null;

  static Future<bool> banArtist(String artist) async {
    final box = _artistBox;
    if (!canWriteBan(box)) return false;
    await box!.put(_artistKey(artist), {"name": artist.trim()});
    return true;
  }

  static Future<bool> unbanArtist(String key) async {
    final box = _artistBox;
    if (!canWriteBan(box)) return false;
    await box!.delete(key);
    return true;
  }

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

  static Future<bool> unbanCollection(String id) async {
    final box = _collectionBox;
    if (!canWriteBan(box)) return false;
    await box!.delete(id);
    return true;
  }

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

  /// Removes banned songs (and songs by banned artists or from banned
  /// albums) from a track list: [MediaItem]s (watch playlists, home shelves)
  /// or raw maps with 'videoId' / 'artists'. [keepVideoId] survives the
  /// filter so an explicitly requested song is never dropped from its own
  /// watch playlist.
  static List<dynamic> filterTracks(List<dynamic> tracks,
      {String? keepVideoId}) {
    if ((!Hive.isBoxOpen("BannedSongs") || _box.isEmpty) &&
        (_artistBox?.isEmpty ?? true) &&
        (_collectionBox?.isEmpty ?? true)) {
      return tracks;
    }
    return tracks.where((t) {
      // Both callers pass MediaItems; letting every non-map through meant
      // bans never reached radio, up next or the home song shelves.
      if (t is MediaItem) {
        return t.id == keepVideoId || !isMediaItemBlocked(t);
      }
      if (t is! Map) return true;
      if (t['videoId'] == keepVideoId) return true;
      return !isTrackBlocked(t);
    }).toList();
  }
}
