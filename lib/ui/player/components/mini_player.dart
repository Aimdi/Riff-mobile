import 'package:audio_service/audio_service.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ionicons/ionicons.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/ui/widgets/lyrics_dialog.dart';
import '/ui/widgets/song_info_dialog.dart';
import '/ui/player/player_controller.dart';
import '/ui/player/player_media_nav.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/utils/theme_controller.dart';
import '../../widgets/add_to_playlist.dart';
import '../../widgets/favorite_heart_button.dart';
import '../../widgets/sleep_timer_bottom_sheet.dart';
import '../../widgets/song_download_btn.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/mini_player_progress_bar.dart';
import 'animated_play_button.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final size = MediaQuery.of(context).size;
    final isWideScreen = size.width > 800;
    final theme = Theme.of(context);
    // Solid frost — BackdropFilter blur was rebuilding every panel-drag /
    // opacity tick and was a major source of mini-player jank.
    final frost = theme.cardColor.withOpacity(
      theme.brightness == Brightness.dark ? 0.94 : 0.97,
    );

    // Built outside the opacity Obx so the same child instance is reused when
    // playerPaneOpacity / visibility / height tick — Flutter skips rebuilding
    // identical child widget instances.
    // Align top + bottom pad so the progress bar stays at the top of the
    // panel while the system nav/home inset is reserved below the content.
    final content = Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          children: [
            !isWideScreen
                ? const _MiniPlayerThinProgress()
                : const _MiniPlayerWideProgress(),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 17.0, vertical: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const _MiniPlayerArt(),
                  const SizedBox(
                    width: 10,
                  ),
                  const Expanded(
                    child: _MiniPlayerSongInfo(),
                  ),
                  isWideScreen
                      ? const SizedBox(
                          width: 450,
                          child: _MiniPlayerTransport(isWideScreen: true),
                        )
                      : const _MiniPlayerTransport(isWideScreen: false),
                  if (isWideScreen)
                    Expanded(
                      child: _MiniPlayerWideExtras(size: size),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Obx(() {
      return Visibility(
        visible: playerController.isPlayerpanelTopVisible.value,
        child: AnimatedOpacity(
          opacity: playerController.playerPaneOpacity.value,
          duration: Duration.zero,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: frost,
              border: Border(
                top: BorderSide(
                  color: theme.dividerColor.withOpacity(0.9),
                  width: 0.5,
                ),
              ),
            ),
            child: SizedBox(
              height: playerController.playerPanelMinHeight.value,
              width: size.width,
              child: content,
            ),
          ),
        ),
      );
    });
  }
}

class _MiniPlayerArt extends StatelessWidget {
  const _MiniPlayerArt();

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Obx(() {
      final song = playerController.currentSong.value;
      return Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          song != null
              ? Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: RiffSurfaces.hairline,
                      width: RiffTokens.hairline,
                    ),
                  ),
                  child: ImageWidget(
                    size: 50,
                    song: song,
                    borderRadius: 8,
                  ),
                )
              : const SizedBox(
                  height: 50,
                  width: 50,
                ),
        ],
      );
    });
  }
}

class _MiniPlayerSongInfo extends StatelessWidget {
  const _MiniPlayerSongInfo();

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final theme = Theme.of(context);
    return GestureDetector(
      onHorizontalDragEnd: (DragEndDetails details) {
        if (details.primaryVelocity! < 0) {
          playerController.next();
        } else if (details.primaryVelocity! > 0) {
          playerController.prev();
        }
      },
      onTap: () {
        playerController.playerPanelController.open();
      },
      child: ColoredBox(
        color: Colors.transparent,
        child: Obx(() {
          final song = playerController.currentSong.value;
          final err = playerController.playbackError.value;
          final songKey = song?.id ?? 'none';
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 20,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: Text(
                    song != null ? song.title : "",
                    key: ValueKey<String>('mini_title_$songKey'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              SizedBox(
                height: 20,
                child: err != null && err.isNotEmpty
                    ? Row(
                        children: [
                          Icon(Icons.error_outline,
                              size: 14, color: theme.colorScheme.error),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              err,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: playerController.retryPlayback,
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              foregroundColor: theme.colorScheme.error,
                            ),
                            child: Text("retry".tr),
                          ),
                        ],
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: _miniArtistLine(
                          playerController,
                          song,
                          songKey,
                          theme,
                        ),
                      ),
              ),
            ],
          );
        }),
      ),
    );
  }

  /// Artist line: tap opens the artist screen when extras have an id.
  /// The parent row tap still expands the player for title / empty space.
  Widget _miniArtistLine(
    PlayerController playerController,
    MediaItem? song,
    String songKey,
    ThemeData theme,
  ) {
    final line = Marquee(
      key: ValueKey<String>('mini_artist_$songKey'),
      id: "${song}_mini",
      delay: const Duration(milliseconds: 300),
      duration: const Duration(seconds: 5),
      child: Text(
        song != null ? (song.artist ?? "") : "",
        maxLines: 1,
        style: theme.textTheme.titleSmall,
      ),
    );
    if (songArtistId(song) == null) return line;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openCurrentArtist(playerController),
      child: line,
    );
  }
}

class _MiniPlayerTransport extends StatelessWidget {
  const _MiniPlayerTransport({required this.isWideScreen});

  final bool isWideScreen;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final skipSize = isWideScreen ? 35.0 : 24.0;
    final skipWidth = isWideScreen ? 40.0 : 28.0;
    const compact = BoxConstraints(minWidth: 32, minHeight: 32);
    return Row(
      mainAxisSize: isWideScreen ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        FavoriteHeartButton(
          iconSize: isWideScreen ? 20 : 18,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: compact,
          splashRadius: 18,
          isFav: playerController.isCurrentSongFav,
          onToggleFav: playerController.toggleFavourite,
          song: () => playerController.currentSong.value,
        ),
        if (isWideScreen)
          IconButton(
              iconSize: 20,
              onPressed: playerController.toggleShuffleMode,
              icon: Obx(() => Icon(
                    Ionicons.shuffle,
                    color: playerController.isShuffleModeEnabled.value
                        ? Theme.of(context).textTheme.titleLarge!.color
                        : Theme.of(context)
                            .textTheme
                            .titleLarge!
                            .color!
                            .withOpacity(0.2),
                  ))),
        SizedBox(
            width: skipWidth,
            child: Obx(() {
              final canPrev = playerController.currentQueue.isNotEmpty &&
                  (playerController.currentQueue.first.id !=
                      playerController.currentSong.value?.id);
              return InkWell(
                onTap: canPrev ? playerController.prev : null,
                child: Icon(
                  Icons.skip_previous_rounded,
                  color: Theme.of(context).textTheme.titleMedium!.color,
                  size: skipSize,
                ),
              );
            })),
        isWideScreen
            ? const AnimatedPlayButton(
                iconSize: 30,
                size: 58,
              )
            : const AnimatedPlayButton(
                iconSize: 22,
                size: 38,
              ),
        SizedBox(
            width: skipWidth,
            child: Obx(() {
              final isLastSong = playerController.currentQueue.isEmpty ||
                  (!(playerController.isShuffleModeEnabled.isTrue ||
                          playerController.isQueueLoopModeEnabled.isTrue) &&
                      (playerController.currentQueue.last.id ==
                          playerController.currentSong.value?.id));
              return InkWell(
                onTap: isLastSong ? null : playerController.next,
                child: Icon(
                  Icons.skip_next_rounded,
                  color: isLastSong
                      ? Theme.of(context)
                          .textTheme
                          .titleLarge!
                          .color!
                          .withOpacity(0.2)
                      : Theme.of(context).textTheme.titleMedium!.color,
                  size: skipSize,
                ),
              );
            })),
        if (!isWideScreen)
          IconButton(
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: compact,
            splashRadius: 18,
            tooltip: 'upNext'.tr,
            onPressed: () {
              final queue = playerController.queuePanelController;
              if (queue.isAttached) {
                queue.open();
              }
            },
            icon: Icon(
              Icons.queue_music,
              color: Theme.of(context).textTheme.titleMedium!.color,
            ),
          ),
        if (isWideScreen)
          Row(
            children: [
              IconButton(
                  iconSize: 20,
                  onPressed: playerController.toggleLoopMode,
                  icon: Obx(() => Icon(
                        Icons.all_inclusive,
                        color: playerController.isLoopModeEnabled.value
                            ? Theme.of(context).textTheme.titleLarge!.color
                            : Theme.of(context)
                                .textTheme
                                .titleLarge!
                                .color!
                                .withOpacity(0.2),
                      ))),
              IconButton(
                  iconSize: 20,
                  onPressed: () {
                    playerController.showLyrics();
                    showDialog(
                            builder: (context) => const LyricsDialog(),
                            context: context)
                        .whenComplete(() {
                      playerController.isDesktopLyricsDialogOpen = false;
                      playerController.showLyricsflag.value = false;
                    });
                    playerController.isDesktopLyricsDialogOpen = true;
                  },
                  icon: Icon(Icons.lyrics_outlined,
                      color: Theme.of(context).textTheme.titleLarge!.color)),
            ],
          ),
        if (isWideScreen)
          const SizedBox(
            width: 20,
          )
      ],
    );
  }
}

class _MiniPlayerWideExtras extends StatelessWidget {
  const _MiniPlayerWideExtras({required this.size});

  final Size size;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Padding(
      padding: EdgeInsets.only(right: size.width < 1004 ? 0 : 30.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.only(right: 20, left: 10),
            height: 20,
            width: (size.width > 860) ? 220 : 180,
            child: Obx(() {
              final volume = playerController.volume.value;
              return Row(
                children: [
                  SizedBox(
                      width: 20,
                      child: InkWell(
                        onTap: playerController.mute,
                        child: Icon(
                          volume == 0
                              ? Icons.volume_off
                              : volume > 0 && volume < 50
                                  ? Icons.volume_down
                                  : Icons.volume_up,
                          size: 20,
                        ),
                      )),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 10.0),
                      ),
                      child: Slider(
                        value: playerController.volume.value / 100,
                        onChanged: (value) {
                          playerController.setVolume((value * 100).toInt());
                        },
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () {
                    playerController.homeScaffoldkey.currentState?.openEndDrawer();
                  },
                  icon: const Icon(Icons.queue_music),
                ),
                if (size.width > 860)
                  Padding(
                    padding: const EdgeInsets.only(left: 10.0),
                    child: Obx(() => IconButton(
                          onPressed: () {
                            final sheetContext = playerController
                                    .homeScaffoldkey.currentContext ??
                                Get.context;
                            if (sheetContext == null) return;
                            showModalBottomSheet(
                              constraints: const BoxConstraints(maxWidth: 500),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(10.0)),
                              ),
                              isScrollControlled: true,
                              context: sheetContext,
                              barrierColor: Colors.transparent.withAlpha(100),
                              builder: (context) =>
                                  const SleepTimerBottomSheet(),
                            );
                          },
                          icon: Icon(playerController.isSleepTimerActive.isTrue
                              ? Icons.timer
                              : Icons.timer_outlined),
                        )),
                  ),
                const SizedBox(
                  width: 10,
                ),
                const SongDownloadButton(
                  calledFromPlayer: true,
                ),
                const SizedBox(
                  width: 10,
                ),
                IconButton(
                  onPressed: () {
                    final currentSong = playerController.currentSong.value;
                    if (currentSong != null) {
                      showDialog(
                        context: context,
                        builder: (context) => AddToPlaylist([currentSong]),
                      ).whenComplete(
                          () => Get.delete<AddToPlaylistController>());
                    }
                  },
                  icon: const Icon(Icons.playlist_add),
                ),
                if (size.width > 965)
                  IconButton(
                    onPressed: () {
                      final currentSong = playerController.currentSong.value;
                      if (currentSong != null) {
                        showDialog(
                          context: context,
                          builder: (context) => SongInfoDialog(
                            song: currentSong,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.info, size: 22),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress-only rebuild scope so art/title/controls stay still while seeking.
class _MiniPlayerThinProgress extends StatelessWidget {
  const _MiniPlayerThinProgress();

  @override
  Widget build(BuildContext context) {
    return GetX<PlayerController>(
      builder: (controller) => Container(
        height: 2,
        color: RiffSurfaces.hairline,
        child: MiniPlayerProgressBar(
          progressBarStatus: controller.progressBarStatus.value,
          progressBarColor: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }
}

class _MiniPlayerWideProgress extends StatelessWidget {
  const _MiniPlayerWideProgress();

  @override
  Widget build(BuildContext context) {
    return GetX<PlayerController>(builder: (controller) {
      return Padding(
        padding:
            const EdgeInsets.only(left: 15.0, top: 8, right: 15, bottom: 0),
        child: ProgressBar(
          timeLabelLocation: TimeLabelLocation.sides,
          thumbRadius: 7,
          barHeight: 4,
          thumbGlowRadius: 15,
          baseBarColor: Theme.of(context).sliderTheme.inactiveTrackColor,
          bufferedBarColor: Theme.of(context).sliderTheme.valueIndicatorColor,
          progressBarColor: Theme.of(context).sliderTheme.activeTrackColor,
          thumbColor: Theme.of(context).sliderTheme.thumbColor,
          timeLabelTextStyle: Theme.of(context).textTheme.titleMedium,
          progress: controller.progressBarStatus.value.current,
          total: controller.progressBarStatus.value.total,
          buffered: controller.progressBarStatus.value.buffered,
          onSeek: controller.seek,
        ),
      );
    });
  }
}
