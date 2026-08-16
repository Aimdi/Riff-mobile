import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:widget_marquee/widget_marquee.dart';

import 'image_widget.dart';
import 'snackbar.dart';
import 'songinfo_bottom_sheet.dart';

const double _kQueueRowExtent = 72;
const double _kSectionLabelExtent = 28;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sectionLabel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Text(
              sectionLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(homeScaffoldContext)
                  .textTheme
                  .labelMedium
                  ?.copyWith(
                    color: isCurrent ? accent : RiffSurfaces.textMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
            ),
          ),
        Expanded(
          child: Opacity(
            opacity: isPlayed ? 0.55 : 1,
            child: Dismissible(
              key: ValueKey('dismiss_${song.id}'),
              direction: DismissDirection.horizontal,
              confirmDismiss: (direction) async => !isCurrent,
              onDismissed: (direction) {
                playerController.removeFromQueue(song);
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isCurrent
                      ? RiffSurfaces.elevatedSoft
                      : Theme.of(homeScaffoldContext)
                          .bottomSheetTheme
                          .backgroundColor,
                  border: Border(
                    left: BorderSide(
                      color: isCurrent ? accent : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: ListTile(
                  onTap: () {
                    playerController.seekByIndex(index);
                  },
                  onLongPress: () {
                    final sheetContext =
                        playerController.homeScaffoldkey.currentContext ??
                            Get.context;
                    if (sheetContext == null) return;
                    showModalBottomSheet(
                      useRootNavigator: true,
                      constraints: const BoxConstraints(maxWidth: 500),
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(10.0)),
                      ),
                      isScrollControlled: true,
                      context: sheetContext,
                      barrierColor: Colors.transparent.withAlpha(100),
                      builder: (context) => SongInfoBottomSheet(
                        song,
                        calledFromQueue: true,
                      ),
                    ).whenComplete(() => Get.delete<SongInfoController>());
                  },
                  contentPadding: EdgeInsets.only(
                      top: 0,
                      left: GetPlatform.isAndroid ? 30 : 0,
                      right: 25),
                  tileColor: Colors.transparent,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (GetPlatform.isDesktop)
                        IconButton(
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
                      ImageWidget(
                        size: 50,
                        song: song,
                      ),
                    ],
                  ),
                  title: Marquee(
                    delay: const Duration(milliseconds: 300),
                    duration: const Duration(seconds: 5),
                    id: "queue${song.title.hashCode}",
                    child: Text(
                      song.title,
                      maxLines: 1,
                      style: Theme.of(homeScaffoldContext)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: RiffSurfaces.textPrimary,
                            fontWeight:
                                isCurrent ? FontWeight.w700 : FontWeight.w500,
                          ),
                    ),
                  ),
                  subtitle: Text(
                    song.artist ?? '',
                    maxLines: 1,
                    style: Theme.of(homeScaffoldContext)
                        .textTheme
                        .titleSmall
                        ?.copyWith(
                          color: isCurrent
                              ? RiffSurfaces.textMuted.withOpacity(0.75)
                              : RiffSurfaces.textMuted,
                        ),
                  ),
                  trailing: ReorderableDragStartListener(
                    enabled: !GetPlatform.isDesktop,
                    index: index,
                    child: Container(
                      padding: EdgeInsets.only(
                          right: (GetPlatform.isDesktop) ? 20 : 5, left: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (!GetPlatform.isDesktop)
                            const Icon(
                              Icons.drag_handle,
                              color: RiffSurfaces.textMuted,
                            ),
                          isCurrent
                              ? Icon(
                                  Icons.equalizer,
                                  color: accent,
                                )
                              : Text(
                                  song.extras?['length'] ?? "",
                                  style: Theme.of(homeScaffoldContext)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                          color: RiffSurfaces.textMuted),
                                ),
                        ],
                      ),
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
