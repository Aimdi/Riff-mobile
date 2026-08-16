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

/// Enqueue is a no-op when the song is already in the queue.
bool isAlreadyQueued({
  required String songId,
  required Iterable<String> queueIds,
}) =>
    queueIds.contains(songId);

/// Queue mutations need a live audio handler.
bool canMutateQueue(bool audioReady) => audioReady;

/// Play / radio needs a live handler and at least one item.
bool canStartPlayback({
  required bool audioReady,
  required int itemCount,
}) =>
    audioReady && itemCount > 0;

/// Home continue chip needs a live handler and a non-empty saved queue.
bool canResumeSavedSession({
  required bool audioReady,
  required int savedQueueLength,
}) =>
    audioReady && savedQueueLength > 0;

/// Sleep timer needs a positive duration.
bool canArmSleepTimer(int minutes) => minutes > 0;

/// Play Next is a no-op when the song is current or already next.
bool isPlayNextNoOp({
  required String songId,
  required List<String> queueIds,
  required int currentIndex,
}) {
  if (queueIds.isEmpty) return false;
  if (currentIndex < 0 || currentIndex >= queueIds.length) return false;
  if (queueIds[currentIndex] == songId) return true;
  if (currentIndex + 1 < queueIds.length &&
      queueIds[currentIndex + 1] == songId) {
    return true;
  }
  return false;
}

/// Keep radio on when a continuation lands on an empty queue.
bool shouldKeepRadioWhenEnqueueing({
  required bool radioOn,
  required bool queueEmpty,
}) =>
    radioOn && queueEmpty;

/// Search tab: prefer the filtered list, then the widget items, then overview.
List<T> searchTabPlaySongs<T>({
  required Iterable<dynamic> items,
  Iterable<dynamic>? filtered,
  Iterable<dynamic>? overview,
}) {
  final fromFiltered = (filtered ?? const []).whereType<T>().toList();
  if (fromFiltered.isNotEmpty) return fromFiltered;
  final fromItems = items.whereType<T>().toList();
  if (fromItems.isNotEmpty) return fromItems;
  return (overview ?? const []).whereType<T>().toList();
}

/// Filter fetch failed — reuse overview results instead of an empty tab.
List searchTabFallback({required dynamic overview}) {
  if (overview is List && overview.isNotEmpty) return List.from(overview);
  return [];
}

/// Last track and radio is off — Skip should retry, not pause and hide the error.
bool shouldRetryInsteadOfSkip({
  required bool hasNext,
  required bool radioOn,
}) =>
    !hasNext && !radioOn;

/// Save-queue button is a no-op when nothing is playing.
bool canSaveQueueAsPlaylist(int queueLength) => queueLength > 0;

/// Prefill when saving the queue (or adding many songs) to a new playlist.
String defaultNewPlaylistName({
  required List<MediaItem>? songItems,
  DateTime? now,
}) {
  if (songItems == null || songItems.isEmpty) return '';
  if (songItems.length == 1) return songItems.first.title;
  final d = now ?? DateTime.now();
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  final lead = songItems.first.title.trim();
  if (lead.isEmpty) return '${d.year}-$mm-$dd';
  return '$lead · ${d.year}-$mm-$dd';
}

/// Hive has not finished the like/unlike write — keep the optimistic heart.
bool shouldKeepOptimisticFav({
  required String? currentSongId,
  required String? persistSongId,
}) =>
    currentSongId != null &&
    currentSongId.isNotEmpty &&
    currentSongId == persistSongId;

