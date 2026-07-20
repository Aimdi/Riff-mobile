import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// A named folder grouping podcast subscriptions (Spotify-style). Stores only
/// the shows' playlistIds; the show data itself lives in LibraryPodcasts.
class PodcastFolder {
  PodcastFolder(this.id, this.name, this.podcastIds);
  final String id;
  String name;
  List<String> podcastIds;

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'ids': podcastIds};

  factory PodcastFolder.fromMap(Map m) => PodcastFolder(
        (m['id'] ?? '').toString(),
        (m['name'] ?? '').toString(),
        (m['ids'] as List?)?.map((e) => e.toString()).toList() ?? <String>[],
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

  PodcastFolder createFolder(String name) {
    final f = PodcastFolder(
        DateTime.now().microsecondsSinceEpoch.toString(), name.trim(), []);
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
