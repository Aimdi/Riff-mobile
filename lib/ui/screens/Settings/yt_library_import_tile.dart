import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/yt_library_import.dart';
import '/ui/screens/Library/library_controller.dart';
import '/ui/widgets/snackbar.dart';
import 'components/custom_expansion_tile.dart';
import 'settings_screen_controller.dart';

/// Settings' "Your YouTube Music library", under the YouTube account while
/// one is connected: a tap brings your YouTube Music playlists and the
/// artists you subscribe to into Riff's Library, as Metrolist brings them
/// in, and says what came.
class YtLibraryImportTile extends StatelessWidget {
  const YtLibraryImportTile({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsScreenController>();
    return Obx(() {
      final busy = YtLibraryImport.importing.value;
      if (!settings.ytConnected.value) return const SizedBox.shrink();
      return ListTile(
        contentPadding: settingsTilePadding,
        title: Text("ytLibraryImport".tr),
        subtitle: Text("ytLibraryImportDes".tr,
            style: settingsSubtitleStyle(context)),
        // Off while it's coming in.
        enabled: !busy,
        onTap: () => _import(context),
      );
    });
  }

  Future<void> _import(BuildContext context) async {
    final target = undoSnackbarTarget(context);
    final came = await YtLibraryImport.importLibrary();
    if (came == null) return;
    if ((came.playlists ?? 0) > 0 &&
        Get.isRegistered<LibraryPlaylistsController>()) {
      Get.find<LibraryPlaylistsController>().refreshLib();
    }
    if ((came.artists ?? 0) > 0 &&
        Get.isRegistered<LibraryArtistsController>()) {
      Get.find<LibraryArtistsController>().refreshLib();
    }
    showUndoSnackbar(target, ytLibraryImportedText(came));
  }
}

/// What the snackbar says came in: "Added from YouTube Music: 3
/// playlists, 1 artist", that it's all there already, or that YouTube
/// couldn't be reached (nothing read).
String ytLibraryImportedText(YtLibraryImported came) {
  final playlists = came.playlists ?? 0;
  final artists = came.artists ?? 0;
  if (playlists + artists == 0) {
    return came.playlists == null || came.artists == null
        ? 'ytLibraryImportFailed'.tr
        : 'ytLibraryUpToDate'.tr;
  }
  String count(int n, String one, String many) =>
      n == 1 ? one.tr : many.trParams({'count': '$n'});
  return 'ytLibraryImported'.trParams({
    'what': [
      if (playlists > 0)
        count(playlists, 'ytPlaylistCountOne', 'ytPlaylistCount'),
      if (artists > 0) count(artists, 'ytArtistCountOne', 'ytArtistCount'),
    ].join(', '),
  });
}
