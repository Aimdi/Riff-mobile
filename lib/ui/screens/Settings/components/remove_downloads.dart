import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/cache_eviction.dart' show formatCacheBytes;
import '/services/smart_downloads.dart';
import '/ui/widgets/confirm_dialog.dart';
import '/ui/widgets/snackbar.dart';
import '../settings_screen_controller.dart';

/// Settings › Remove downloaded songs: asks first (how many, how much
/// space), then removes them all and says so.
Future<void> removeAllDownloadsAsked(BuildContext context) async {
  final settings = Get.find<SettingsScreenController>();
  final count =
      Hive.isBoxOpen('SongDownloads') ? Hive.box('SongDownloads').length : 0;
  if (count == 0) return;
  final message = [
    'removeAllDownloadsMsg'.trParams({
      'count': '$count',
      'size': formatCacheBytes(settings.downloadsBytes.value),
    }),
    // They'd come back on Wi-Fi.
    if (SmartDownloads.enabled.value) 'smartDownloadsRefill'.tr,
  ].join('\n\n');
  final confirmed = await confirmDestructive(context,
      title: 'removeAllDownloadsQ'.tr,
      message: message,
      confirmLabel: 'remove'.tr);
  if (!confirmed || !context.mounted) return;
  final target = undoSnackbarTarget(context);
  final removed = await settings.removeAllDownloads();
  showUndoSnackbar(
      target, removed == null ? 'operationFailed'.tr : 'downloadsRemoved'.tr);
}
