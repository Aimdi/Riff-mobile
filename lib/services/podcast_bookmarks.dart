import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'podcast_progress_service.dart';
import 'podcast_segments.dart' show formatSegmentLength;

/// A saved moment in a podcast episode: where, what was said, and an
/// optional note. Carries enough of the episode to play it again from the
/// Bookmarks list.
class PodcastBookmark {
  const PodcastBookmark({
    required this.id,
    required this.episodeId,
    required this.positionMs,
    required this.createdAt,
    this.quote = '',
    this.note,
    this.episodeTitle = '',
    this.showTitle = '',
    this.episode = const {},
    this.updatedAt,
  });

  final String id;
  final String episodeId;
  final int positionMs;
  final int createdAt;
  final String quote;
  final String? note;
  final String episodeTitle;
  final String showTitle;

  /// Playable snapshot of the episode ([episodeSnapshot]).
  final Map<String, dynamic> episode;

  /// Last change after it was made (a note edit), for sync. Null when
  /// unchanged since [createdAt].
  final int? updatedAt;

  PodcastBookmark copyWith(
          {String? note, bool clearNote = false, int? updatedAt}) =>
      PodcastBookmark(
        id: id,
        episodeId: episodeId,
        positionMs: positionMs,
        createdAt: createdAt,
        quote: quote,
        note: clearNote ? null : (note ?? this.note),
        episodeTitle: episodeTitle,
        showTitle: showTitle,
        episode: episode,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'episodeId': episodeId,
        'positionMs': positionMs,
        'createdAt': createdAt,
        'quote': quote,
        if (note != null) 'note': note,
        'episodeTitle': episodeTitle,
        'showTitle': showTitle,
        'episode': episode,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };

  /// Null for anything that isn't a stored bookmark.
  static PodcastBookmark? fromJson(dynamic j) {
    if (j is! Map) return null;
    final id = j['id'];
    final ep = j['episodeId'];
    final pos = j['positionMs'];
    if (id is! String || ep is! String || ep.isEmpty || pos is! num) {
      return null;
    }
    final created = j['createdAt'];
    final note = j['note'];
    final snap = j['episode'];
    final updated = j['updatedAt'];
    return PodcastBookmark(
      id: id,
      episodeId: ep,
      positionMs: pos.toInt() < 0 ? 0 : pos.toInt(),
      createdAt: created is num ? created.toInt() : 0,
      quote: '${j['quote'] ?? ''}',
      note: note is String && note.trim().isNotEmpty ? note : null,
      episodeTitle: '${j['episodeTitle'] ?? ''}',
      showTitle: '${j['showTitle'] ?? ''}',
      episode: snap is Map ? Map<String, dynamic>.from(snap) : const {},
      updatedAt: updated is num && updated > 0 ? updated.toInt() : null,
    );
  }
}

/// "“quote” — Show, Episode @ 12:34" for sharing. Without a quote it's
/// just "Show, Episode @ 12:34".
String formatBookmarkShare(PodcastBookmark b) {
  final at = formatSegmentLength(b.positionMs / 1000);
  final where = [b.showTitle, b.episodeTitle]
      .where((s) => s.trim().isNotEmpty)
      .join(', ');
  final tail = where.isEmpty ? '@ $at' : '$where @ $at';
  final q = b.quote.trim();
  return q.isEmpty ? tail : '“$q” — $tail';
}

/// What's kept of an episode so a bookmark can play it later: the
/// MediaItem's basics and its plain-valued extras. A downloaded episode's
/// local file path is swapped for its remote URL (the download may go).
Map<String, dynamic> episodeSnapshot(MediaItem item) {
  final extras = <String, dynamic>{
    for (final e in (item.extras ?? const <String, dynamic>{}).entries)
      if (e.value is String || e.value is num || e.value is bool)
        e.key: e.value,
  };
  final url = PodcastProgressService.storableUrl(
    remoteUrl: extras['remoteUrl']?.toString(),
    currentUrl: extras['url']?.toString(),
  );
  if (url != null) {
    extras['url'] = url;
  } else {
    extras.remove('url');
  }
  // Long show notes aren't needed to play it again.
  extras.remove('description');
  return {
    'id': item.id,
    'title': item.title,
    if (item.artist != null) 'artist': item.artist,
    if (item.artUri != null) 'artUri': item.artUri.toString(),
    if (item.duration != null) 'durationMs': item.duration!.inMilliseconds,
    'extras': extras,
  };
}

/// Rebuild a playable MediaItem from [episodeSnapshot]. Null if the
/// snapshot is missing or broken.
MediaItem? mediaItemFromSnapshot(Map<String, dynamic> s) {
  final id = s['id'];
  if (id is! String || id.isEmpty) return null;
  final extras = s['extras'];
  final dur = s['durationMs'];
  final art = s['artUri'];
  return MediaItem(
    id: id,
    title: '${s['title'] ?? ''}',
    artist: s['artist']?.toString(),
    duration: dur is int && dur > 0 ? Duration(milliseconds: dur) : null,
    artUri: art is String ? Uri.tryParse(art) : null,
    extras: {
      if (extras is Map) ...Map<String, dynamic>.from(extras),
      'isPodcast': true,
    },
  );
}

/// Newest first, for the Bookmarks list.
List<PodcastBookmark> sortBookmarksNewest(Iterable<PodcastBookmark> all) =>
    all.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

/// In playback order, for one episode's list.
List<PodcastBookmark> sortBookmarksByPosition(
        Iterable<PodcastBookmark> all) =>
    all.toList()..sort((a, b) => a.positionMs.compareTo(b.positionMs));

/// Bookmarks in box `PodcastBookmarks`, keyed by bookmark id.
class PodcastBookmarkStore {
  PodcastBookmarkStore._();

  static const box = 'PodcastBookmarks';

  /// Bumped on every change, for Obx.
  static final rev = 0.obs;

  static Box? get _box => Hive.isBoxOpen(box) ? Hive.box(box) : null;

  static List<PodcastBookmark> get all {
    final b = _box;
    if (b == null) return const [];
    return sortBookmarksNewest([
      for (final v in b.values)
        if (PodcastBookmark.fromJson(v) case final bm?) bm
    ]);
  }

  static List<PodcastBookmark> forEpisode(String episodeId) =>
      sortBookmarksByPosition(all.where((b) => b.episodeId == episodeId));

  /// Save a moment of [item] at [position]. Null when storage is closed.
  static Future<PodcastBookmark?> add(MediaItem item, Duration position,
      {String quote = '', String? note, DateTime? now}) async {
    final b = _box;
    if (b == null) return null;
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final bm = PodcastBookmark(
      id: '${item.id}_$at',
      episodeId: item.id,
      positionMs: position.inMilliseconds < 0 ? 0 : position.inMilliseconds,
      createdAt: at,
      quote: quote.trim(),
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      episodeTitle: item.title,
      showTitle: item.artist ?? '',
      episode: episodeSnapshot(item),
    );
    await b.put(bm.id, bm.toJson());
    rev.value++;
    return bm;
  }

  static Future<void> setNote(PodcastBookmark bm, String note,
      {DateTime? now}) async {
    final b = _box;
    if (b == null) return;
    final n = note.trim();
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    await b.put(
        bm.id,
        (n.isEmpty
                ? bm.copyWith(clearNote: true, updatedAt: at)
                : bm.copyWith(note: n, updatedAt: at))
            .toJson());
    rev.value++;
  }

  static Future<void> remove(String id) async {
    await _box?.delete(id);
    rev.value++;
  }

  /// Put a removed bookmark back (Undo).
  static Future<void> restore(PodcastBookmark bm) async {
    await _box?.put(bm.id, bm.toJson());
    rev.value++;
  }
}
