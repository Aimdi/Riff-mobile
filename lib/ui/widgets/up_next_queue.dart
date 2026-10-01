import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:widget_marquee/widget_marquee.dart';

import 'image_widget.dart';
import 'riff_sheet.dart';
import 'snackbar.dart';
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
              sectionLabel =
                  '${_queueTr('nextUp', 'Next up')} · $remaining';
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
    const fg = RiffSurfaces.textPrimary;
    void openMenu() {
      final sheetContext =
          playerController.homeScaffoldkey.currentContext ?? Get.context;
      if (sheetContext == null) return;
      showModalBottomSheet(
        useRootNavigator: true,
        constraints: const BoxConstraints(maxWidth: 500),
        shape: riffSheetShape,
        isScrollControlled: true,
        context: sheetContext,
        barrierColor: Colors.transparent.withAlpha(100),
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
            color: Theme.of(homeScaffoldContext)
                .bottomSheetTheme
                .backgroundColor,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              // Explicit size: the theme's labelMedium is 22sp bold.
              child: Text(
                sectionLabel!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: isCurrent ? accent : RiffSurfaces.textMuted,
                ),
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
              child: Material(
                color: isCurrent
                    ? RiffSurfaces.elevatedSoft
                    : Theme.of(homeScaffoldContext)
                        .bottomSheetTheme
                        .backgroundColor,
                child: InkWell(
                  onTap: () => playerController.seekByIndex(index),
                  onLongPress: openMenu,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 4),
                    child: Row(
                      children: [
                        if (GetPlatform.isDesktop)
                          IconButton(
                              tooltip: 'removeFromQueue'.tr,
                              onPressed: () {
                                if (isCurrent) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(context,
                                          "songRemovedfromQueueCurrSong".tr,
                                          size: SanckBarSize.BIG));
                                } else {
                                  playerController.removeFromQueue(song);
                                }
                              },
                              icon: const Icon(Icons.close)),
                        ImageWidget(size: 48, song: song),
                        const SizedBox(width: 14),
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
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isCurrent
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: isCurrent ? accent : fg,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: RiffSurfaces.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isCurrent)
                          Icon(Icons.equalizer_rounded, color: accent, size: 22)
                        else
                          Text(
                            '${song.extras?['length'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: RiffSurfaces.textMuted,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        if (!GetPlatform.isDesktop)
                          ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 16),
                              child: Icon(Icons.drag_handle_rounded,
                                  color: RiffSurfaces.textMuted, size: 22),
                            ),
                          )
                        else
                          const SizedBox(width: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
