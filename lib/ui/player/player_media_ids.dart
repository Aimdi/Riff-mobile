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
