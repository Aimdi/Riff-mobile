import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/ui/screens/Home/home_screen_controller.dart';
import '../utils/helper.dart';
import '../ui/navigator.dart';
import '../ui/player/player.dart';
import 'player/components/mini_player.dart';
import 'player/player_controller.dart';
import 'widgets/sliding_up_panel.dart';
import 'widgets/snackbar.dart';
import 'widgets/up_next_queue.dart';

class Home extends StatelessWidget {
  const Home({super.key});
  static const routeName = '/appHome';
  @override
  Widget build(BuildContext context) {
    printINFO("Home");
    // #region agent log
    try {
      File('/opt/cursor/logs/debug.log').writeAsStringSync(
          '{"location":"home.dart:build","message":"Home.build enter","data":{"width":${MediaQuery.of(context).size.width},"isWide":${MediaQuery.of(context).size.width > 800}},"hypothesisId":"A","timestamp":${DateTime.now().millisecondsSinceEpoch}}\n',
          mode: FileMode.append);
    } catch (_) {}
    // #endregion
    final PlayerController playerController = Get.find<PlayerController>();
    final homeScreenController = Get.find<HomeScreenController>();
    final size = MediaQuery.of(context).size;
    final isWideScreen = size.width > 800;
    // #region agent log
    try {
      File('/opt/cursor/logs/debug.log').writeAsStringSync(
          '{"location":"home.dart:build","message":"Home scaffold building (no outer Obx)","data":{"initFlag":${playerController.initFlagForPlayer},"panelMin":${playerController.playerPanelMinHeight.value},"tab":${homeScreenController.tabIndex.value},"isWide":$isWideScreen},"hypothesisId":"A","runId":"post-fix","timestamp":${DateTime.now().millisecondsSinceEpoch}}\n',
          mode: FileMode.append);
    } catch (_) {}
    // #endregion
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
            if (homeScreenController.tabIndex.value != 0) {
              homeScreenController.onSideBarTabSelected(0);
            } else if (playerController.buttonState.value ==
                PlayButtonState.playing) {
              SystemNavigator.pop();
            } else {
              await Get.find<AudioHandler>().customAction("saveSession");
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
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(10)),
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
                          SizedBox(
                            height: 60,
                            child: ColoredBox(
                              color: Theme.of(context).canvasColor,
                              child: Center(
                                  child: Padding(
                                padding: const EdgeInsets.only(
                                    left: 15.0, right: 15),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Obx(() => Text(
                                        "${playerController.currentQueue.length} ${"songs".tr}")),
                                    Text(
                                      "upNext".tr,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    Row(
                                      children: [
                                        InkWell(
                                          onTap: () {
                                            playerController
                                                .toggleQueueLoopMode();
                                          },
                                          child: Obx(
                                            () => Container(
                                              height: 30,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 20),
                                              decoration: BoxDecoration(
                                                color: playerController
                                                        .isQueueLoopModeEnabled
                                                        .isFalse
                                                    ? Colors.white24
                                                    : Colors.white
                                                        .withOpacity(0.8),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Center(
                                                  child: Text("queueLoop".tr)),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                            onPressed: () {
                                              if (playerController
                                                  .isShuffleModeEnabled
                                                  .isTrue) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(snackbar(
                                                        context,
                                                        "queueShufflingDeniedMsg"
                                                            .tr,
                                                        size: SanckBarSize
                                                            .BIG));
                                                return;
                                              }
                                              playerController.shuffleQueue();
                                            },
                                            icon: const Icon(Icons.shuffle)),
                                        IconButton(
                                            onPressed: () {
                                              playerController.clearQueue();
                                            },
                                            icon: const Icon(
                                                Icons.playlist_remove)),
                                      ],
                                    )
                                  ],
                                ),
                              )),
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
