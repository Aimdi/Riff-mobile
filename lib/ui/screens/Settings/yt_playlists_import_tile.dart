import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/yt_playlists_import.dart';
import '/ui/screens/Library/library_controller.dart';
import '/ui/widgets/snackbar.dart';
import 'components/custom_expansion_tile.dart';
import 'settings_screen_controller.dart';

/// Settings' "Your YouTube Music playlists", under the YouTube account
/// while one is connected: a tap adds the playlists of your YouTube Music
/// library to Riff's Library, as Metrolist brings them in, and says how
/// many came.
class YtPlaylistsImportTile extends StatelessWidget {
  const YtPlaylistsImportTile({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsScreenController>();
    return Obx(() {
      final busy = YtPlaylistsImport.importing.value;
      if (!settings.ytConnected.value) return const SizedBox.shrink();
      return ListTile(
        contentPadding: settingsTilePadding,
        title: Text("ytPlaylistsImport".tr),
        subtitle: Text("ytPlaylistsImportDes".tr,
            style: settingsSubtitleStyle(context)),
        // Off while they're coming in.
        enabled: !busy,
        onTap: () => _import(context),
      );
    });
  }

  Future<void> _import(BuildContext context) async {
    final target = undoSnackbarTarget(context);
    final count = await YtPlaylistsImport.importPlaylists();
    if ((count ?? 0) > 0 && Get.isRegistered<LibraryPlaylistsController>()) {
      Get.find<LibraryPlaylistsController>().refreshLib();
    }
    showUndoSnackbar(
        target,
        switch (count) {
          null => 'ytPlaylistsImportFailed'.tr,
          0 => 'ytPlaylistsUpToDate'.tr,
          1 => 'ytPlaylistsImportedOne'.tr,
          _ => 'ytPlaylistsImported'.trParams({'count': '$count'}),
        });
  }
}
