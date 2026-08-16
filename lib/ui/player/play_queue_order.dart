import 'package:audio_service/audio_service.dart';

/// Copy [songs] into a playable queue. When [shuffle] is true the copy is
/// shuffled in place so the original list (Hive / controller) stays stable.
List<MediaItem> playQueueFrom(
  Iterable<MediaItem> songs, {
  required bool shuffle,
}) {
  final list = List<MediaItem>.from(songs);
  if (shuffle) {
    list.shuffle();
  }
  return list;
}

/// True when the offline Songs tab should show Play all / Shuffle.
bool shouldShowLibrarySongsPlayBar({
  required bool cloudMode,
  required int songCount,
}) =>
    !cloudMode && songCount > 0;

/// Home discovery shelves play as a queue when more than one card is visible.
bool shouldPlayDiscoveryShelfAsQueue(int shelfLength) => shelfLength > 1;
