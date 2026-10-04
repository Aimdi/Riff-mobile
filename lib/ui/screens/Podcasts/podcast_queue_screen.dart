import '/ui/player/long_form_queue.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/services/podcast_download_service.dart';
import '/services/podcast_library.dart';
import '/services/podcast_progress_service.dart';
import '/services/wizestream_service.dart';
import '../Home/home_layout.dart';
import 'podcast_empty_state.dart';
import 'podcast_layout.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/sheet_insets.dart';
import '/ui/widgets/podcast_play.dart';
import '/ui/widgets/snackbar.dart';
import 'podcast_queue_controller.dart';
import 'podcasts_screen.dart';

/// Long-press action sheet for a podcast episode: queue, download, play next,
/// mark played, and shownotes. Opens immediately — download/queue state is
/// resolved inside the builder so the sheet never waits on disk I/O.
///
/// [onChanged] runs after an action that changes the episode's state
/// (played, queued, downloaded) so the list behind can refresh.
void showAddToQueueSheet(BuildContext context, MediaItem episode,
    {VoidCallback? onChanged}) {
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
      final notes = episodeNotes(episode).trim();
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
              if (WizeStream.isInstalled &&
                  WizeStream.watchUrlFor(episode) != null)
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: Text("openInWizeStream".tr),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok =
                        await WizeStream.open(WizeStream.watchUrlFor(episode)!);
                    if (!ok) snack("operationFailed".tr);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text("playNext".tr),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final ok =
                      await Get.find<PlayerController>().playNext(episode);
                  snack(ok ? "playnextMsg".tr : "operationFailed".tr);
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text("playLast".tr),
                subtitle: Text("playLastDes".tr),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final ok =
                      await Get.find<PlayerController>().enqueueSong(episode);
                  snack(ok ? "playLastMsg".tr : "operationFailed".tr);
                },
              ),
              ListTile(
                leading:
                    Icon(queued ? Icons.playlist_remove : Icons.playlist_add),
                title: Text(queued ? "removeFromQueue".tr : "addToQueue".tr),
                onTap: () {
                  queued ? c.removeById(episode.id) : c.add(episode);
                  Navigator.of(ctx).pop();
                  onChanged?.call();
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
                      onChanged?.call();
                      return;
                    }
                    snack("downloadStarted".tr);
                    final ok = await PodcastDownloadService.download(episode);
                    snack(ok ? "downloadComplete".tr : "downloadFailed".tr);
                    onChanged?.call();
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
                    // Finished downloads may go, per the show's setting.
                    PodcastLibrary.sweepDownloads(
                        currentId:
                            Get.find<PlayerController>().currentSong.value?.id);
                  }
                  Navigator.of(ctx).pop();
                  onChanged?.call();
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
                        padding: const EdgeInsets.only(
                            left: RiffSpacing.xl,
                            top: RiffSpacing.lg,
                            right: RiffSpacing.xl,
                            bottom: RiffSpacing.unit * 10),
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
            padding: const EdgeInsets.only(
                left: HomeLayout.gutter,
                top: RiffSpacing.sm,
                right: RiffSpacing.xs,
                bottom: RiffSpacing.xxs),
            child: SizedBox(
              height: RiffComponentSizes.iconHit,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      episodeMetaLine([
                        "${items.length} ${'episodes'.tr}",
                        "${'remainingTime'.tr} ${_fmtTotal(controller.totalTime)}",
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: homeMutedColor(context)),
                    ),
                  ),
                  // Non-embedded gets the clear action in the AppBar instead.
                  if (embedded)
                    IconButton(
                      tooltip: "clear".tr,
                      icon: const Icon(Icons.delete_sweep_outlined,
                          size: RiffComponentSizes.headerIcon),
                      onPressed: controller.clear,
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: RiffSpacing.listEnd),
              itemCount: items.length,
              buildDefaultDragHandles: false,
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
      body: Column(children: [
        RiffPageHeader("queue".tr, actions: [
          Obx(() => controller.queue.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: "clear".tr,
                  icon: const Icon(Icons.clear_all_rounded),
                  onPressed: controller.clear,
                )),
        ]),
        Expanded(child: body),
      ]),
    );
  }

  Widget _row(BuildContext context, PodcastQueueController controller,
      MediaItem e, int i) {
    final art = Thumbnail(e.artUri?.toString() ?? '').medium;
    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: RiffSpacing.xxl),
        color: Theme.of(context).colorScheme.error.withOpacity(0.18),
        child: Icon(Icons.playlist_remove_rounded,
            color: Theme.of(context).colorScheme.error),
      ),
      onDismissed: (_) {
        final index = controller.queue.indexWhere((q) => q.id == e.id);
        controller.removeById(e.id);
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text("removedFromQueue".tr),
            action: SnackBarAction(
              label: "undo".tr,
              onPressed: () => controller.insertAt(index, e),
            ),
          ));
      },
      child: PodcastEpisodeTile(
        artUrl: art,
        title: e.title,
        meta: episodeMetaLine([
          e.artist,
          '${e.extras?['date'] ?? ''}',
          compactEpisodeLength(e.duration?.inSeconds ?? 0),
        ]),
        progress: PodcastProgressService.progress(e.id),
        onTap: () async {
          if (await openInWizeStreamIfPreferred(e)) return;
          final ok = await Get.find<PlayerController>()
              .playPlayListSong(items(controller), i);
          if (!ok) snackOperationFailed();
        },
        onLongPress: () => showAddToQueueSheet(context, e),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(right: RiffSpacing.sm),
                child: Icon(Icons.drag_indicator_rounded,
                    size: RiffComponentSizes.headerIcon,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            PodcastArt(url: art, size: RiffComponentSizes.rowArt),
          ],
        ),
        trailing: IconButton(
          tooltip: "removeFromQueue".tr,
          icon: Icon(Icons.remove_circle_outline_rounded,
              size: RiffComponentSizes.trailingIcon,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          onPressed: () => controller.removeAt(i),
        ),
      ),
    );
  }

  List<MediaItem> items(PodcastQueueController c) => c.queue.toList();
}
