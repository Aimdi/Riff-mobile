import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/audiobook_catalog_service.dart';

/// Local bookmarks for catalog audiobooks. Since catalog books aren't playable
/// in-app, "saving" just keeps a local list (Hive box `SavedAudiobooks`) you
/// can revisit from the Audiobooks > Saved tab.
class AudiobookLibraryController extends GetxController {
  final saved = <AudiobookItem>[].obs;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox('SavedAudiobooks');
    saved.assignAll(box.values
        .map<AudiobookItem?>((e) {
          try {
            return AudiobookItem.fromJson(Map<String, dynamic>.from(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<AudiobookItem>()
        .toList());
  }

  bool isSaved(String id) => saved.any((b) => b.id == id);

  /// Toggle a book's saved state. Returns the new state (true = now saved).
  Future<bool> toggle(AudiobookItem book) async {
    final box = await Hive.openBox('SavedAudiobooks');
    if (isSaved(book.id)) {
      await box.delete(book.id);
      saved.removeWhere((b) => b.id == book.id);
      return false;
    }
    await box.put(book.id, book.toJson());
    saved.insert(0, book);
    return true;
  }
}
