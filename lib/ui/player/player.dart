import 'package:get/get.dart';
import 'package:flutter/material.dart';

import '/ui/player/components/gesture_player.dart';
import '/ui/player/components/standard_player.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/utils/theme_controller.dart';
import '../../utils/helper.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/snackbar.dart';
import '../widgets/up_next_queue.dart';
import '/ui/player/player_controller.dart';
import '/ui/player/upcoming_queue.dart';
import '../widgets/sliding_up_panel.dart';

/// Player screen
/// Contains the player ui
///
/// Player ui can be standard player or gesture player
class Player extends StatelessWidget {
  const Player({super.key});

  @override
  Widget build(BuildContext context) {
    printINFO("player");
    final size = MediaQuery.of(context).size;
    final PlayerController playerController = Get.find<PlayerController>();
    final settingsScreenController = Get.find<SettingsScreenController>();
    final accent = Theme.of(context).colorScheme.secondary;
    return Scaffold(
      /// SlidingUpPanel is used to create a panel that can slide up and down
      /// It is used to show the current queue panel in mobile
      body: Obx(
        () => SlidingUpPanel(
          boxShadow: const [],
          minHeight: settingsScreenController.playerUi.value == 0
              ? 65 + Get.mediaQuery.padding.bottom
              : 0,
          maxHeight: size.height,
          isDraggable: !GetPlatform.isDesktop,
          controller: GetPlatform.isDesktop
              ? null
              : playerController.queuePanelController,

          /// Collapsed queue strip — elevated surface, hairline top, drag pill.
          collapsed: InkWell(
            onTap: () {
              /// queue open in end drawer in desktop
              if (GetPlatform.isDesktop) {
                playerController.homeScaffoldkey.currentState?.openEndDrawer();
              } else {
                playerController.queuePanelController.open();
              }
            },
            child: Container(
                decoration: const BoxDecoration(
                  color: RiffSurfaces.elevated,
                  border: Border(
                    top: BorderSide(
                      color: RiffSurfaces.hairline,
                      width: RiffTokens.hairline,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 65,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: RiffSurfaces.hairline,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "upNext".tr,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: RiffSurfaces.textMuted,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                          ),
                          Obx(() {
                            final upcoming = playerController.upcomingQueue;
                            if (upcoming.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(20, 1, 20, 0),
                              child: Text(
                                upcomingPreviewLabel(
                                    upcoming.first.title, upcoming.length),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: RiffSurfaces.textPrimary
                                          .withOpacity(0.85),
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                )),
          ),

          /// Panel for queue
          panelBuilder: (ScrollController sc, onReorderStart, onReorderEnd) {
            playerController.scrollController = sc;
            return Stack(
              children: [
                /// Stack first child
                /// UpNextQueue widget contains list of songs in queue
                UpNextQueue(
                  onReorderEnd: onReorderEnd,
                  onReorderStart: onReorderStart,
                ),

                /// Stack second child
                /// Bottom bar: queue loop / shuffle / clear — solid frost
                /// (BackdropFilter blur was a queue-panel jank source).
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Builder(builder: (context) {
                    final theme = Theme.of(context);
                    final frost = theme.cardColor.withOpacity(
                      theme.brightness == Brightness.dark ? 0.94 : 0.97,
                    );
                    return Container(
                      padding: const EdgeInsets.only(
                          top: 15, bottom: 10, left: 10, right: 10),
                      decoration: BoxDecoration(
                          color: frost,
                          border: const Border(
                            top: BorderSide(
                              color: RiffSurfaces.hairline,
                              width: RiffTokens.hairline,
                            ),
                          )),
                      height: 60 + Get.mediaQuery.padding.bottom,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            /// number of songs in queue
                            Obx(
                              () => Text(
                                "${playerController.currentQueue.length} ${"songs".tr}",
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall!
                                    .copyWith(
                                        color: RiffSurfaces.textPrimary),
                              ),
                            ),

                            /// queue loop button
                            InkWell(
                              onTap: () {
                                playerController.toggleQueueLoopMode();
                              },
                              child: Obx(
                                () {
                                  final active = playerController
                                      .isQueueLoopModeEnabled.isTrue;
                                  return Container(
                                    height: 30,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 15),
                                    decoration: BoxDecoration(
                                      color: RiffSurfaces.elevatedSoft,
                                      borderRadius: BorderRadius.circular(
                                          RiffTokens.radiusSm),
                                      border: Border.all(
                                        color: active
                                            ? accent
                                            : Colors.transparent,
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Center(
                                        child: Text(
                                      "queueLoop".tr,
                                      style: TextStyle(
                                        color: active
                                            ? RiffSurfaces.textPrimary
                                            : RiffSurfaces.textMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )),
                                  );
                                },
                              ),
                            ),

                            /// queue shuffle button
                            InkWell(
                              onTap: () {
                                if (playerController
                                    .isShuffleModeEnabled.isTrue) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(context,
                                          "queueShufflingDeniedMsg".tr,
                                          size: SanckBarSize.BIG));
                                  return;
                                }
                                playerController.shuffleQueue();
                              },
                              child: Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 15),
                                decoration: BoxDecoration(
                                  color: RiffSurfaces.elevatedSoft,
                                  borderRadius: BorderRadius.circular(
                                      RiffTokens.radiusSm),
                                ),
                                child: const Center(
                                    child: Icon(Icons.shuffle,
                                        size: 18,
                                        color: RiffSurfaces.textPrimary)),
                              ),
                            ),

                            /// save queue as playlist
                            InkWell(
                              onTap: () {
                                final queue =
                                    playerController.currentQueue.toList();
                                if (queue.isEmpty) return;
                                showAddToPlaylistSheet(context, queue);
                              },
                              child: Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 15),
                                decoration: BoxDecoration(
                                  color: RiffSurfaces.elevatedSoft,
                                  borderRadius: BorderRadius.circular(
                                      RiffTokens.radiusSm),
                                ),
                                child: const Center(
                                    child: Icon(Icons.playlist_add,
                                        size: 18,
                                        color: RiffSurfaces.textPrimary)),
                              ),
                            ),

                            /// clear queue button
                            InkWell(
                              onTap: () {
                                playerController.clearQueue();
                              },
                              child: Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 15),
                                decoration: BoxDecoration(
                                  color: RiffSurfaces.elevatedSoft,
                                  borderRadius: BorderRadius.circular(
                                      RiffTokens.radiusSm),
                                ),
                                child: const Center(
                                    child: Icon(Icons.playlist_remove,
                                        size: 18,
                                        color: RiffSurfaces.textPrimary)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },

          /// show player ui based on selected player ui in settings
          /// Gesture player is only applicable for mobile
          body: settingsScreenController.playerUi.value == 0
              ? const StandardPlayer()
              : const GesturePlayer(),
        ),
      ),
    );
  }
}
