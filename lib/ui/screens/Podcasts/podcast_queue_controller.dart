import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

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
  }

  void removeById(String id) {
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

  // --- serialization (MediaItem <-> Hive map) ---

  Map<String, dynamic> _toMap(MediaItem m) => {
        'id': m.id,
        'title': m.title,
        'artist': m.artist,
        'artUri': m.artUri?.toString(),
        'durationMs': m.duration?.inMilliseconds,
        // Keep only the primitive extras needed for playback + display.
        'url': m.extras?['url'],
        'isPodcast': m.extras?['isPodcast'] ?? true,
        'date': m.extras?['date'],
        'description': m.extras?['description'],
        'length': m.extras?['length'],
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
          'date': m['date'],
          'description': m['description'],
          'length': m['length'],
        },
      );
}
