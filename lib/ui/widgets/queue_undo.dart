import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/player/player_controller.dart';
import 'snackbar.dart';

/// Removes [song] from Up Next with an Undo snackbar, like Spotify and
/// YouTube Music. [context] picks the messenger (defaults to the app's).
Future<void> removeFromQueueWithUndo(MediaItem song,
    {BuildContext? context}) async {
  // Before the await: a swiped-away row is gone once the queue updates.
  final target = undoSnackbarTarget(_snackContext(context));
  final undo = await Get.find<PlayerController>().removeFromQueueUndoable(song);
  // A newer edit replaces the last one's snackbar, as in other players.
  showUndoSnackbar(
      target, undo == null ? 'operationFailed'.tr : 'removedFromQueue'.tr,
      onUndo: undo);
}

/// Clears Up Next down to the playing song, with an Undo snackbar.
Future<void> clearQueueWithUndo({BuildContext? context}) async {
  final target = undoSnackbarTarget(_snackContext(context));
  final undo = await Get.find<PlayerController>().clearQueueUndoable();
  // Nothing was queued after the playing song: nothing to say or undo.
  if (undo == null) return;
  showUndoSnackbar(target, 'queueCleared'.tr, onUndo: undo);
}

BuildContext? _snackContext(BuildContext? context) =>
    (context != null && context.mounted)
        ? context
        : Get.find<PlayerController>().homeScaffoldkey.currentContext ??
            Get.context;
