import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

/// Tracks playback position for Audiobookshelf tracks so a book can be resumed
/// where the listener left off. Stored in the `AudiobookProgress` Hive box,
/// keyed by track id (`abs_<bookId>_<trackIndex>`).
///
/// Audiobooks are hours long and split into one [MediaItem] per track, so
/// losing the position means restarting a chapter — a far worse failure than
/// it is for music. Podcasts already had [PodcastProgressService]; audiobooks
/// had nothing, and neither the local position nor the server-side sync was
/// ever recorded.
///
/// Kept deliberately parallel to `PodcastProgressService` rather than merged
/// with it: the podcast "Continue" list in the inbox reads that box directly,
/// and audiobook chapters do not belong in it.
class AudiobookProgressService {
  AudiobookProgressService._();

  static const String boxName = 'AudiobookProgress';

  static Box get _box => Hive.box(boxName);

  /// Audiobookshelf tracks carry the `abs_` prefix (see
  /// `AudiobookshelfService.toMediaItems`), which is also what makes
  /// `MyAudioHandler.checkNGetUrl` skip YouTube stream resolution.
  static bool isAudiobookItem(MediaItem item) => item.id.startsWith('abs_');

  /// The owning book's id, recovered from `extras['absItemId']` when present
  /// and otherwise from the `abs_<bookId>_<trackIndex>` id shape. Returns null
  /// when neither is available.
  static String? bookIdOf(MediaItem item) {
    final fromExtras = item.extras?['absItemId'];
    if (fromExtras is String && fromExtras.isNotEmpty) return fromExtras;
    if (!item.id.startsWith('abs_')) return null;
    final rest = item.id.substring(4);
    final lastSep = rest.lastIndexOf('_');
    if (lastSep <= 0) return null;
    return rest.substring(0, lastSep);
  }

  /// True once [posMs] is far enough into a track of [totMs] to count as
  /// finished, at which point the record is dropped so the next play starts
  /// clean. Pure so it can be tested without Hive.
  static bool isFinished(int posMs, int totMs) =>
      totMs > 0 && (posMs >= totMs - 20000 || posMs >= totMs * 0.98);

  /// True when [posMs] is too early to be worth storing — a stray tap should
  /// not overwrite a real position with ~0.
  static bool isTooEarly(int posMs) => posMs < 15000;

  /// Seconds of book preceding [track], stamped by
  /// `AudiobookshelfService.toMediaItems`. Null when unknown, which must be
  /// treated as "cannot report a book position" rather than as offset 0 —
  /// guessing 0 would rewind the listener to chapter 1 on the server.
  static double? startOffsetSec(MediaItem track) {
    final v = track.extras?['absStartOffset'];
    return v is num ? v.toDouble() : null;
  }

  /// Total book length in seconds, or null when unknown.
  static double? bookDurationSec(MediaItem track) {
    final v = track.extras?['absBookDuration'];
    return (v is num && v > 0) ? v.toDouble() : null;
  }

  /// The Audiobookshelf session id this track belongs to, if any.
  static String? sessionIdOf(MediaItem track) {
    final v = track.extras?['absSessionId'];
    return (v is String && v.isNotEmpty) ? v : null;
  }

  /// Convert a position *within a track* to a position within the whole book.
  /// Returns null when the offset is unknown, so callers skip the sync rather
  /// than report a wrong place.
  static double? bookPositionSec(MediaItem track, Duration positionInTrack) {
    final offset = startOffsetSec(track);
    if (offset == null) return null;
    final pos = offset + (positionInTrack.inMilliseconds / 1000.0);
    return pos < 0 ? 0 : pos;
  }

  /// Which track a whole-book position falls in, and how far into it.
  ///
  /// The inverse of the `absStartOffset` stamping in
  /// `AudiobookshelfService.toMediaItems`: Audiobookshelf reports one position
  /// for the entire book, but Riff plays a queue of per-track items, so opening
  /// a book needs that position mapped back to a track.
  ///
  /// Returns index 0 / offset 0 when there is nothing to resume, so callers can
  /// use the result unconditionally. Positions past the end of the book clamp
  /// to the last track rather than running off the list.
  static ({int index, double offsetSec}) resolveTrackForBookPosition(
      List<double> trackDurations, double bookPositionSec) {
    if (trackDurations.isEmpty || bookPositionSec <= 0) {
      return (index: 0, offsetSec: 0);
    }
    var remaining = bookPositionSec;
    for (var i = 0; i < trackDurations.length; i++) {
      final d = trackDurations[i];
      // A zero/unknown-length track cannot contain the position; step over it
      // rather than dividing the book at a point that does not exist.
      if (d <= 0) continue;
      if (remaining < d) return (index: i, offsetSec: remaining);
      remaining -= d;
    }
    final lastPlayable = trackDurations.lastIndexWhere((d) => d > 0);
    final idx = lastPlayable < 0 ? trackDurations.length - 1 : lastPlayable;
    return (index: idx, offsetSec: 0);
  }

  /// Minimum gap between server syncs. Deliberately longer than the 5s local
  /// save: these land on someone's self-hosted box, and losing at most 15s of
  /// position on a crash is a fair trade for not hammering it.
  static const int serverSyncIntervalMs = 15000;

  static bool shouldSyncServer(int lastSyncMs, int nowMs) =>
      nowMs - lastSyncMs >= serverSyncIntervalMs;

  /// Persist the position of a playing audiobook track. Drops the record once
  /// the track is (nearly) finished and ignores the first 15s.
  static void save(MediaItem? track, Duration position, Duration? total,
      {required int nowMs}) {
    if (track == null || !isAudiobookItem(track)) return;
    if (!Hive.isBoxOpen(boxName)) return;
    final posMs = position.inMilliseconds;
    final totMs = (total?.inMilliseconds ?? 0) > 0
        ? total!.inMilliseconds
        : (track.duration?.inMilliseconds ?? 0);
    if (totMs <= 0) return;
    if (isFinished(posMs, totMs)) {
      _box.delete(track.id);
      return;
    }
    if (isTooEarly(posMs)) return;
    _box.put(track.id, {
      'id': track.id,
      'bookId': bookIdOf(track),
      'title': track.title,
      'album': track.album,
      'artist': track.artist,
      'artUri': track.artUri?.toString(),
      'url': track.extras?['url'],
      'trackIndex': track.extras?['absTrackIndex'],
      'positionMs': posMs,
      'durationMs': totMs,
      'updatedAt': nowMs,
    });
  }

  static int? positionMs(String id) {
    if (!Hive.isBoxOpen(boxName)) return null;
    final r = _box.get(id);
    if (r is Map && r['positionMs'] is int) return r['positionMs'] as int;
    return null;
  }

  /// 0..1 played fraction of a single track, or null if unknown.
  static double? progress(String id) {
    if (!Hive.isBoxOpen(boxName)) return null;
    final r = _box.get(id);
    if (r is Map && r['positionMs'] is int && r['durationMs'] is int) {
      final d = r['durationMs'] as int;
      if (d > 0) return ((r['positionMs'] as int) / d).clamp(0.0, 1.0);
    }
    return null;
  }

  static void clear(String id) {
    if (Hive.isBoxOpen(boxName)) _box.delete(id);
  }

  /// The most recently played stored track for [bookId], so a book reopened
  /// from the library can resume on the right chapter rather than track 1.
  static Map<String, dynamic>? lastTrackForBook(String bookId) {
    if (!Hive.isBoxOpen(boxName)) return null;
    Map<String, dynamic>? best;
    for (final v in _box.values) {
      if (v is! Map) continue;
      if (v['bookId'] != bookId) continue;
      final m = Map<String, dynamic>.from(v);
      if (best == null ||
          ((m['updatedAt'] ?? 0) as int) > ((best['updatedAt'] ?? 0) as int)) {
        best = m;
      }
    }
    return best;
  }

  /// In-progress audiobook tracks, newest first.
  static List<Map<String, dynamic>> inProgress() {
    if (!Hive.isBoxOpen(boxName)) return [];
    final list = _box.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    list.sort((a, b) =>
        ((b['updatedAt'] ?? 0) as int).compareTo((a['updatedAt'] ?? 0) as int));
    return list;
  }
}
