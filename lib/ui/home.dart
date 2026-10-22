import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/ui/screens/Home/home_screen_controller.dart';
import '../utils/helper.dart';
import '../ui/navigator.dart';
import '../ui/player/player.dart';
import '/ui/theme/riff_spacing.dart';
import 'player/components/mini_player.dart';
import 'player/player_controller.dart';
import 'widgets/sliding_up_panel.dart';
import 'widgets/queue_undo.dart';
import 'widgets/snackbar.dart';
import 'widgets/up_next_queue.dart';

class Home extends StatelessWidget {
  const Home({super.key});
  static const routeName = '/appHome';
  @override
  Widget build(BuildContext context) {
    printINFO("Home");
    final PlayerController playerController = Get.find<PlayerController>();
    final homeScreenController = Get.find<HomeScreenController>();
    final size = MediaQuery.of(context).size;
    final isWideScreen = size.width > 800;
    if (!playerController.initFlagForPlayer) {
      if (isWideScreen) {
        playerController.playerPanelMinHeight.value =
            105 + Get.mediaQuery.padding.bottom;
      } else {
        playerController.playerPanelMinHeight.value =
            75 + Get.mediaQuery.padding.bottom;
      }
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (playerController.playerPanelController.isPanelOpen) {
          playerController.playerPanelController.close();
        } else {
          if (Get.nestedKey(ScreenNavigationSetup.id)!.currentState!.canPop()) {
            Get.nestedKey(ScreenNavigationSetup.id)!.currentState!.pop();
          } else {
            if (homeScreenController.tabIndex.value != RailTab.home) {
              homeScreenController.onSideBarTabSelected(RailTab.home);
            } else if (playerController.buttonState.value ==
                PlayButtonState.playing) {
              SystemNavigator.pop();
            } else {
              if (Get.isRegistered<AudioHandler>()) {
                await Get.find<AudioHandler>().customAction("saveSession");
              }
              exit(0);
            }
          }
        }
      },
      child: CallbackShortcuts(
        bindings: {
          LogicalKeySet(LogicalKeyboardKey.space): playerController.playPause
        },
        // Outer Obx removed: after bottom-nav removal it read no observables on
        // phone (endDrawer is null), and GetX throws "improper use of a GetX"
        // which blanks the entire Home scaffold in release builds.
        child: Scaffold(
            key: playerController.homeScaffoldkey,
            endDrawer: GetPlatform.isDesktop || isWideScreen
                ? Container(
                    constraints: const BoxConstraints(maxWidth: 600),
                    decoration: BoxDecoration(
                      borderRadius:
                          const BorderRadius.only(topLeft: Radius.circular(10)),
                      border: Border(
                        left: BorderSide(
                            color: Theme.of(context).colorScheme.secondary),
                        top: BorderSide(
                            color: Theme.of(context).colorScheme.secondary),
                      ),
                    ),
                    margin: const EdgeInsets.only(
                      top: 5,
                      bottom: 106,
                    ),
                    child: SizedBox(
                      child: Column(
                        children: [
                          // Title and count on the left, the queue's
                          // actions as icons (as under the phone's queue),
                          // so a narrow window doesn't spill the row.
                          ColoredBox(
                            color: Theme.of(context).canvasColor,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  left: RiffSpacing.lg,
                                  top: RiffSpacing.xs,
                                  right: RiffSpacing.sm,
                                  bottom: RiffSpacing.xs),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          "upNext".tr,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge,
                                        ),
                                        Obx(() => Text(
                                              "${playerController.currentQueue.length} ${"songs".tr}",
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant),
                                            )),
                                      ],
                                    ),
                                  ),
                                  Obx(() => QueueBarButton(
                                        tooltip: "queueLoop".tr,
                                        icon: Icons.repeat_rounded,
                                        active: playerController
                                            .isQueueLoopModeEnabled.isTrue,
                                        onTap: playerController
                                            .toggleQueueLoopMode,
                                      )),
                                  QueueBarButton(
                                    tooltip: "shuffleQueue".tr,
                                    icon: Icons.shuffle_rounded,
                                    onTap: () {
                                      if (playerController
                                          .isShuffleModeEnabled.isTrue) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(snackbar(context,
                                                "queueShufflingDeniedMsg".tr,
                                                size: SanckBarSize.BIG));
                                        return;
                                      }
                                      playerController.shuffleQueue();
                                    },
                                  ),
                                  QueueBarButton(
                                    tooltip: "clearQueue".tr,
                                    icon: Icons.playlist_remove_rounded,
                                    onTap: () =>
                                        clearQueueWithUndo(context: context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Expanded(
                            child: UpNextQueue(
                              isQueueInSlidePanel: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
            drawerScrimColor: Colors.transparent,
            body: Obx(() => SlidingUpPanel(
                  onPanelSlide: playerController.panellistener,
                  controller: playerController.playerPanelController,
                  minHeight: playerController.playerPanelMinHeight.value,
                  maxHeight: size.height,
                  isDraggable: !isWideScreen,
                  // Clear sheet: each player paints its own page, and the
                  // music player fades it while minimising so the screen
                  // behind shows through.
                  color: Colors.transparent,
                  // No shadow either: under a clear sheet it fills the
                  // whole panel, a dark wash over the screen behind that
                  // travels with the minimise / expand morph.
                  boxShadow: const [],
                  onSwipeUp: () {
                    playerController.queuePanelController.open();
                  },
                  panel: const Player(),
                  body: const ScreenNavigation(),
                  header: !isWideScreen
                      ? InkWell(
                          onTap: playerController.playerPanelController.open,
                          child: const MiniPlayer(),
                        )
                      : const MiniPlayer(),
                ))),
      ),
    );
  }
}
