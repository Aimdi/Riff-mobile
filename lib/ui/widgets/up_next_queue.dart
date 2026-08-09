import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:widget_marquee/widget_marquee.dart';

import 'image_widget.dart';
import 'snackbar.dart';
import 'songinfo_bottom_sheet.dart';

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
          itemCount: playerController.currentQueue.length,
          // Fixed row height — cheaper scroll layout for long queues.
          itemExtent: 72,
          padding: EdgeInsets.only(
              top: isQueueInSlidePanel ? 55 : 0,
              bottom: isQueueInSlidePanel ? 80 : 0),
          physics: const AlwaysScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            final homeScaffoldContext =
                playerController.homeScaffoldkey.currentContext!;
            final song = playerController.currentQueue[index];
            return Material(
              // Stable id key — index keys remount every reorder.
              key: ValueKey(song.id),
              child: Obx(
                () {
                  final isCurrent =
                      playerController.currentSongIndex.value == index;
                  return Dismissible(
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
                        final sheetContext = playerController
                                .homeScaffoldkey.currentContext ??
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
                              ?.copyWith(color: RiffSurfaces.textPrimary),
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
                );
                },
              ),
            );
          },
        );
      }),
    );
  }
}
