import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/podcast_download_service.dart';
import '/services/podcast_progress_service.dart';
import '/services/podcast_service.dart';
import 'podcast_empty_state.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/sheet_insets.dart';
import '/ui/widgets/snackbar.dart';
import 'podcast_queue_controller.dart';
import 'podcasts_screen.dart';

/// Long-press action sheet for a podcast episode: queue, download, play next,
/// mark played, and shownotes. Opens immediately — download/queue state is
/// resolved inside the builder so the sheet never waits on disk I/O.
void showAddToQueueSheet(BuildContext context, MediaItem episode) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    // Root overlay sits above the SlidingUpPanel mini player; nested
    // navigator sheets were leaving Download under the playing bar.
    useRootNavigator: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) {
      final c = Get.find<PodcastQueueController>();
      final queued = c.isQueued(episode.id);
      final downloaded = PodcastDownloadService.isDownloaded(episode.id);
      final canDownload =
          (episode.extras?['url'] as String?)?.isNotEmpty ?? false;
      final notes = (episode.extras?['description'] ?? '').toString().trim();
      final feedUrl = (episode.extras?['feedUrl'] ?? '').toString().trim();
      void snack(String msg) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          snackbar(context, msg, size: SanckBarSize.MEDIUM),
        );
      }

      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            top: 8,
            // Root navigator already clears the mini player — only safe area.
            bottom: 8 + sheetBottomInset(ctx, liftAboveMiniPlayer: false),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text("playNext".tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Get.find<PlayerController>().playNext(episode);
                  snack("playNext".tr);
                },
              ),
              ListTile(
                leading:
                    Icon(queued ? Icons.playlist_remove : Icons.playlist_add),
                title: Text(queued ? "removeFromQueue".tr : "addToQueue".tr),
                onTap: () {
                  queued ? c.removeById(episode.id) : c.add(episode);
                  Navigator.of(ctx).pop();
                  snack(queued ? "removedFromQueue".tr : "addedToQueue".tr);
                },
              ),
              if (canDownload || downloaded)
                ListTile(
                  leading: Icon(downloaded
                      ? Icons.delete_outline
                      : Icons.download_outlined),
                  title: Text(downloaded ? "removeDownload".tr : "download".tr),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    if (downloaded) {
                      await PodcastDownloadService.delete(episode.id);
                      snack("downloadRemoved".tr);
                      return;
                    }
                    snack("downloadStarted".tr);
                    final ok = await PodcastDownloadService.download(episode);
                    snack(ok ? "downloadComplete".tr : "downloadFailed".tr);
                  },
                ),
              ListTile(
                leading: Icon(PodcastProgressService.isPlayed(episode.id)
                    ? Icons.remove_done
                    : Icons.check_circle_outline),
                title: Text(PodcastProgressService.isPlayed(episode.id)
                    ? "markAsUnplayed".tr
                    : "markAsPlayed".tr),
                onTap: () {
                  if (PodcastProgressService.isPlayed(episode.id)) {
                    PodcastProgressService.markUnplayed(episode.id);
                    snack("markAsUnplayed".tr);
                  } else {
                    PodcastProgressService.markAsPlayed(episode.id);
                    snack("markAsPlayed".tr);
                  }
                  Navigator.of(ctx).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: Text("shownotes".tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showModalBottomSheet(
                    context: context,
                    useRootNavigator: true,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    builder: (sctx) => DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: 0.55,
                      minChildSize: 0.35,
                      maxChildSize: 0.9,
                      builder: (_, scrollCtrl) => SingleChildScrollView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(episode.title,
                                style: Theme.of(sctx).textTheme.titleLarge),
                            if ((episode.artist ?? '').isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(episode.artist!,
                                  style: Theme.of(sctx).textTheme.titleSmall),
                            ],
                            const Divider(height: 24),
                            Text(
                              notes.isEmpty ? "noShownotes".tr : notes,
                              style: Theme.of(sctx).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (feedUrl.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.podcasts_outlined),
                  title: Text("openShow".tr),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Get.to(() => PodcastEpisodesScreen(podcast: {
                          'feedUrl': feedUrl,
                          'title': episode.artist ?? '',
                          'artwork': episode.artUri?.toString() ?? '',
                        }));
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// The podcast Queue ("Warteschlange"): episodes you've added via long-press,
/// played in order. Reorder by dragging the handle, swipe/remove to drop one,
/// tap to play from that point.
class PodcastQueueScreen extends StatelessWidget {
  const PodcastQueueScreen({super.key, this.embedded = false, this.onDiscover});

  /// Jumps to the Discover tab (embedded mode) from the empty state.
  final VoidCallback? onDiscover;

  /// When true, render just the content (no Scaffold/AppBar) for inline use.
  final bool embedded;

  static String _fmtTotal(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return "${h}h ${m}m";
    return "${m}m";
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PodcastQueueController>();
    final body = Obx(() {
      final items = controller.queue;
      if (items.isEmpty) {
        return PodcastEmptyState(
          icon: Icons.playlist_play_rounded,
          message: "queueEmpty".tr,
          actionLabel: onDiscover != null ? 'discover'.tr : null,
          onAction: onDiscover,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "${items.length} ${'episodes'.tr}  ·  "
                    "${'remainingTime'.tr} ${_fmtTotal(controller.totalTime)}",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                // Non-embedded gets the clear action in the AppBar instead.
                if (embedded)
                  IconButton(
                    tooltip: "clear".tr,
                    icon: const Icon(Icons.clear_all, size: 22),
                    onPressed: controller.clear,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 200),
              itemCount: items.length,
              onReorder: controller.reorder,
              itemBuilder: (context, i) =>
                  _row(context, controller, items[i], i),
            ),
          ),
        ],
      );
    });
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text("queue".tr),
        actions: [
          Obx(() => controller.queue.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: "clear".tr,
                  icon: const Icon(Icons.clear_all),
                  onPressed: controller.clear,
                )),
        ],
      ),
      body: body,
    );
  }

  Widget _row(BuildContext context, PodcastQueueController controller,
      MediaItem e, int i) {
    final date = (e.extras?['date'] ?? '').toString().trim();
    final durationText =
        PodcastService.formatDuration(e.duration?.inSeconds ?? 0);
    final art = Thumbnail(e.artUri?.toString() ?? '').medium;
    return Padding(
      key: ValueKey(e.id),
      // Match Inbox rhythm: 16 content inset; drag handle sits in the gutter.
      padding: const EdgeInsets.only(left: 8, right: 16),
      child: InkWell(
        onTap: () =>
            Get.find<PlayerController>().playPlayListSong(items(controller), i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_indicator, size: 22),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: art,
                  width: 56,
                  height: 56,
                  memCacheWidth:
                      (56 * MediaQuery.devicePixelRatioOf(context)).round(),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.podcasts, size: 40),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (date.isNotEmpty || durationText.isNotEmpty)
                      Text(
                        [date, durationText]
                            .where((s) => s.isNotEmpty)
                            .join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    Text(
                      e.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: "removeFromQueue".tr,
                icon: const Icon(Icons.remove_circle_outline, size: 22),
                onPressed: () => controller.removeAt(i),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<MediaItem> items(PodcastQueueController c) => c.queue.toList();
}
