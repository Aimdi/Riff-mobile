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
  final ctx = (context != null && context.mounted) ? context : Get.context;
  final folderId = podcastFolderIdForFeed(feed);
  final folders = Get.isRegistered<PodcastFolderController>()
      ? Get.find<PodcastFolderController>()
      : null;
  final places = folders?.removeEverywhere(folderId) ?? const <String, int>{};
  final stored = await PodcastService.unsubscribe(feed);
  if (stored == null || ctx == null || !ctx.mounted) return;
  ScaffoldMessenger.of(ctx)
    ..hideCurrentSnackBar()
    ..showSnackBar(snackbar(
      ctx,
      'unsubscribedFrom'.trParams({'name': title}),
      actionLabel: 'undo'.tr,
      onAction: () async {
        await PodcastService.restoreSubscription(stored);
        folders?.putBack(folderId, places);
      },
    ));
}
