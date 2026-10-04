import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/discovery/discovery_types.dart';
import '/services/podcast_progress_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/letter_art.dart';
import '/ui/widgets/riff_sheet.dart';
import '/ui/widgets/snackbar.dart';
import '../Audiobooks/audiobook_play.dart';
import '../Audiobooks/audiobooks_screen.dart' show resumeFreeAudiobook;
import 'home_feed_builder.dart';
import 'home_feed_data.dart';
import 'home_metrics.dart';
import 'podcast_continue.dart';

/// Jump back in: what you can resume, as a two-column grid of 56dp tiles
/// (one item fills the row). No header; tap resumes, long-press opens a
/// menu.
class HomeJumpBackIn extends StatelessWidget {
  const HomeJumpBackIn({super.key, required this.items, required this.metrics});

  final List<HomeItem> items;
  final HomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final resumables = [
      for (final i in items)
        if (i.value is HomeResumable) i.value as HomeResumable
    ];
    if (resumables.isEmpty) return const SizedBox.shrink();
    final single = resumables.length == 1;
    final width = single ? metrics.inner : metrics.jumpTile;
    return Padding(
      padding: const EdgeInsets.only(
          left: RiffSpacing.gutter,
          top: RiffSpacing.sm,
          right: RiffSpacing.gutter),
      child: Wrap(
        spacing: RiffSpacing.gridGap,
        runSpacing: RiffSpacing.gridGap,
        children: [
          for (final r in resumables)
            SizedBox(width: width, child: JumpBackInTile(item: r)),
        ],
      ),
    );
  }
}

class JumpBackInTile extends StatelessWidget {
  const JumpBackInTile({super.key, required this.item});
  final HomeResumable item;

  Future<void> _resume() async {
    if (!Get.isRegistered<PlayerController>()) return;
    final player = Get.find<PlayerController>();
    switch (item.kind) {
      case ResumeKind.session:
        if (!await player.resumeSavedSession()) snackOperationFailed();
      case ResumeKind.episode:
        // Newest-first in-progress list, starting at this episode.
        final queue = podcastContinueQueue(PodcastProgressService.inProgress());
        final at = queue.indexWhere((e) => e.id == item.id);
        if (at < 0) return;
        final pos = PodcastProgressService.positionMs(item.id) ?? 0;
        if (pos > 0) player.armResume(item.id, pos);
        final ok = await player.playPlayListSong(queue, at,
            source: DiscoverySource.podcast);
        if (!ok) snackOperationFailed();
      case ResumeKind.book:
        final record = item.record ?? const {};
        final ok = '${record['id']}'.startsWith('lv_')
            ? await resumeFreeAudiobook(record)
            : await playAudiobook(bookId: item.id);
        if (!ok) snackOperationFailed();
    }
  }

  void _menu(BuildContext context) {
    final player = Get.isRegistered<PlayerController>()
        ? Get.find<PlayerController>()
        : null;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      shape: riffSheetShape,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RiffSheetHandle(),
            RiffSheetTitle(item.title),
            RiffSheetTile(
              icon: Icons.play_arrow_rounded,
              title: 'resume'.tr,
              onTap: () {
                Navigator.of(sheet).pop();
                _resume();
              },
            ),
            if (item.kind == ResumeKind.episode)
              RiffSheetTile(
                icon: Icons.done_all_rounded,
                title: 'markAsPlayed'.tr,
                onTap: () {
                  Navigator.of(sheet).pop();
                  PodcastProgressService.markPlayed(item.id);
                  homeFeedRev.value++;
                },
              ),
            if (item.kind == ResumeKind.session)
              RiffSheetTile(
                icon: Icons.close_rounded,
                title: 'dismiss'.tr,
                onTap: () {
                  Navigator.of(sheet).pop();
                  player?.dismissContinueListening();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    // 56dp, or taller when large system text needs two full lines.
    final height = (scaler.scale(14) * 1.25 * 2 + 12)
        .clamp(RiffSizes.jumpTileHeight, 120.0);
    final art = item.art;
    final radius = BorderRadius.circular(RiffSizes.tileRadius);
    return Semantics(
      button: true,
      label: item.kind == ResumeKind.session
          ? 'continueItem'.trParams({'title': item.title})
          : item.title,
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _resume,
          onLongPress: () => _menu(context),
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: RiffSizes.jumpArt,
                      height: height,
                      child: Center(
                        child: art != null
                            ? ImageWidget(
                                song: art,
                                size: RiffSizes.jumpArt,
                                borderRadius: 0)
                            : LetterArt(
                                title: item.title, size: RiffSizes.jumpArt),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.progress != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: RiffSizes.progressBar,
                      color: theme.colorScheme.secondary,
                      backgroundColor:
                          theme.colorScheme.onSurface.withOpacity(0.12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
