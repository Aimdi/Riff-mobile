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
  static Box get _artistBox => Hive.box("BannedArtists");

  static bool isBanned(String songId) => _box.containsKey(songId);

  static Future<void> ban(MediaItem song) => _box.put(song.id, {
        "title": song.title,
        "artist": song.artist ?? "",
      });

  static Future<void> unban(String songId) => _box.delete(songId);

  // --- Artist-level ban (RiPlay-style) ---

  /// Normalizes an artist string so "A, B" and "B, A" don't slip through.
  static String _artistKey(String artist) => artist.trim().toLowerCase();

  static bool isArtistBanned(String? artist) {
    if (artist == null || artist.isEmpty || _artistBox.isEmpty) return false;
    // Match any individual artist within a "feat."/multi-artist string.
    for (final part in artist.split(RegExp(r'[,&]'))) {
      if (_artistBox.containsKey(_artistKey(part))) return true;
    }
    return false;
  }

  static Future<void> banArtist(String artist) =>
      _artistBox.put(_artistKey(artist), {"name": artist.trim()});

  static Future<void> unbanArtist(String key) => _artistBox.delete(key);

  /// [{key, name}] of all banned artists.
  static List<Map<String, dynamic>> get allArtists => _artistBox.keys
      .map((k) => {
            "key": k as String,
            "name": _artistBox.get(k)["name"] ?? k,
          })
      .toList();

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
    if (_box.isEmpty && _artistBox.isEmpty) return tracks;
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
