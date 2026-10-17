/// Songs you're not interested in, as YouTube Music's and Spotify's "Not
/// interested" on what they pick for you: kept out of radio, Up next,
/// Autoplay, Riff's mixes and Home's song shelves. Unlike Never play this,
/// you can still play them yourself (search, an album, a playlist).
library;

import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

class NotInterested {
  NotInterested._();

  /// Hive box: song id → {title, artist, at}.
  static const box = 'NotInterested';

  static Box? get _box => Hive.isBoxOpen(box) ? Hive.box(box) : null;

  static bool has(String id) => _box?.containsKey(id) ?? false;

  /// A track map (with a 'videoId'), as recommendations carry them.
  static bool hasTrack(Map track) => has('${track['videoId'] ?? ''}');

  static Future<void> add(MediaItem song, {DateTime? now}) async {
    await _box?.put(song.id, {
      'title': song.title,
      'artist': song.artist ?? '',
      'at': (now ?? DateTime.now()).millisecondsSinceEpoch,
    });
  }

  static Future<void> remove(String id) async => _box?.delete(id);

  /// [tracks] ([MediaItem]s or maps with a 'videoId') without the songs
  /// you're not interested in; [keepId], the song asked for, stays.
  static List<T> filter<T>(List<T> tracks, {String? keepId}) {
    if (_box?.isEmpty ?? true) return tracks;
    return [
      for (final t in tracks)
        if (_idOf(t) case final id when id == keepId || !has(id)) t,
    ];
  }

  static String _idOf(Object? track) => switch (track) {
        MediaItem(:final id) => id,
        Map() => '${track['videoId'] ?? ''}',
        _ => '',
      };
}
