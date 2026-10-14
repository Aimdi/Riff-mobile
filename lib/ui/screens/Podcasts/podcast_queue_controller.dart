import 'dart:async';
import 'dart:math';

import '/services/podcast_queue_downloads.dart';
import '/services/podcast_service.dart';
import '/ui/player/long_form_queue.dart';
import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Orders the queue can be put in, once, as AntennaPod sorts its queue.
enum PodcastQueueSort { newest, oldest, shortest, longest, show, shuffle }

/// When [episode] came out (epoch ms): as kept, else read from its date
/// ("5 Mar 2026"); 0 when unknown.
int queuedEpisodeReleasedMs(MediaItem episode) {
  final ms = episode.extras?['pubDateMs'];
  if (ms is int && ms > 0) return ms;
  final date = episode.extras?['date'];
  return date is String ? PodcastService.pubDateMs(date) : 0;
}

/// [items] in [sort]'s order. Episodes it can't tell apart (the same show,
/// the same date or length, or no date or length, which go last) keep the
/// order they were in.
List<MediaItem> sortedQueue(List<MediaItem> items, PodcastQueueSort sort,
    {Random? random}) {
  if (sort == PodcastQueueSort.shuffle) return items.toList()..shuffle(random);
  int released(MediaItem e) => queuedEpisodeReleasedMs(e);
  int length(MediaItem e) => e.duration?.inMilliseconds ?? 0;
  String show(MediaItem e) => (e.artist ?? '').trim().toLowerCase();
  // Unknown (0) after every known value, whichever way known ones go.
  int known(int a, int b, {required bool ascending}) {
    if (a <= 0 || b <= 0) return (a <= 0 ? 1 : 0) - (b <= 0 ? 1 : 0);
    return ascending ? a.compareTo(b) : b.compareTo(a);
  }

  int compare(MediaItem a, MediaItem b) => switch (sort) {
        PodcastQueueSort.newest =>
          known(released(a), released(b), ascending: false),
        PodcastQueueSort.oldest =>
          known(released(a), released(b), ascending: true),
        PodcastQueueSort.shortest =>
          known(length(a), length(b), ascending: true),
        PodcastQueueSort.longest =>
          known(length(a), length(b), ascending: false),
        PodcastQueueSort.show => show(a).compareTo(show(b)),
        PodcastQueueSort.shuffle => 0,
      };
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// A manually-curated podcast play queue ("Queue" / AntennaPod's
/// "Warteschlange"): episodes you add via long-press, played in order.
/// Persisted as an ordered list in the "PodcastQueue" Hive box.
class PodcastQueueController extends GetxController {
  final queue = <MediaItem>[].obs;

  static const _key = 'items';

  Box get _box => Hive.box('PodcastQueue');

  @override
  void onInit() {
    super.onInit();
    _load();
    // Queued while on mobile data, or before downloads were switched on.
    unawaited(PodcastQueueDownloads.run());
  }

  void _load() {
    final raw = _box.get(_key);
    if (raw is List) {
      queue.assignAll(raw
          .whereType<Map>()
          .map((m) => _fromMap(Map<String, dynamic>.from(m)))
          .toList());
    }
  }

  void _persist() {
    _box.put(_key, queue.map(_toMap).toList());
  }

  bool isQueued(String id) => queue.any((e) => e.id == id);

  /// Total time of everything still in the queue.
  Duration get totalTime => queue.fold(
      Duration.zero, (sum, e) => sum + (e.duration ?? Duration.zero));

  void add(MediaItem item) {
    if (isQueued(item.id)) return;
    queue.add(item);
    _persist();
    unawaited(PodcastQueueDownloads.run());
  }

  /// Put [item] back at [index] (Undo), or at the end if that's past it.
  void insertAt(int index, MediaItem item) {
    if (isQueued(item.id)) return;
    queue.insert(index.clamp(0, queue.length), item);
    _persist();
    unawaited(PodcastQueueDownloads.run());
  }

  /// Callers fire this for episodes that usually aren't queued (every one
  /// "Keep latest" archives on each Inbox load, every finished episode),
  /// so do nothing then: RxList.removeWhere notifies every listener and
  /// _persist rewrites the whole queue even when nothing was removed.
  void removeById(String id) {
    if (!isQueued(id)) return;
    queue.removeWhere((e) => e.id == id);
    _persist();
  }

  void removeAt(int index) {
    if (index < 0 || index >= queue.length) return;
    queue.removeAt(index);
    _persist();
  }

  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);
    _persist();
  }

  void clear() {
    queue.clear();
    _persist();
  }

  /// Empties the queue; the returned callback puts it back as it was
  /// (Undo), keeping after it anything queued since. Null when it was
  /// already empty.
  void Function()? clearUndoable() {
    if (queue.isEmpty) return null;
    final before = queue.toList();
    clear();
    return () {
      final kept = {for (final e in before) e.id};
      queue.assignAll([...before, ...queue.where((e) => !kept.contains(e.id))]);
      _persist();
    };
  }

  /// Puts the queue in [sort]'s order; the returned callback puts it back
  /// as it was (Undo), keeping what's been removed since out and what's
  /// been queued since after it. Null with nothing to sort.
  void Function()? sortUndoable(PodcastQueueSort sort, {Random? random}) {
    if (queue.length < 2) return null;
    final before = queue.toList();
    queue.assignAll(sortedQueue(before, sort, random: random));
    _persist();
    return () {
      final was = {for (final e in before) e.id};
      final still = {for (final e in queue) e.id};
      queue.assignAll([
        ...before.where((e) => still.contains(e.id)),
        ...queue.where((e) => !was.contains(e.id)),
      ]);
      _persist();
    };
  }

  // --- serialization (MediaItem <-> Hive map) ---

  Map<String, dynamic> _toMap(MediaItem m) => {
        'id': m.id,
        'title': m.title,
        'artist': m.artist,
        'artUri': m.artUri?.toString(),
        'durationMs': m.duration?.inMilliseconds,
        // Keep extras needed for playback, chapters, transcripts, and display.
        'url': m.extras?['url'],
        'isPodcast': m.extras?['isPodcast'] ?? true,
        'feedUrl': m.extras?['feedUrl'],
        'date': m.extras?['date'],
        // When it came out, for sorting by date.
        'pubDateMs': m.extras?['pubDateMs'],
        'description': episodeNotes(m),
        'length': m.extras?['length'],
        'chaptersUrl': episodeChaptersUrl(m),
        'transcriptUrl': m.extras?['transcriptUrl'],
        'transcriptType': m.extras?['transcriptType'],
        // The episode's page, for sharing it.
        'link': m.extras?['link'],
      };

  MediaItem _fromMap(Map<String, dynamic> m) => MediaItem(
        id: (m['id'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        artist: m['artist']?.toString(),
        duration: m['durationMs'] is int
            ? Duration(milliseconds: m['durationMs'])
            : null,
        artUri: (m['artUri'] != null && '${m['artUri']}'.isNotEmpty)
            ? Uri.tryParse(m['artUri'].toString())
            : null,
        extras: {
          'url': m['url'],
          'isPodcast': m['isPodcast'] ?? true,
          if (m['feedUrl'] != null) 'feedUrl': m['feedUrl'],
          'date': m['date'],
          if (m['pubDateMs'] is int) 'pubDateMs': m['pubDateMs'],
          'description': m['description'],
          'length': m['length'],
          if (m['chaptersUrl'] != null) 'chaptersUrl': m['chaptersUrl'],
          if (m['transcriptUrl'] != null) 'transcriptUrl': m['transcriptUrl'],
          if (m['transcriptType'] != null)
            'transcriptType': m['transcriptType'],
          if (m['link'] != null) 'link': m['link'],
        },
      );
}
