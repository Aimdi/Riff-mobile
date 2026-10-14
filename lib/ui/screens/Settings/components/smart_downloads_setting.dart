import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/smart_downloads.dart';
import '/ui/widgets/snackbar.dart';
import '../../../widgets/cust_switch.dart';
import 'custom_expansion_tile.dart';

/// Settings › Downloads › Smart downloads (YouTube Music's): the switch,
/// and while it's on, how many songs it keeps.
class SmartDownloadsSetting extends StatelessWidget {
  const SmartDownloadsSetting({super.key});

  /// Says what the look it started came to.
  Future<void> _report(
      BuildContext context, Future<SmartDownloadsRun> run) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    final message = switch (await run) {
      SmartDownloadsRun.started => 'smartDownloadsStarted'
          .trParams({'count': '${SmartDownloads.started}'}),
      SmartDownloadsRun.upToDate => 'smartDownloadsUpToDate'.tr,
      SmartDownloadsRun.waitingForWifi => 'smartDownloadsOnWifi'.tr,
      SmartDownloadsRun.nothingYet => 'smartDownloadsNothingYet'.tr,
      _ => null,
    };
    if (message != null) messenger.showSnackBar(themedSnackbar(theme, message));
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final on = SmartDownloads.enabled.value;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: settingsTilePadding,
            title: Text('smartDownloads'.tr),
            subtitle: Text('smartDownloadsDes'.tr,
                style: settingsSubtitleStyle(context)),
            trailing: CustSwitch(
                value: on,
                onChanged: (value) =>
                    _report(context, SmartDownloads.set(value))),
          ),
          if (on)
            ListTile(
              contentPadding: settingsTilePadding,
              title: Text('smartDownloadsCount'.tr),
              subtitle: Text('smartDownloadsCountDes'.tr,
                  style: settingsSubtitleStyle(context)),
              trailing: DropdownButton<int>(
                dropdownColor:
                    Theme.of(context).colorScheme.surfaceContainerLow,
                underline: const SizedBox.shrink(),
                value: SmartDownloads.count.value,
                items: [
                  for (final n in SmartDownloads.counts)
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: (n) {
                  if (n != null) _report(context, SmartDownloads.setCount(n));
                },
              ),
            ),
        ],
      );
    });
  }
}
