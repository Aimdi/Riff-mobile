import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'network_kind.dart';
import 'podcast_download_service.dart';
import 'podcast_library.dart';

/// Downloads what's in the podcast queue, as Pocket Casts' auto download
/// of Up Next: Off, On Wi-Fi (waits while on mobile data) or Always, for
/// the whole library. Episodes from feeds: YouTube ones have no file.
class PodcastQueueDownloads {
  PodcastQueueDownloads._();

  static const prefKey = 'podcastQueueDownload';

  /// Downloads one episode; tests swap it.
  static Future<bool> Function(MediaItem) downloader =
      PodcastDownloadService.download;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static NewEpisodesDownload get mode =>
      parseNewEpisodesDownload(_prefs?.get(prefKey));

  static Future<void> setMode(NewEpisodesDownload m) async {
    await _prefs?.put(prefKey, m.name);
    PodcastLibrary.rev.value++;
    if (m != NewEpisodesDownload.off) unawaited(run());
  }

  /// The queued episodes still to download, in queue order: from feeds,
  /// with a file, not downloaded yet.
  static List<MediaItem> pending(Iterable<MediaItem> queue) => [
        for (final e in queue)
          if (e.id.startsWith('podcast_') &&
              ((e.extras?['url'] as String?)?.isNotEmpty ?? false) &&
              !PodcastDownloadService.isDownloaded(e.id))
            e
      ];

  static bool _running = false;
  static bool _again = false;

  /// Downloads the [pending] episodes one after another, top of the queue
  /// first, while [mode] allows it (On Wi-Fi: not on mobile data). Asked
  /// again meanwhile, it looks at the queue once more when it's done.
  static Future<void> run() async {
    if (mode == NewEpisodesDownload.off ||
        !Get.isRegistered<PodcastQueueController>()) {
      return;
    }
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final queue = Get.find<PodcastQueueController>().queue;
        for (final e in pending(queue)) {
          final m = mode;
          if (m == NewEpisodesDownload.off) return;
          if (m == NewEpisodesDownload.wifi && await NetworkKind.isMetered()) {
            return;
          }
          // Taken out of the queue while the one before downloaded.
          if (!queue.any((q) => q.id == e.id)) continue;
          await downloader(e);
        }
      } while (_again);
    } finally {
      _running = false;
    }
  }
}
