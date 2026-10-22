import '/ui/player/long_form_queue.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '/models/thumbnail.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/services/podcast_download_service.dart';
import '/services/podcast_library.dart';
import '/services/podcast_progress_service.dart';
import '/services/podcast_share.dart';
import '/services/podcast_starred.dart';
import '/services/wizestream_service.dart';
import '../Home/home_layout.dart';
import 'podcast_empty_state.dart';
import 'podcast_layout.dart';
import '/ui/player/components/show_notes_text.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/sheet_insets.dart';
import '/ui/widgets/podcast_play.dart';
import '/ui/widgets/riff_motion.dart';
import '/ui/widgets/snackbar.dart';
import 'podcast_download_undo.dart';
import 'podcast_queue_controller.dart';
import 'podcast_starred_screen.dart' show toggleStarredEpisode;
import 'podcasts_screen.dart';

/// Long-press action sheet for a podcast episode: queue, download, play next,
/// mark played, and shownotes. Opens immediately — download/queue state is
/// resolved inside the builder so the sheet never waits on disk I/O.
///
/// [onChanged] runs after an action that changes the episode's state
/// (played, queued, downloaded) so the list behind can refresh. With
/// [onRemoveFromInbox] (the Inbox's own rows) it offers Remove from Inbox.
void showAddToQueueSheet(BuildContext context, MediaItem episode,
    {VoidCallback? onChanged, VoidCallback? onRemoveFromInbox}) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    // Root overlay sits above the SlidingUpPanel mini player; nested
    // navigator sheets were leaving Download under the playing bar.
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) {
      final c = Get.find<PodcastQueueController>();
      final queued = c.isQueued(episode.id);
      final downloaded = PodcastDownloadService.isDownloaded(episode.id);
      final canDownload =
          (episode.extras?['url'] as String?)?.isNotEmpty ?? false;
      final notes = episodeNotes(episode).trim();
      final feedUrl = (episode.extras?['feedUrl'] ?? '').toString().trim();
      final starred = StarredEpisodes.isStarred(episode.id);
      void snack(String msg) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          snackbar(context, msg, size: SanckBarSize.MEDIUM),
        );
      }

      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            top: RiffSpacing.sm,
            // Root navigator already clears the mini player — only safe area.
            bottom: RiffSpacing.sm +
                sheetBottomInset(ctx, liftAboveMiniPlayer: false),
          ),
          // Sheet rows per RIFF_UI_RESTYLE.md §5.10.
          child: ListTileTheme.merge(
            titleTextStyle: Theme.of(ctx).textTheme.bodyLarge,
            iconColor: Theme.of(ctx).colorScheme.onSurface,
            child: IconTheme.merge(
              data: const IconThemeData(size: RiffComponentSizes.headerIcon),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: RiffComponentSizes.handleWidth,
                    height: RiffComponentSizes.handleHeight,
                    margin: const EdgeInsets.only(bottom: RiffSpacing.sm),
                    decoration: BoxDecoration(
                      color: RiffColors.of(ctx).handle,
                      borderRadius: BorderRadius.circular(RiffRadii.pill),
                    ),
                  ),
                  if (WizeStream.isInstalled &&
                      WizeStream.watchUrlFor(episode) != null)
                    ListTile(
                      leading: const Icon(Icons.open_in_new_rounded),
                      title: Text("openInWizeStream".tr),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        final ok = await WizeStream.open(
                            WizeStream.watchUrlFor(episode)!);
                        if (!ok) snack("operationFailed".tr);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.playlist_play),
                    title: Text("playNext".tr),
                    onTap: () async {
                      HapticFeedback.lightImpact();
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
                      HapticFeedback.lightImpact();
                      Navigator.of(ctx).pop();
                      final ok = await Get.find<PlayerController>()
                          .enqueueSong(episode);
                      snack(ok ? "playLastMsg".tr : "operationFailed".tr);
                    },
                  ),
                  ListTile(
                    iconColor: queued ? Theme.of(ctx).colorScheme.error : null,
                    textColor: queued ? Theme.of(ctx).colorScheme.error : null,
                    leading: Icon(
                        queued ? Icons.playlist_remove : Icons.playlist_add),
                    title:
                        Text(queued ? "removeFromQueue".tr : "addToQueue".tr),
                    onTap: () {
                      if (!queued) HapticFeedback.lightImpact();
                      queued ? c.removeById(episode.id) : c.add(episode);
                      Navigator.of(ctx).pop();
                      onChanged?.call();
                      snack(queued ? "removedFromQueue".tr : "addedToQueue".tr);
                    },
                  ),
                  if (canDownload || downloaded)
                    ListTile(
                      iconColor:
                          downloaded ? Theme.of(ctx).colorScheme.error : null,
                      textColor:
                          downloaded ? Theme.of(ctx).colorScheme.error : null,
                      leading: Icon(downloaded
                          ? Icons.delete_outline
                          : Icons.download_outlined),
                      title: Text(
                          downloaded ? "removeDownload".tr : "download".tr),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        if (downloaded) {
                          await removePodcastDownloadWithUndo(episode.id,
                              context: context, onChanged: onChanged);
                          return;
                        }
                        HapticFeedback.lightImpact();
                        snack("downloadStarted".tr);
                        final ok =
                            await PodcastDownloadService.download(episode);
                        snack(ok ? "downloadComplete".tr : "downloadFailed".tr);
                        onChanged?.call();
                      },
                    ),
                  // Out of the Inbox, unplayed (AntennaPod's Remove from
                  // inbox, Pocket Casts' Archive).
                  if (onRemoveFromInbox != null)
                    ListTile(
                      leading: const Icon(Icons.inbox_outlined),
                      title: Text("removeFromInbox".tr),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onRemoveFromInbox();
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
                            currentId: Get.find<PlayerController>()
                                .currentSong
                                .value
                                ?.id);
                      }
                      Navigator.of(ctx).pop();
                      onChanged?.call();
                    },
                  ),
                  // Pocket Casts' star: kept in Podcasts › Starred.
                  ListTile(
                    leading: Icon(starred
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded),
                    title:
                        Text(starred ? "unstarEpisode".tr : "starEpisode".tr),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      toggleStarredEpisode(context, episode);
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
                                  const SizedBox(height: RiffSpacing.xs),
                                  Text(episode.artist!,
                                      style:
                                          Theme.of(sctx).textTheme.titleSmall),
                                ],
                                const Divider(height: RiffSpacing.xxl),
                                if (notes.isEmpty)
                                  Text("noShownotes".tr,
                                      style: Theme.of(sctx).textTheme.bodyLarge)
                                else
                                  // A timestamp plays the episode from
                                  // there; a link opens.
                                  ShowNotesText(
                                    notes: notes,
                                    length: episode.duration,
                                    style: Theme.of(sctx).textTheme.bodyLarge,
                                    onTime: (seconds) {
                                      Navigator.of(sctx).pop();
                                      Get.find<PlayerController>()
                                          .playPodcastAt(episode,
                                              Duration(seconds: seconds));
                                    },
                                    onLink: (url) => launchUrl(Uri.parse(url),
                                        mode: LaunchMode.externalApplication),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // As from the player's ⋮ (Pocket Casts' episode menu).
                  ListTile(
                    leading: const Icon(Icons.ios_share_rounded),
                    title: Text("shareEpisode".tr),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Share.share(podcastEpisodeShareText(episode));
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
  const PodcastQueueScreen({super.key, this.onDiscover});

  /// Jumps to the Discover tab from the empty state.
  final VoidCallback? onDiscover;

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
                  _QueueSortButton(controller),
                  IconButton(
                    tooltip: "clear".tr,
                    icon: const Icon(Icons.delete_sweep_outlined,
                        size: RiffComponentSizes.headerIcon),
                    // With Undo, as the music queue's Clear.
                    onPressed: () {
                      final target = undoSnackbarTarget(context);
                      final undo = controller.clearUndoable();
                      if (undo == null) return;
                      showUndoSnackbar(target, 'queueCleared'.tr, onUndo: undo);
                    },
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
    return body;
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
      onDismissed: (_) => _removeWithUndo(context, controller, e),
      child: _FadeInOnce(
        fade: _restored.remove(e.id),
        child: PodcastEpisodeTile(
          artUrl: art,
          title: e.title,
          show: e.artist ?? '',
          meta: episodeMetaLine([
            episodeDateLabel(e.extras?['date']),
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
            onPressed: () => _removeWithUndo(context, controller, e),
          ),
        ),
      ),
    );
  }

  /// Takes [e] out of the queue with Undo (swipe or ✕ alike).
  void _removeWithUndo(
      BuildContext context, PodcastQueueController controller, MediaItem e) {
    final target = undoSnackbarTarget(context);
    final index = controller.queue.indexWhere((q) => q.id == e.id);
    if (index < 0) return;
    controller.removeById(e.id);
    showUndoSnackbar(target, "removedFromQueue".tr, onUndo: () {
      _restored.add(e.id);
      controller.insertAt(index, e);
    });
  }

  /// Episodes Undo just put back: each fades in where it returns, the first
  /// time its row is built, rather than popping back.
  static final _restored = <String>{};

  List<MediaItem> items(PodcastQueueController c) => c.queue.toList();
}

/// [child], faded in if [fade] was set as it first showed (a row Undo put
/// back); otherwise just [child], as before.
class _FadeInOnce extends StatefulWidget {
  const _FadeInOnce({required this.fade, required this.child});

  final bool fade;
  final Widget child;

  @override
  State<_FadeInOnce> createState() => _FadeInOnceState();
}

class _FadeInOnceState extends State<_FadeInOnce> {
  late final bool _fade = widget.fade;

  @override
  Widget build(BuildContext context) =>
      _fade ? RiffFadeIn(child: widget.child) : widget.child;
}

/// "Newest first", "By show", … for [sort].
String podcastQueueSortLabel(PodcastQueueSort sort) => switch (sort) {
      PodcastQueueSort.newest => 'newestFirst'.tr,
      PodcastQueueSort.oldest => 'oldestFirst'.tr,
      PodcastQueueSort.shortest => 'shortestFirst'.tr,
      PodcastQueueSort.longest => 'longestFirst'.tr,
      PodcastQueueSort.show => 'byShow'.tr,
      PodcastQueueSort.shuffle => 'shuffle'.tr,
    };

/// The queue header's sort menu, as AntennaPod sorts its queue: once, with
/// Undo, as the header's Clear.
class _QueueSortButton extends StatelessWidget {
  const _QueueSortButton(this.controller);

  final PodcastQueueController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PodcastQueueSort>(
      tooltip: 'sortBy'.tr,
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.sort_rounded, size: RiffComponentSizes.headerIcon),
      onSelected: (sort) {
        final target = undoSnackbarTarget(context);
        final undo = controller.sortUndoable(sort);
        if (undo == null) return;
        showUndoSnackbar(target, 'queueSorted'.tr, onUndo: undo);
      },
      itemBuilder: (_) => [
        for (final sort in PodcastQueueSort.values)
          PopupMenuItem<PodcastQueueSort>(
            height: RiffComponentSizes.sheetRow,
            value: sort,
            child: Text(podcastQueueSortLabel(sort)),
          ),
      ],
    );
  }
}
