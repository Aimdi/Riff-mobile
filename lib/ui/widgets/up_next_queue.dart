import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_spacing.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:widget_marquee/widget_marquee.dart';

import 'image_widget.dart';
import 'snackbar.dart';
import 'song_list_tile.dart' show RiffRowHairline;
import 'songinfo_bottom_sheet.dart';

const double _kQueueRowExtent = 64;
const double _kSectionLabelExtent = 34;

String _queueTr(String key, String fallback) {
  final translated = key.tr;
  return translated == key ? fallback : translated;
}

class UpNextQueue extends StatelessWidget {
  const UpNextQueue(
      {super.key,
      this.onReorderEnd,
      this.onReorderStart,
      this.isQueueInSlidePanel = true});
  final void Function(int)? onReorderStart;
  final void Function(int)? onReorderEnd;
  final bool isQueueInSlidePanel;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final accent = Theme.of(context).colorScheme.secondary;
    return Container(
      color: Theme.of(context).bottomSheetTheme.backgroundColor,
      child: Obx(() {
        final currentIndex = playerController.currentSongIndex.value;
        final queueLength = playerController.currentQueue.length;
        final remaining = currentIndex >= 0 && currentIndex < queueLength
            ? queueLength - currentIndex - 1
            : 0;
        return ReorderableListView.builder(
          footer: SizedBox(height: Get.mediaQuery.padding.bottom),
          scrollController:
              isQueueInSlidePanel ? playerController.scrollController : null,
          onReorder: (int oldIndex, int newIndex) {
            if (playerController.isShuffleModeEnabled.isTrue) {
              ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
                  Get.context!, "queuerearrangingDeniedMsg".tr,
                  size: SanckBarSize.BIG));
              return;
            }
            playerController.onReorder(oldIndex, newIndex);
          },
          onReorderStart: onReorderStart,
          onReorderEnd: onReorderEnd,
          itemCount: queueLength,
          // Extra height only on the Now playing / Next up section rows.
          itemExtentBuilder: (index, _) {
            if (index == currentIndex) {
              return _kQueueRowExtent + _kSectionLabelExtent;
            }
            if (index == currentIndex + 1) {
              return _kQueueRowExtent + _kSectionLabelExtent;
            }
            return _kQueueRowExtent;
          },
          padding: EdgeInsets.only(
              top: isQueueInSlidePanel ? 55 : 0,
              bottom: isQueueInSlidePanel ? 80 : 0),
          physics: const AlwaysScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            final homeScaffoldContext =
                playerController.homeScaffoldkey.currentContext ?? context;
            final song = playerController.currentQueue[index];
            final isCurrent = currentIndex == index;
            final isFirstUpcoming = index == currentIndex + 1;
            final isPlayed = currentIndex >= 0 && index < currentIndex;
            String? sectionLabel;
            if (isCurrent) {
              sectionLabel = _queueTr('nowPlaying', 'Now playing');
            } else if (isFirstUpcoming) {
              sectionLabel = '${_queueTr('nextUp', 'Next up')} · $remaining';
            }
            return Material(
              // Stable id key — index keys remount every reorder.
              key: ValueKey(song.id),
              child: _QueueSongRow(
                index: index,
                song: song,
                isCurrent: isCurrent,
                isPlayed: isPlayed,
                sectionLabel: sectionLabel,
                accent: accent,
                homeScaffoldContext: homeScaffoldContext,
                playerController: playerController,
              ),
            );
          },
        );
      }),
    );
  }
}

class _QueueSongRow extends StatelessWidget {
  const _QueueSongRow({
    required this.index,
    required this.song,
    required this.isCurrent,
    required this.isPlayed,
    required this.sectionLabel,
    required this.accent,
    required this.homeScaffoldContext,
    required this.playerController,
  });

  static const _playedOpacity = AlwaysStoppedAnimation<double>(0.55);

  final int index;
  final MediaItem song;
  final bool isCurrent;
  final bool isPlayed;
  final String? sectionLabel;
  final Color accent;
  final BuildContext homeScaffoldContext;
  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final text = Theme.of(context).textTheme;
    void openMenu() {
      final sheetContext =
          playerController.homeScaffoldkey.currentContext ?? Get.context;
      if (sheetContext == null) return;
      showModalBottomSheet(
        useRootNavigator: true,
        constraints: const BoxConstraints(maxWidth: 500),
        isScrollControlled: true,
        context: sheetContext,
        builder: (context) => SongInfoBottomSheet(
          song,
          calledFromQueue: true,
        ),
      ).whenComplete(() => Get.delete<SongInfoController>());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sectionLabel != null)
          Container(
            height: _kSectionLabelExtent,
            color:
                Theme.of(homeScaffoldContext).bottomSheetTheme.backgroundColor,
            child: Padding(
              padding: const EdgeInsets.only(
                  left: RiffSpacing.lg,
                  top: RiffSpacing.md,
                  right: RiffSpacing.lg,
                  bottom: RiffSpacing.xs),
              child: Text(
                sectionLabel!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(color: muted),
              ),
            ),
          ),
        Expanded(
          // FadeTransition with a constant animation: the row becomes its own
          // repaint boundary with a retained opacity layer, instead of an
          // Opacity re-rasterizing the row via saveLayer on every repaint.
          child: FadeTransition(
            opacity: isPlayed ? _playedOpacity : kAlwaysCompleteAnimation,
            child: Dismissible(
              key: ValueKey('dismiss_${song.id}'),
              direction: DismissDirection.horizontal,
              confirmDismiss: (direction) async => !isCurrent,
              onDismissed: (direction) {
                playerController.removeFromQueue(song);
              },
              child: Stack(
                // Expand so the row still fills the fixed queue extent.
                fit: StackFit.expand,
                children: [
                  Material(
                    // Now playing: flat accentMuted tint (§5.2).
                    color: isCurrent
                        ? RiffColors.of(context).accentMuted
                        : Theme.of(homeScaffoldContext)
                            .bottomSheetTheme
                            .backgroundColor,
                    child: InkWell(
                      onTap: () => playerController.seekByIndex(index),
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        openMenu();
                      },
                      child: Padding(
                        // 16h like every row; the drag handle brings its own
                        // trailing room. Vertical padding comes from the fixed
                        // 64dp queue extent (48 art centred).
                        padding: const EdgeInsets.only(
                            left: RiffSpacing.lg, right: RiffSpacing.xs),
                        child: Row(
                          children: [
                            if (GetPlatform.isDesktop)
                              IconButton(
                                  tooltip: 'removeFromQueue'.tr,
                                  onPressed: () {
                                    if (isCurrent) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(snackbar(context,
                                              "songRemovedfromQueueCurrSong".tr,
                                              size: SanckBarSize.BIG));
                                    } else {
                                      playerController.removeFromQueue(song);
                                    }
                                  },
                                  icon: const Icon(Icons.close)),
                            ImageWidget(
                              size: RiffComponentSizes.rowArt,
                              song: song,
                              borderRadius: RiffRadii.xs,
                            ),
                            const SizedBox(width: RiffSpacing.md),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Marquee(
                                    delay: const Duration(milliseconds: 300),
                                    duration: const Duration(seconds: 5),
                                    id: "queue${song.title.hashCode}",
                                    child: Text(
                                      song.title,
                                      maxLines: 1,
                                      style: text.titleMedium?.copyWith(
                                        color: isCurrent ? accent : fg,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: RiffSpacing.xxs),
                                  Text(
                                    song.artist ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodyMedium?.copyWith(
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: RiffSpacing.sm),
                            if (isCurrent)
                              Icon(Icons.equalizer_rounded,
                                  color: accent,
                                  size: RiffComponentSizes.trailingIcon)
                            else
                              Text(
                                '${song.extras?['length'] ?? ''}',
                                style: text.bodyMedium?.copyWith(color: muted),
                              ),
                            if (!GetPlatform.isDesktop)
                              ReorderableDragStartListener(
                                index: index,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: RiffSpacing.md,
                                      vertical: RiffSpacing.lg),
                                  child: Icon(Icons.drag_handle_rounded,
                                      color: muted,
                                      size: RiffComponentSizes.trailingIcon),
                                ),
                              )
                            else
                              const SizedBox(width: RiffSpacing.lg),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Inset hairline from the text column, inside the row's
                  // bottom edge (desktop rows lead with a remove button, so
                  // theirs runs full width).
                  RiffRowHairline(
                      inset: GetPlatform.isDesktop
                          ? 0
                          : RiffRowHairline.textInset),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
