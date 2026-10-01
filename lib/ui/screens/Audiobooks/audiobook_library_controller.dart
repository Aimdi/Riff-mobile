import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/audiobook_catalog_service.dart';
import '/services/free_audiobook_service.dart';

/// Local bookmarks for audiobooks, shown on Audiobooks > Saved:
/// store titles (browse-only, Hive box `SavedAudiobooks`) and free LibriVox
/// books (playable, box `SavedFreeAudiobooks`).
class AudiobookLibraryController extends GetxController {
  final saved = <AudiobookItem>[].obs;
  final savedFree = <FreeAudiobook>[].obs;

  static const _storeBox = 'SavedAudiobooks';
  static const _freeBox = 'SavedFreeAudiobooks';

  @override
  void onInit() {
    super.onInit();
    _load(_storeBox, saved, AudiobookItem.fromJson);
    _load(_freeBox, savedFree, FreeAudiobook.fromJson);
  }

  Future<void> _load<T>(
      String boxName, RxList<T> target, T Function(Map) fromJson) async {
    final box = await Hive.openBox(boxName);
    // Newest first: Hive keeps insertion order, saves append.
    target.assignAll(box.values
        .map<T?>((e) {
          try {
            return fromJson(Map<String, dynamic>.from(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<T>()
        .toList()
        .reversed);
  }

  bool isSaved(String id) => saved.any((b) => b.id == id);

  bool isFreeSaved(String id) => savedFree.any((b) => b.id == id);

  Future<bool> _toggleIn<T>(String boxName, RxList<T> target, T book, String id,
      Map<String, dynamic> json, String Function(T) idOf) async {
    final box = await Hive.openBox(boxName);
    if (target.any((b) => idOf(b) == id)) {
      await box.delete(id);
      target.removeWhere((b) => idOf(b) == id);
      return false;
    }
    await box.put(id, json);
    target.insert(0, book);
    return true;
  }

  /// Toggle a store book's saved state. Returns the new state (true = saved).
  Future<bool> toggle(AudiobookItem book) => _toggleIn<AudiobookItem>(
      _storeBox, saved, book, book.id, book.toJson(), (b) => b.id);

  /// Toggle a free book's saved state. Returns the new state (true = saved).
  Future<bool> toggleFree(FreeAudiobook book) => _toggleIn<FreeAudiobook>(
      _freeBox, savedFree, book, book.id, book.toJson(), (b) => b.id);
}
