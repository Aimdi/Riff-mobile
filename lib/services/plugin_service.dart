import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Built-in plugin ids that can be offered from Settings → Plugins.
class PluginIds {
  PluginIds._();
  static const torrentsDigger = 'torrents_digger';
  static const soulSync = 'soul_sync';
  static const seeker = 'seeker';
}

/// Tracks which optional plugins the user has installed/enabled.
///
/// Plugins ship with the app; "download" here means enabling the bundled
/// plugin (same UX as a marketplace install).
class PluginService extends GetxController {
  static const _prefsKey = 'installedPlugins';

  final installed = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    final raw = Hive.box('AppPrefs').get(_prefsKey, defaultValue: <dynamic>[]);
    installed.assignAll(
      (raw as List).map((e) => e.toString()).toList(),
    );
  }

  bool isInstalled(String id) => installed.contains(id);

  Future<void> install(String id) async {
    if (installed.contains(id)) return;
    installed.add(id);
    await _persist();
  }

  Future<void> uninstall(String id) async {
    installed.remove(id);
    await _persist();
  }

  Future<void> _persist() async {
    await Hive.box('AppPrefs').put(_prefsKey, installed.toList());
  }
}
