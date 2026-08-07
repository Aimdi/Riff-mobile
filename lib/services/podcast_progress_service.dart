import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/ui/screens/Podcasts/podcast_queue_controller.dart';

/// Tracks per-episode playback position for podcasts so episodes can be resumed
/// ("Continue" section) and show a progress bar. Stored in the `PodcastProgress`
/// Hive box keyed by episode id. Finished episodes move to `PodcastPlayed`.
class PodcastProgressService {
  PodcastProgressService._();

  static Box get _box => Hive.box('PodcastProgress');
  static Box? get _playedBox =>
      Hive.isBoxOpen('PodcastPlayed') ? Hive.box('PodcastPlayed') : null;

  /// A podcast episode from either backend: iTunes/RSS (`podcast_` id) or
  /// YouTube Music (videoId id but flagged via extras['isPodcast']).
  static bool isPodcastItem(MediaItem item) =>
      item.id.startsWith('podcast_') || item.extras?['isPodcast'] == true;

  /// True for a URL that is only meaningful on this device — a downloaded copy
  /// substituted at playback time.
  static bool isLocalUrl(String? url) =>
      url != null && (url.startsWith('file://') || url.startsWith('/'));

  /// The URL worth persisting for an episode. Playing a downloaded episode
  /// rewrites `extras['url']` to a `file://` path, which becomes a dead link as
  /// soon as the download is removed (or after a data restore), so prefer the
  /// stashed remote enclosure URL and never persist a local path — falling back
  /// to whatever was stored for that episode before.
  static String? storableUrl(
      {String? remoteUrl, String? currentUrl, String? previousUrl}) {
    for (final candidate in [remoteUrl, currentUrl, previousUrl]) {
      if (candidate != null && candidate.isNotEmpty && !isLocalUrl(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  /// Persist the current position of a playing podcast episode. Clears the
  /// record once the episode is (nearly) finished; ignores the first 15s.
  static void save(MediaItem? episode, Duration position, Duration? total,
      {int nowMs = 0}) {
    if (episode == null || !isPodcastItem(episode)) return;
    if (!Hive.isBoxOpen('PodcastProgress')) return;
    final posMs = position.inMilliseconds;
    final totMs = (total?.inMilliseconds ?? 0) > 0
        ? total!.inMilliseconds
        : (episode.duration?.inMilliseconds ?? 0);
    if (totMs <= 0) return;
    // Finished (last 20s or ≥98%) → mark played + drop in-progress.
    if (posMs >= totMs - 20000 || posMs >= totMs * 0.98) {
      markPlayed(episode.id);
      return;
    }
    if (posMs < 15000) return; // barely started
    // Resuming an episode clears played state.
    _playedBox?.delete(episode.id);
    final previous = _box.get(episode.id);
    _box.put(episode.id, {
      'id': episode.id,
      'title': episode.title,
      'artist': episode.artist,
      'artUri': episode.artUri?.toString(),
      'url': storableUrl(
        remoteUrl: episode.extras?['remoteUrl']?.toString(),
        currentUrl: episode.extras?['url']?.toString(),
        previousUrl: previous is Map ? previous['url']?.toString() : null,
      ),
      'feedUrl': episode.extras?['feedUrl'],
      'description': episode.extras?['description'],
      'chaptersUrl': episode.extras?['chaptersUrl'],
      'transcriptUrl': episode.extras?['transcriptUrl'],
      'transcriptType': episode.extras?['transcriptType'],
      'positionMs': posMs,
      'durationMs': totMs,
      'updatedAt': nowMs,
    });
  }

  static bool isPlayed(String id) {
    final box = _playedBox;
    if (box == null) return false;
    return box.containsKey(id);
  }

  static void markPlayed(String id) {
    if (Hive.isBoxOpen('PodcastProgress')) _box.delete(id);
    final box = _playedBox;
    if (box != null) {
      box.put(id, DateTime.now().millisecondsSinceEpoch);
    }
    // Idempotent: clear from Up Next when finished or manually marked played.
    if (Get.isRegistered<PodcastQueueController>()) {
      Get.find<PodcastQueueController>().removeById(id);
    }
  }

  static void markUnplayed(String id) {
    _playedBox?.delete(id);
  }

  static int? positionMs(String id) {
    if (!Hive.isBoxOpen('PodcastProgress')) return null;
    final r = _box.get(id);
    if (r is Map && r['positionMs'] is int) return r['positionMs'] as int;
    return null;
  }

  /// 0..1 played fraction, or null if unknown.
  static double? progress(String id) {
    final r = _box.get(id);
    if (r is Map && r['positionMs'] is int && r['durationMs'] is int) {
      final d = r['durationMs'] as int;
      if (d > 0) return ((r['positionMs'] as int) / d).clamp(0.0, 1.0);
    }
    return null;
  }

  /// Seconds still left on an in-progress episode, or null if unknown/finished.
  static int? remainingSec(String id, {int? fallbackDurationSec}) {
    if (!Hive.isBoxOpen('PodcastProgress')) {
      return fallbackDurationSec != null && fallbackDurationSec > 0
          ? fallbackDurationSec
          : null;
    }
    final r = _box.get(id);
    if (r is Map && r['positionMs'] is int && r['durationMs'] is int) {
      final leftMs = (r['durationMs'] as int) - (r['positionMs'] as int);
      if (leftMs <= 0) return 0;
      return (leftMs / 1000).round();
    }
    if (fallbackDurationSec != null && fallbackDurationSec > 0) {
      return fallbackDurationSec;
    }
    return null;
  }

  static void clear(String id) {
    if (Hive.isBoxOpen('PodcastProgress')) _box.delete(id);
  }

  /// Mark played (AntennaPod-style) — removes resume row and flags as finished.
  static void markAsPlayed(String id) => markPlayed(id);

  /// In-progress episodes, newest first, as stored maps.
  static List<Map<String, dynamic>> inProgress() {
    if (!Hive.isBoxOpen('PodcastProgress')) return [];
    final list = _box.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    list.sort((a, b) =>
        ((b['updatedAt'] ?? 0) as int).compareTo((a['updatedAt'] ?? 0) as int));
    return list;
  }

  /// Rebuild a playable MediaItem from a stored progress record.
  static MediaItem toMediaItem(Map<String, dynamic> r) => MediaItem(
        id: '${r['id']}',
        title: '${r['title'] ?? ''}',
        artist: r['artist']?.toString(),
        duration: (r['durationMs'] is int)
            ? Duration(milliseconds: r['durationMs'] as int)
            : null,
        artUri: r['artUri'] != null ? Uri.tryParse('${r['artUri']}') : null,
        extras: {
          'url': storableUrl(
            remoteUrl: r['remoteUrl']?.toString(),
            currentUrl: r['url']?.toString(),
          ),
          'isPodcast': true,
          if (r['feedUrl'] != null) 'feedUrl': r['feedUrl'],
          if (r['description'] != null) 'description': r['description'],
          if (r['chaptersUrl'] != null) 'chaptersUrl': r['chaptersUrl'],
          if (r['transcriptUrl'] != null) 'transcriptUrl': r['transcriptUrl'],
          if (r['transcriptUrl'] != null)
            'transcriptType': r['transcriptType'],
        },
      );
}
