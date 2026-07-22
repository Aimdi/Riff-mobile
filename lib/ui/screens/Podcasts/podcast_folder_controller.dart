import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Preset folder colors (Spotify-style chips). Index is persisted with the folder.
class PodcastFolderColors {
  PodcastFolderColors._();

  static const List<Color> swatches = [
    Color(0xFF1DB954), // green
    Color(0xFF1E90FF), // dodger blue
    Color(0xFF9B59B6), // purple
    Color(0xFFE74C3C), // red
    Color(0xFFF39C12), // amber
    Color(0xFF1ABC9C), // teal
    Color(0xFFE91E63), // pink
    Color(0xFF00BCD4), // cyan
    Color(0xFFFF5722), // deep orange
    Color(0xFF8BC34A), // light green
    Color(0xFF607D8B), // blue grey
    Color(0xFF795548), // brown
  ];

  static Color of(int index) =>
      swatches[index.clamp(0, swatches.length - 1)];
}

/// A named folder grouping podcast subscriptions (Spotify-style). Stores only
/// the shows' playlistIds; the show data itself lives in LibraryPodcasts.
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
      folders.assignAll(raw
          .whereType<Map>()
          .map((m) => PodcastFolder.fromMap(m))
          .toList());
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
    f.colorIndex =
        colorIndex.clamp(0, PodcastFolderColors.swatches.length - 1);
    folders.refresh();
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
