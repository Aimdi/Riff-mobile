import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/yt_like_sync.dart';
import '/ui/screens/Playlist/playlist_screen_controller.dart';
import '/ui/widgets/cust_switch.dart';
import '/ui/widgets/snackbar.dart';
import 'components/custom_expansion_tile.dart';
import 'settings_screen_controller.dart';

/// Settings' "Like on YouTube Music too", under the YouTube account while
/// one is connected: turned on, your YouTube Music likes come into your
/// Favorites and the likes you make in Riff go to YouTube Music.
class YtLikeSyncTile extends StatelessWidget {
  const YtLikeSyncTile({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsScreenController>();
    return Obx(() {
      YtLikeSync.rev.value;
      if (!settings.ytConnected.value) return const SizedBox.shrink();
      return ListTile(
        contentPadding: settingsTilePadding,
        title: Text("ytLikeSync".tr),
        subtitle:
            Text("ytLikeSyncDes".tr, style: settingsSubtitleStyle(context)),
        trailing: CustSwitch(
          value: YtLikeSync.enabled,
          onChanged: (on) => _turn(context, on),
        ),
      );
    });
  }

  Future<void> _turn(BuildContext context, bool on) async {
    final target = undoSnackbarTarget(context);
    await YtLikeSync.setEnabled(on);
    if (!on) return;
    final count = await YtLikeSync.importLikes();
    if ((count ?? 0) > 0) {
      // The Favorites page, if open, shows them.
      final tag = const Key('LIBFAV').hashCode.toString();
      if (Get.isRegistered<PlaylistScreenController>(tag: tag)) {
        Get.find<PlaylistScreenController>(tag: tag)
            .fetchSongsfromDatabase('LIBFAV');
      }
    }
    showUndoSnackbar(
        target,
        switch (count) {
          null => 'ytLikesImportFailed'.tr,
          0 => 'ytLikesUpToDate'.tr,
          _ => 'ytLikesImported'.trParams({'count': '$count'}),
        });
  }
}
