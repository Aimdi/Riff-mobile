import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/ui/theme/palettes/podcast_folders.dart';

export '/ui/theme/palettes/podcast_folders.dart' show PodcastFolderColors;

/// Folder id for a feed (RSS) show. YouTube library shows use their
/// playlistId as before, so folders saved by older versions keep working.
String podcastFolderIdForFeed(String feedUrl) => 'rss:$feedUrl';

/// The feed URL in a folder entry, or null for a YouTube show.
String? feedUrlFromFolderId(String id) =>
    id.startsWith('rss:') ? id.substring(4) : null;

/// Move an item in a list the way ReorderableListView reports it.
List<T> reorderList<T>(List<T> list, int oldIndex, int newIndex) {
  final out = List<T>.of(list);
  if (oldIndex < 0 || oldIndex >= out.length) return out;
  if (newIndex > oldIndex) newIndex -= 1;
  final item = out.removeAt(oldIndex);
  out.insert(newIndex.clamp(0, out.length), item);
  return out;
}

/// A named folder grouping podcast subscriptions (Spotify-style). Stores only
/// show ids (YouTube playlistIds, or `rss:<feed>` for feed shows); the show
/// data itself lives in LibraryPodcasts and the feed subscriptions.
class PodcastFolder {
  PodcastFolder(this.id, this.name, this.podcastIds, {this.colorIndex = 0});
  final String id;
  String name;
  List<String> podcastIds;
  int colorIndex;

  Color get color => PodcastFolderColors.of(colorIndex);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'ids': podcastIds,
        'color': colorIndex,
      };

  factory PodcastFolder.fromMap(Map m) => PodcastFolder(
        (m['id'] ?? '').toString(),
        (m['name'] ?? '').toString(),
        (m['ids'] as List?)?.map((e) => e.toString()).toList() ?? <String>[],
        colorIndex: (m['color'] is int)
            ? m['color'] as int
            : int.tryParse('${m['color'] ?? 0}') ?? 0,
      );
}

class PodcastFolderController extends GetxController {
  final folders = <PodcastFolder>[].obs;

  static const _key = 'folders';
  Box get _box => Hive.box('PodcastFolders');

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  void _load() {
    final raw = _box.get(_key);
    if (raw is List) {
      folders.assignAll(
          raw.whereType<Map>().map((m) => PodcastFolder.fromMap(m)).toList());
    }
  }

  void _persist() => _box.put(_key, folders.map((f) => f.toMap()).toList());

  PodcastFolder? findById(String id) {
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  PodcastFolder createFolder(String name, {int colorIndex = 0}) {
    final f = PodcastFolder(
      DateTime.now().microsecondsSinceEpoch.toString(),
      name.trim(),
      [],
      colorIndex: colorIndex.clamp(0, PodcastFolderColors.swatches.length - 1),
    );
    folders.add(f);
    _persist();
    return f;
  }

  void rename(String id, String name) {
    final f = findById(id);
    if (f != null) {
      f.name = name.trim();
      folders.refresh();
      _persist();
    }
  }

  void setColor(String id, int colorIndex) {
    final f = findById(id);
    if (f == null) return;
    f.colorIndex = colorIndex.clamp(0, PodcastFolderColors.swatches.length - 1);
    folders.refresh();
    _persist();
  }

  /// Drag to reorder (ReorderableListView indices).
  void move(int oldIndex, int newIndex) {
    folders.assignAll(reorderList(folders, oldIndex, newIndex));
    _persist();
  }

  void deleteFolder(String id) {
    folders.removeWhere((f) => f.id == id);
    _persist();
  }

  bool contains(String folderId, String podcastId) =>
      findById(folderId)?.podcastIds.contains(podcastId) ?? false;

  void toggle(String folderId, String podcastId) {
    final f = findById(folderId);
    if (f == null) return;
    if (f.podcastIds.contains(podcastId)) {
      f.podcastIds.remove(podcastId);
    } else {
      f.podcastIds.add(podcastId);
    }
    folders.refresh();
    _persist();
  }

  /// Remove a podcast from every folder (e.g. when unsubscribed).
  void removeEverywhere(String podcastId) {
    var changed = false;
    for (final f in folders) {
      if (f.podcastIds.remove(podcastId)) changed = true;
    }
    if (changed) {
      folders.refresh();
      _persist();
    }
  }
}
