import 'package:audio_service/audio_service.dart';

/// Helpers for distinguishing YouTube Music *songs* from actual *videos*.
///
/// Songs (ATV) keep the classic square album-art player. Videos (OMV / UGC /
/// Search → Videos) can show an in-player 16:9 surface.
extension MediaItemVideoX on MediaItem {
  /// True for YouTube music videos / regular videos — not songs or podcasts.
  bool get isYoutubeVideo {
    final vt = '${extras?['videoType'] ?? ''}';
    if (vt.contains('PODCAST')) return false;
    if (vt == 'MUSIC_VIDEO_TYPE_ATV') return false;
    if (vt.isNotEmpty) return true;
    final rt = '${extras?['resultType'] ?? ''}'.toLowerCase();
    return rt == 'video';
  }
}

/// Same logic for maps / seeds that are not yet MediaItems.
bool looksLikeYoutubeVideo({String? videoType, String? resultType}) {
  final vt = videoType ?? '';
  if (vt.contains('PODCAST')) return false;
  if (vt == 'MUSIC_VIDEO_TYPE_ATV') return false;
  if (vt.isNotEmpty) return true;
  return (resultType ?? '').toLowerCase() == 'video';
}
