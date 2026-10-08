import 'package:get/get.dart';
import 'package:flutter/material.dart';

import '/ui/player/components/gesture_player.dart';
import '/ui/player/components/long_form_player.dart';
import '/ui/player/components/queue_panel.dart';
import '/ui/player/components/standard_player.dart';
import '/ui/player/components/up_next_card.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../../utils/helper.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/snackbar.dart';
import '/ui/player/play_queue_order.dart';
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
    return Scaffold(
      /// SlidingUpPanel is used to create a panel that can slide up and down
      /// It is used to show the current queue panel in mobile
      body: Obx(() {
        // Standard player: the queue waits in a slim card at the bottom.
        final showCard = settingsScreenController.playerUi.value == 0;
        final bottomInset = Get.mediaQuery.padding.bottom;
        return SlidingUpPanel(
          // No sheet: collapsed, only the card floats over the player, and
          // the queue (which paints its own background) fades in as it
          // opens.
          renderPanelSheet: false,
          fadePanelWhenCollapsed: true,
          minHeight: showCard ? UpNextCard.extent + bottomInset : 0,
          maxHeight: size.height,
          isDraggable: !GetPlatform.isDesktop,
          controller: GetPlatform.isDesktop
              ? null
              : playerController.queuePanelController,
          collapsed: showCard
              ? Obx(() {
                  final upcoming = playerController.upcomingQueue;
                  return UpNextCard(
                    preview: upcoming.isEmpty
                        ? ''
                        : upcomingPreviewLabel(
                            upcoming.first.title, upcoming.length),
                    bottomInset: bottomInset,
                    onTap: () {
                      /// queue open in end drawer in desktop
                      if (GetPlatform.isDesktop) {
                        playerController.homeScaffoldkey.currentState
                            ?.openEndDrawer();
                      } else {
                        playerController.queuePanelController.open();
                      }
                    },
                  );
                })
              : null,

          /// Panel for queue
          panelBuilder: (ScrollController sc, onReorderStart, onReorderEnd) {
            playerController.scrollController = sc;
            // Up next / Similar songs tabs over the queue or the similar
            // list.
            return QueuePanel(
              onReorderEnd: onReorderEnd,
              onReorderStart: onReorderStart,

              /// Bottom bar: queue loop / shuffle / clear — solid frost
              /// (BackdropFilter blur was a queue-panel jank source).
              queueFooter: Align(
                alignment: Alignment.bottomCenter,
                child: Builder(builder: (context) {
                  final theme = Theme.of(context);
                  // Opaque, so queue rows never show through the footer.
                  return Container(
                    padding: EdgeInsets.only(
                        left: RiffSpacing.xl,
                        right: RiffSpacing.sm,
                        bottom: Get.mediaQuery.padding.bottom),
                    decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        border: Border(
                          top: BorderSide(color: theme.dividerColor, width: 0),
                        )),
                    height: 60 + Get.mediaQuery.padding.bottom,
                    child: Row(
                      children: [
                        /// number of songs in queue
                        Expanded(
                          child: Obx(
                            () => Text(
                              "${playerController.currentQueue.length} ${"songs".tr}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                        Obx(() => _QueueBarButton(
                              tooltip: "queueLoop".tr,
                              icon: Icons.repeat_rounded,
                              active: playerController
                                  .isQueueLoopModeEnabled.isTrue,
                              onTap: playerController.toggleQueueLoopMode,
                            )),
                        _QueueBarButton(
                          tooltip: "shuffleQueue".tr,
                          icon: Icons.shuffle_rounded,
                          onTap: () {
                            if (playerController.isShuffleModeEnabled.isTrue) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  snackbar(
                                      context, "queueShufflingDeniedMsg".tr,
                                      size: SanckBarSize.BIG));
                              return;
                            }
                            playerController.shuffleQueue();
                          },
                        ),
                        _QueueBarButton(
                          tooltip: "saveQueueAsPlaylist".tr,
                          icon: Icons.playlist_add_rounded,
                          onTap: () {
                            final queue =
                                playerController.currentQueue.toList();
                            if (!canSaveQueueAsPlaylist(queue.length)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                snackbar(
                                  context,
                                  'emptyPlaylist'.tr,
                                  size: SanckBarSize.MEDIUM,
                                ),
                              );
                              return;
                            }
                            showAddToPlaylistSheet(context, queue);
                          },
                        ),
                        _QueueBarButton(
                          tooltip: "clearQueue".tr,
                          icon: Icons.playlist_remove_rounded,
                          onTap: playerController.clearQueue,
                        ),
                      ],
                    ),
                  );
                }),
              ),
            );
          },

          /// show player ui based on selected player ui in settings
          /// Gesture player is only applicable for mobile
          /// Tickers (ambient canvas backdrop, play-button morph) are muted
          /// while the full player is collapsed behind the mini player —
          /// SlidingUpPanel always builds the panel, so they'd otherwise
          /// repaint full-screen layers every frame forever.
          body: _PlayerBodyTickerMode(
            playerController: playerController,
            // Podcasts and audiobooks get their own long-form player.
            child: Obx(() => playerController.usesLongFormTransport
                ? const LongFormPlayer()
                : settingsScreenController.playerUi.value == 0
                    ? const StandardPlayer()
                    : const GesturePlayer()),
          ),
        );
      }),
    );
  }
}

/// Enables tickers below [child] only while the player panel is visibly
/// expanded (past the mini-player cross-fade zone).
class _PlayerBodyTickerMode extends StatelessWidget {
  const _PlayerBodyTickerMode({
    required this.playerController,
    required this.child,
  });
  final PlayerController playerController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Obx(() => TickerMode(
          enabled: !playerController.isPlayerpanelTopVisible.value,
          child: child,
        ));
  }
}

/// Queue panel footer action: icon only, accent while [active].
class _QueueBarButton extends StatelessWidget {
  const _QueueBarButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.secondary;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      iconSize: RiffComponentSizes.headerIcon,
      isSelected: active,
      style: IconButton.styleFrom(
        backgroundColor:
            active ? RiffColors.of(context).accentMuted : Colors.transparent,
      ),
      icon: Icon(icon, color: active ? accent : scheme.onSurface),
    );
  }
}
