import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_item_extras.dart';
import 'podcast_bookmarks.dart' show episodeSnapshot, mediaItemFromSnapshot;

/// A starred episode: when it was starred and enough of it to play it
/// again (show notes included, to read them later).
class StarredEpisode {
  const StarredEpisode({required this.starredAt, required this.episode});

  final int starredAt;

  /// Playable snapshot of the episode ([episodeSnapshot] and its notes).
  final Map<String, dynamic> episode;

  String get id => '${episode['id'] ?? ''}';
  MediaItem? get item => mediaItemFromSnapshot(episode);

  Map<String, dynamic> toJson() => {'starredAt': starredAt, 'episode': episode};

  static StarredEpisode? fromJson(Object? value) {
    if (value is! Map) return null;
    final at = value['starredAt'];
    final episode = value['episode'];
    if (at is! int || episode is! Map) return null;
    final starred = StarredEpisode(
        starredAt: at, episode: Map<String, dynamic>.from(episode));
    return starred.id.isEmpty ? null : starred;
  }
}

/// Episodes starred to come back to, like Pocket Casts' Starred, Spotify's
/// Your Episodes and Apple Podcasts' Saved: newest starred first, from any
/// show (followed or not). Their downloads are kept when finished ones are
/// deleted, as AntennaPod keeps its favourites'.
class StarredEpisodes {
  StarredEpisodes._();

  static const box = 'PodcastStarred';

  /// Bumped on every change, for Obx.
  static final rev = 0.obs;

  static Box? get _box => Hive.isBoxOpen(box) ? Hive.box(box) : null;

  /// Newest starred first.
  static List<StarredEpisode> get all {
    final b = _box;
    if (b == null) return const [];
    return [
      for (final v in b.values)
        if (StarredEpisode.fromJson(v) case final starred?) starred
    ]..sort((a, b) => b.starredAt.compareTo(a.starredAt));
  }

  static bool isStarred(String id) => _box?.containsKey(id) ?? false;

  /// [id]'s entry, when it's starred.
  static StarredEpisode? entry(String id) =>
      StarredEpisode.fromJson(_box?.get(id));

  /// Stars [item] (podcast episodes only); false when it can't be.
  static Future<bool> star(MediaItem item, {DateTime? now}) async {
    final b = _box;
    if (b == null || !item.isPodcastEpisode) return false;
    final episode = episodeSnapshot(item);
    final notes = item.extras?['description'];
    if (notes is String && notes.trim().isNotEmpty) {
      (episode['extras'] as Map<String, dynamic>)['description'] = notes;
    }
    final starred = StarredEpisode(
        starredAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
        episode: episode);
    await b.put(item.id, starred.toJson());
    rev.value++;
    return true;
  }

  /// Gone from [all] at once (a swiped-away row must leave the list in the
  /// next frame: Hive drops it from memory before writing), then stored.
  static Future<void> unstar(String id) async {
    final stored = _box?.delete(id);
    rev.value++;
    await stored;
    rev.value++;
  }

  /// Puts unstarred episodes back (Undo).
  static Future<void> restore(Iterable<StarredEpisode> episodes) async {
    await _box?.putAll({for (final e in episodes) e.id: e.toJson()});
    rev.value++;
  }
}
