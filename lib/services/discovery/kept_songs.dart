import 'package:hive/hive.dart';

import 'discovery_types.dart';

/// Songs as Riff keeps them, with all they need to play and show (art,
/// album, length, a file's address), for the mixes made of what you play
/// (Rediscover, On Repeat): Favorites, downloads, the song cache and
/// Recently played.
class KeptSongs {
  KeptSongs() : _recent = _recentlyPlayed();

  /// Keyed by song id.
  static const _byId = ['LIBFAV', 'SongDownloads', 'SongsCache'];

  /// Where a kept song was last played from, and when: not the mix's.
  static const _playContext = {
    'discoverySource',
    'discoveryReason',
    'dailyMixId',
    'dailyMixTitle',
    'playedAt',
  };

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Recently played, by id (its keys are its order).
  final Map<String, Map> _recent;

  static Map<String, Map> _recentlyPlayed() {
    if (!Hive.isBoxOpen('LIBRP')) return const {};
    return {
      for (final v in Hive.box('LIBRP').values)
        if (v is Map && v['videoId'] is String) v['videoId'] as String: v,
    };
  }

  /// [id]'s song as a mix track: as Riff keeps it, else from its [title]
  /// and [artist] with YouTube's thumbnail. Null when it couldn't play from
  /// a mix: an episode or a book's chapter, or a song Riff no longer keeps
  /// that isn't on YouTube (a file on the phone, a cloud song).
  Map<String, dynamic>? track(String id, {String? title, String? artist}) {
    if (id.isEmpty || isLongFormId(id)) return null;
    Map? kept;
    for (final name in _byId) {
      if (!Hive.isBoxOpen(name)) continue;
      final v = Hive.box(name).get(id);
      if (v is Map && v['videoId'] == id) {
        kept = v;
        break;
      }
    }
    kept ??= _recent[id];
    if (kept != null) {
      return {
        for (final e in kept.entries)
          if (!_playContext.contains(e.key)) '${e.key}': e.value,
      };
    }
    if (!_videoId.hasMatch(id)) return null;
    return {
      'videoId': id,
      'title': title ?? id,
      'artists': [
        {'name': artist ?? ''}
      ],
      'thumbnails': [
        {'url': 'https://i.ytimg.com/vi/$id/hqdefault.jpg'}
      ],
    };
  }
}
