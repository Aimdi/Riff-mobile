import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Library › Playlists and Albums as a grid of covers or a list of rows,
/// like Spotify's Your Library list / grid switch: one choice for both,
/// kept in AppPrefs.
class LibraryViewMode {
  LibraryViewMode._();

  static const prefKey = 'libraryListView';

  /// Rows instead of the grid.
  static final list = RxBool(_stored());

  static bool _stored() =>
      Hive.isBoxOpen('AppPrefs') && Hive.box('AppPrefs').get(prefKey) == true;

  static Future<void> setList(bool on) async {
    list.value = on;
    if (Hive.isBoxOpen('AppPrefs')) await Hive.box('AppPrefs').put(prefKey, on);
  }
}
