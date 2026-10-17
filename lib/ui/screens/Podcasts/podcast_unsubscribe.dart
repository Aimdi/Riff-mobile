import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/podcast_service.dart';
import '/ui/widgets/snackbar.dart';
import 'podcast_folder_controller.dart';

/// Unsubscribes from a feed show and says so with Undo, as Pocket Casts
/// and Spotify do: Undo brings the subscription back as it was, date
/// included, and puts the show back in its folders at the same places.
Future<void> unsubscribeWithUndo(String feed, String title,
    {BuildContext? context}) async {
  // Before any await: a long-pressed tile is gone once the grid updates.
  final target = undoSnackbarTarget(context);
  final folderId = podcastFolderIdForFeed(feed);
  final folders = Get.isRegistered<PodcastFolderController>()
      ? Get.find<PodcastFolderController>()
      : null;
  final places = folders?.removeEverywhere(folderId) ?? const <String, int>{};
  final stored = await PodcastService.unsubscribe(feed);
  if (stored == null) return;
  showUndoSnackbar(
    target,
    'unsubscribedFrom'.trParams({'name': title}),
    onUndo: () async {
      await PodcastService.restoreSubscription(stored);
      folders?.putBack(folderId, places);
    },
  );
}
