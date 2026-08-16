import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

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

/// Insert play-next items in reverse so they keep [songs] order after the
/// current track (each insert sits immediately after now-playing).
List<MediaItem> playNextBatchOrder(Iterable<MediaItem> songs) =>
    List<MediaItem>.from(songs).reversed.toList();

/// Sleep-timer "stop after this track" copy — episode for long-form.
String sleepEndLabelKey({required bool longForm}) =>
    longForm ? 'endOfThisEpisode' : 'endOfThisSong';

/// Volume icon for the 0–100 slider (mute / low / high).
IconData volumeIconFor(int volume) {
  if (volume <= 0) return Icons.volume_off;
  if (volume < 50) return Icons.volume_down;
  return Icons.volume_up;
}

