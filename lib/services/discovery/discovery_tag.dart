import 'package:audio_service/audio_service.dart';

import '../../models/playling_from.dart';
import 'discovery_types.dart';

/// Hive extras key for [DiscoverySource.wireName].
const String kDiscoverySourceExtra = 'discoverySource';

/// System / generated playlist ids that should not log as a generic playlist.
DiscoverySource sourceFromPlaylistId(String id) {
  switch (id) {
    case 'SongDownloads':
    case 'SongsCache':
    case 'LIBFAV':
      return DiscoverySource.downloads;
    case 'LIBRP':
      return DiscoverySource.home;
    default:
      if (id.startsWith('RIFF_')) return DiscoverySource.dailyMix;
      return DiscoverySource.playlist;
  }
}

/// Infer a source from the player "playing from" chip when none was tagged.
DiscoverySource sourceFromPlaylingFrom(PlaylingFrom? playfrom) {
  switch (playfrom?.type) {
    case PlaylingFromType.ALBUM:
      return DiscoverySource.album;
    case PlaylingFromType.PLAYLIST:
      return DiscoverySource.playlist;
    case PlaylingFromType.ARTIST:
      return DiscoverySource.artist;
    case PlaylingFromType.SELECTION:
    case null:
      return DiscoverySource.userClick;
  }
}

DiscoverySource sourceFromMediaItem(MediaItem item) =>
    DiscoverySource.fromWire(item.extras?[kDiscoverySourceExtra] as String?);

/// Stamp [fallback] only when extras has no source yet.
MediaItem ensureDiscoverySource(MediaItem item, DiscoverySource fallback) {
  final existing = item.extras?[kDiscoverySourceExtra];
  if (existing is String && existing.isNotEmpty) return item;
  final extras = Map<String, dynamic>.from(item.extras ?? {});
  extras[kDiscoverySourceExtra] = fallback.wireName;
  return item.copyWith(extras: extras);
}

List<MediaItem> ensureDiscoverySources(
  Iterable<MediaItem> items,
  DiscoverySource fallback,
) =>
    items.map((m) => ensureDiscoverySource(m, fallback)).toList();

/// Overwrite (or set) the source. Used by radio / similar / mix builders.
MediaItem withDiscoverySource(MediaItem item, DiscoverySource source) {
  final extras = Map<String, dynamic>.from(item.extras ?? {});
  extras[kDiscoverySourceExtra] = source.wireName;
  return item.copyWith(extras: extras);
}

List<MediaItem> withDiscoverySources(
  Iterable<MediaItem> items,
  DiscoverySource source,
) =>
    items.map((m) => withDiscoverySource(m, source)).toList();
