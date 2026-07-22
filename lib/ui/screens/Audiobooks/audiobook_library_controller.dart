import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/audiobook_catalog_service.dart';

/// Local bookmarks for catalog audiobooks. Since catalog books aren't playable
/// in-app, "saving" just keeps a local list (Hive box `SavedAudiobooks`) you
/// can revisit from the Audiobooks > Saved tab. The wish list (Audible-style)
/// works the same way, backed by the `AudiobookWishlist` box.
class AudiobookLibraryController extends GetxController {
  final saved = <AudiobookItem>[].obs;
  final wishlist = <AudiobookItem>[].obs;

  @override
  void onInit() {
    super.onInit();
    _load('SavedAudiobooks', saved);
    _load('AudiobookWishlist', wishlist);
  }

  Future<void> _load(String boxName, RxList<AudiobookItem> target) async {
    final box = await Hive.openBox(boxName);
    target.assignAll(box.values
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
  bool isWishlisted(String id) => wishlist.any((b) => b.id == id);

  Future<bool> _toggleIn(
      String boxName, RxList<AudiobookItem> target, AudiobookItem book) async {
    final box = await Hive.openBox(boxName);
    if (target.any((b) => b.id == book.id)) {
      await box.delete(book.id);
      target.removeWhere((b) => b.id == book.id);
      return false;
    }
    await box.put(book.id, book.toJson());
    target.insert(0, book);
    return true;
  }

  /// Toggle a book's saved state. Returns the new state (true = now saved).
  Future<bool> toggle(AudiobookItem book) =>
      _toggleIn('SavedAudiobooks', saved, book);

  /// Toggle a book's wish-list state. Returns true if now wishlisted.
  Future<bool> toggleWishlist(AudiobookItem book) =>
      _toggleIn('AudiobookWishlist', wishlist, book);
}
