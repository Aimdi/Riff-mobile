import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

import '/services/audiobook_downloads.dart';
import '/services/audiobook_progress_service.dart';
import '/services/audiobookshelf_service.dart';
import '/services/free_audiobook_service.dart';
import '/services/discovery/discovery_types.dart';
import '/services/offline_playback.dart';
import '/ui/player/player_controller.dart';

/// Library tiles play the book; long-press still opens detail.
bool shouldPlayAudiobookOnTap() => true;

/// Play an Audiobookshelf book from [bookId], resuming local/server position
/// unless [index] picks a chapter. Returns false so the caller can open detail.
/// Downloaded, it plays from the phone when there's no connection or the
/// server can't be reached.
Future<bool> playAudiobook({
  required String bookId,
  int? index,
}) async {
  if (!Get.isRegistered<PlayerController>()) return false;
  if (!Get.isRegistered<AudiobookshelfService>() ||
      (OfflinePlayback.noConnection.isTrue &&
          AudiobookDownloads.isDownloaded(bookId))) {
    return playDownloadedAudiobook(bookId, index: index);
  }
  try {
    final abs = Get.find<AudiobookshelfService>();
    final detail = await abs.openBook(bookId);
    if (detail.tracks.isEmpty) return false;
    final items = abs.toMediaItems(detail);
    if (items.isEmpty) return false;

    var start = 0;
    var resumeMs = 0;
    if (index != null) {
      start = index.clamp(0, items.length - 1);
    } else {
      final local = AudiobookProgressService.lastTrackForBook(detail.id);
      final at = local == null
          ? -1
          : items.indexWhere((m) => m.id == local['id']?.toString());
      if (at >= 0 && local != null) {
        start = at;
        final pos = local['positionMs'];
        if (pos is int) resumeMs = pos;
      } else {
        final mapped = AudiobookshelfService.mapCurrentTimeToTrack(
          detail.currentTime,
          detail.tracks.map((t) => t.duration).toList(),
        );
        start = mapped.$1.clamp(0, items.length - 1);
        resumeMs = mapped.$2.inMilliseconds;
      }
    }

    final player = Get.find<PlayerController>();
    if (resumeMs > 1500) {
      player.armResume(items[start].id, resumeMs);
    }
    return player.playPlayListSong(
      items,
      start,
      source: DiscoverySource.audiobook,
    );
  } catch (_) {
    // The server out of reach: a downloaded book plays from the phone.
    return playDownloadedAudiobook(bookId, index: index);
  }
}

/// Play a free (LibriVox) book, resuming the last chapter and position
/// unless [index] picks a chapter.
Future<bool> playFreeAudiobook(FreeAudiobookDetail detail, {int? index}) =>
    _playChapters(FreeAudiobookService.toMediaItems(detail), detail.book.id,
        index: index);

/// Play the downloaded book [bookId] from the phone, with no server or
/// connection, resuming the last chapter and position unless [index] picks
/// a chapter. False when it isn't downloaded.
Future<bool> playDownloadedAudiobook(String bookId, {int? index}) =>
    _playChapters(AudiobookDownloads.chapters(bookId) ?? const [], bookId,
        index: index);

Future<bool> _playChapters(List<MediaItem> items, String bookId,
    {int? index}) async {
  if (!Get.isRegistered<PlayerController>()) return false;
  if (items.isEmpty) return false;
  var start = 0;
  var resumeMs = 0;
  if (index != null) {
    start = index.clamp(0, items.length - 1);
    resumeMs = AudiobookProgressService.positionMs(items[start].id) ?? 0;
  } else {
    final local = AudiobookProgressService.lastTrackForBook(bookId);
    final at = local == null
        ? -1
        : items.indexWhere((m) => m.id == local['id']?.toString());
    if (at >= 0) {
      start = at;
      final pos = local!['positionMs'];
      if (pos is int) resumeMs = pos;
    }
  }
  final player = Get.find<PlayerController>();
  if (resumeMs > 1500) player.armResume(items[start].id, resumeMs);
  return player.playPlayListSong(items, start,
      source: DiscoverySource.audiobook);
}
