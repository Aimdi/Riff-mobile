import 'package:audio_service/audio_service.dart';

import '/services/podcast_progress_service.dart';

/// Newest in-progress episode, or null when the inbox is empty.
Map<String, dynamic>? latestPodcastContinue(
    List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return null;
  return rows.first;
}

/// Rebuild playable items from stored progress rows (newest first).
List<MediaItem> podcastContinueQueue(List<Map<String, dynamic>> rows) {
  final out = <MediaItem>[];
  for (final row in rows) {
    final item = PodcastProgressService.toMediaItem(row);
    if (item.id.isNotEmpty) out.add(item);
  }
  return out;
}

/// Hide the Home chip when there is nothing to resume, or that episode is
/// already the current track.
bool shouldShowPodcastContinueChip({
  required bool hasEpisode,
  required String? currentSongId,
  required String? continueEpisodeId,
}) {
  if (!hasEpisode) return false;
  final id = continueEpisodeId?.trim() ?? '';
  if (id.isEmpty) return false;
  return currentSongId != id;
}
