import 'package:audio_service/audio_service.dart';

/// Album browse id from song extras, if any.
String? songAlbumId(MediaItem? song) {
  final album = song?.extras?['album'];
  if (album is Map && album['id'] != null) {
    final id = '${album['id']}';
    if (id.isNotEmpty && id != 'null') return id;
  }
  return null;
}

/// First artist browse id from extras['artistId'] or extras['artists'].
String? songArtistId(MediaItem? song) {
  final extras = song?.extras;
  if (extras == null) return null;
  final direct = extras['artistId'];
  if (direct != null) {
    final id = '$direct';
    if (id.isNotEmpty && id != 'null') return id;
  }
  final artists = extras['artists'];
  if (artists is List) {
    for (final a in artists) {
      if (a is Map && a['id'] != null) {
        final id = '${a['id']}';
        if (id.isNotEmpty && id != 'null') return id;
      }
    }
  }
  return null;
}

/// One of a song's artists that has a page to open.
typedef SongArtistRef = ({String id, String name});

/// Every artist of [song] with a browse id, in credit order, once each
/// (extras['artists']; else extras['artistId'] with the song's artist line).
List<SongArtistRef> songArtists(MediaItem? song) {
  final extras = song?.extras;
  if (extras == null) return const [];
  String? clean(dynamic v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  final out = <SongArtistRef>[];
  final seen = <String>{};
  final artists = extras['artists'];
  if (artists is List) {
    for (final a in artists) {
      if (a is! Map) continue;
      final id = clean(a['id']);
      if (id == null || !seen.add(id)) continue;
      out.add((id: id, name: clean(a['name']) ?? song?.artist ?? ''));
    }
  }
  if (out.isEmpty) {
    final id = clean(extras['artistId']);
    if (id != null) out.add((id: id, name: song?.artist ?? ''));
  }
  return out;
}
