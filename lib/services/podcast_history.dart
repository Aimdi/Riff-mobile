import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_item_extras.dart';
import 'podcast_bookmarks.dart' show episodeSnapshot, mediaItemFromSnapshot;
import 'podcast_service.dart';

/// An episode in the listening history: when it last started playing and
/// enough of it to play it again.
class PodcastHistoryEntry {
  const PodcastHistoryEntry({required this.playedAt, required this.episode});

  final int playedAt;

  /// Playable snapshot of the episode ([episodeSnapshot]).
  final Map<String, dynamic> episode;

  String get id => '${episode['id'] ?? ''}';
  MediaItem? get item => mediaItemFromSnapshot(episode);

  Map<String, dynamic> toJson() => {'playedAt': playedAt, 'episode': episode};

  static PodcastHistoryEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final at = value['playedAt'];
    final episode = value['episode'];
    if (at is! int || episode is! Map) return null;
    final entry = PodcastHistoryEntry(
        playedAt: at, episode: Map<String, dynamic>.from(episode));
    return entry.id.isEmpty ? null : entry;
  }
}

/// Episodes played, newest first, like AntennaPod's Playback history and
/// Pocket Casts' Listening history: one entry per episode (playing it again
/// moves it to the top), at most [maxEntries]. The player adds them when
/// they start, never in a private session.
class PodcastHistory {
  PodcastHistory._();

  static const box = 'PodcastHistory';
  static const maxEntries = 300;

  /// Bumped on every change, for Obx.
  static final rev = 0.obs;

  static Box? get _box => Hive.isBoxOpen(box) ? Hive.box(box) : null;

  /// Newest first.
  static List<PodcastHistoryEntry> get all {
    final b = _box;
    if (b == null) return const [];
    return [
      for (final v in b.values)
        if (PodcastHistoryEntry.fromJson(v) case final entry?) entry
    ]..sort((a, b) => b.playedAt.compareTo(a.playedAt));
  }

  /// [item] started playing (podcast episodes only).
  static Future<void> add(MediaItem item, {DateTime? now}) async {
    final b = _box;
    if (b == null || !item.isPodcastEpisode) return;
    final entry = PodcastHistoryEntry(
        playedAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
        episode: episodeSnapshot(item));
    await b.put(item.id, entry.toJson());
    if (b.length > maxEntries) {
      await b.deleteAll([for (final e in all.skip(maxEntries)) e.id]);
    }
    rev.value++;
  }

  /// Gone from [all] at once (a swiped-away row must leave the list in the
  /// next frame: Hive drops it from memory before writing), then stored.
  static Future<void> remove(String id) async {
    final stored = _box?.delete(id);
    rev.value++;
    await stored;
    rev.value++;
  }

  static Future<void> clear() async {
    await _box?.clear();
    rev.value++;
  }

  /// Puts removed entries back (Undo).
  static Future<void> restore(Iterable<PodcastHistoryEntry> entries) async {
    await _box?.putAll({for (final e in entries) e.id: e.toJson()});
    rev.value++;
  }
}

/// The history (newest first) by day, each under its label: Today,
/// Yesterday, then the date.
List<(String, List<PodcastHistoryEntry>)> podcastHistoryByDay(
    List<PodcastHistoryEntry> entries, DateTime now) {
  final days = <(String, List<PodcastHistoryEntry>)>[];
  for (final e in entries) {
    final label =
        podcastHistoryDay(DateTime.fromMillisecondsSinceEpoch(e.playedAt), now);
    if (days.isNotEmpty && days.last.$1 == label) {
      days.last.$2.add(e);
    } else {
      days.add((label, [e]));
    }
  }
  return days;
}

/// "Today", "Yesterday", else the date as episode dates show it.
String podcastHistoryDay(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day);
  if (day == DateTime(now.year, now.month, now.day)) return 'today'.tr;
  if (day == DateTime(now.year, now.month, now.day - 1)) {
    return 'yesterday'.tr;
  }
  return PodcastService.formatDay(day);
}
