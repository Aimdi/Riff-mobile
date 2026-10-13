import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'audiobook_progress_service.dart';

/// A saved moment in an audiobook, like Audible's bookmarks: the track
/// (its id and its place in the book) and the position in it.
class AudiobookBookmark {
  const AudiobookBookmark({
    required this.id,
    required this.bookId,
    required this.trackId,
    required this.trackIndex,
    required this.positionMs,
    required this.createdAt,
    this.trackTitle = '',
  });

  final String id;
  final String bookId;
  final String trackId;

  /// The track's place in the book (0 = first).
  final int trackIndex;
  final int positionMs;
  final int createdAt;
  final String trackTitle;

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'trackId': trackId,
        'trackIndex': trackIndex,
        'positionMs': positionMs,
        'createdAt': createdAt,
        'trackTitle': trackTitle,
      };

  static AudiobookBookmark? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final bookId = value['bookId'];
    final trackId = value['trackId'];
    final position = value['positionMs'];
    if (id is! String || bookId is! String || trackId is! String) return null;
    if (position is! int) return null;
    final index = value['trackIndex'];
    final created = value['createdAt'];
    return AudiobookBookmark(
      id: id,
      bookId: bookId,
      trackId: trackId,
      trackIndex: index is int ? index : 0,
      positionMs: position,
      createdAt: created is int ? created : 0,
      trackTitle: '${value['trackTitle'] ?? ''}',
    );
  }
}

/// Reading order: by track, then by position in it.
int compareAudiobookBookmarks(AudiobookBookmark a, AudiobookBookmark b) {
  final byTrack = a.trackIndex.compareTo(b.trackIndex);
  return byTrack != 0 ? byTrack : a.positionMs.compareTo(b.positionMs);
}

/// Audiobook bookmarks in box `AudiobookBookmarks`, keyed by bookmark id.
class AudiobookBookmarkStore {
  AudiobookBookmarkStore._();

  static const box = 'AudiobookBookmarks';

  /// Bumped on every change, for Obx.
  static final rev = 0.obs;

  static Box? get _box => Hive.isBoxOpen(box) ? Hive.box(box) : null;

  /// [bookId]'s bookmarks in reading order.
  static List<AudiobookBookmark> forBook(String bookId) {
    final b = _box;
    if (b == null) return const [];
    return [
      for (final v in b.values)
        if (AudiobookBookmark.fromJson(v) case final bm?
            when bm.bookId == bookId)
          bm
    ]..sort(compareAudiobookBookmarks);
  }

  /// Saves [position] in [track], the book's track number [trackIndex].
  /// Null when [track] isn't a book's or storage is closed.
  static Future<AudiobookBookmark?> add(MediaItem track, Duration position,
      {required int trackIndex, DateTime? now}) async {
    final b = _box;
    final bookId = AudiobookProgressService.bookIdOf(track);
    if (b == null || bookId == null) return null;
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final bm = AudiobookBookmark(
      id: '${track.id}_$at',
      bookId: bookId,
      trackId: track.id,
      trackIndex: math.max(0, trackIndex),
      positionMs: math.max(0, position.inMilliseconds),
      createdAt: at,
      trackTitle: track.title,
    );
    await b.put(bm.id, bm.toJson());
    rev.value++;
    return bm;
  }

  /// Gone from [forBook] at once (Hive drops it from memory before
  /// writing), then stored.
  static Future<void> remove(String id) async {
    final stored = _box?.delete(id);
    rev.value++;
    await stored;
    rev.value++;
  }

  /// Puts a removed bookmark back (Undo).
  static Future<void> restore(AudiobookBookmark bm) async {
    await _box?.put(bm.id, bm.toJson());
    rev.value++;
  }
}
