import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/podcast_download_service.dart';
import '/ui/widgets/snackbar.dart';

/// Removes an episode's download with "Download removed · Undo": it stops
/// counting as downloaded at once ([onChanged] refreshes the screen), the
/// file is deleted only when the snackbar goes without Undo, so a slip
/// doesn't cost the download.
Future<void> removePodcastDownloadWithUndo(String id,
    {BuildContext? context, VoidCallback? onChanged}) async {
  // Before any await: the row that asked is gone once the list updates.
  final target = undoSnackbarTarget(context);
  final removal = await PodcastDownloadService.takeOut(id);
  onChanged?.call();
  if (removal == null) return;
  final shown = showUndoSnackbar(
    target,
    'downloadRemoved'.tr,
    onUndo: () async {
      await PodcastDownloadService.restore(removal);
      onChanged?.call();
    },
  );
  if (shown == null) {
    // Nowhere to offer Undo.
    await PodcastDownloadService.commitRemoval(removal);
    return;
  }
  shown.closed.then((reason) {
    if (reason != SnackBarClosedReason.action) {
      PodcastDownloadService.commitRemoval(removal);
    }
  });
}
