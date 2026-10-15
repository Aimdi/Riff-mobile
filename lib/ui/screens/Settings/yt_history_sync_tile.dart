import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/yt_history_sync.dart';
import '/ui/widgets/cust_switch.dart';
import 'components/custom_expansion_tile.dart';
import 'settings_screen_controller.dart';

/// Settings' "Add to YouTube Music history", under the YouTube account
/// while one is connected: on, what you play in Riff goes into the
/// account's YouTube Music history, as plays in YouTube Music do.
class YtHistorySyncTile extends StatelessWidget {
  const YtHistorySyncTile({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsScreenController>();
    return Obx(() {
      YtHistorySync.rev.value;
      if (!settings.ytConnected.value) return const SizedBox.shrink();
      return ListTile(
        contentPadding: settingsTilePadding,
        title: Text("ytHistorySync".tr),
        subtitle:
            Text("ytHistorySyncDes".tr, style: settingsSubtitleStyle(context)),
        trailing: CustSwitch(
          value: YtHistorySync.enabled,
          onChanged: YtHistorySync.setEnabled,
        ),
      );
    });
  }
}
