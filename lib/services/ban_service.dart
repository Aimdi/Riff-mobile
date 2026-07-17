import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

/// "Never Play This" (ported from Riff desktop): banned songs are kept out
/// of radio / up-next suggestions. Explicitly playing a banned song still
/// works - the ban only silences recommendations.
class BanService {
  BanService._();

  static Box get _box => Hive.box("BannedSongs");

  static bool isBanned(String songId) => _box.containsKey(songId);

  static Future<void> ban(MediaItem song) => _box.put(song.id, {
        "title": song.title,
        "artist": song.artist ?? "",
      });

  static Future<void> unban(String songId) => _box.delete(songId);

  /// [{id, title, artist}] of all banned songs.
  static List<Map<String, dynamic>> get all => _box.keys
      .map((k) => {
            "id": k as String,
            "title": _box.get(k)["title"] ?? "",
            "artist": _box.get(k)["artist"] ?? "",
          })
      .toList();

  /// Removes banned songs from a raw track list (maps with 'videoId').
  /// [keepVideoId] survives the filter so an explicitly requested song is
  /// never dropped from its own watch playlist.
  static List<dynamic> filterTracks(List<dynamic> tracks,
      {String? keepVideoId}) {
    if (_box.isEmpty) return tracks;
    return tracks
        .where((t) =>
            t['videoId'] == keepVideoId || !_box.containsKey(t['videoId']))
        .toList();
  }
}
