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
import '/ui/player/radio_continuation.dart';
import '../../widgets/add_to_playlist.dart';
import '../../widgets/favorite_heart_button.dart';
import '../../widgets/sleep_timer_bottom_sheet.dart';
import '../../widgets/song_download_btn.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/mini_player_progress_bar.dart';
import 'animated_play_button.dart';
import 'playback_error_actions.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  /// Width of the wide (desktop) transport block (keeps its current size).
  static const double _wideTransportWidth = 450;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final size = MediaQuery.of(context).size;
    final isWideScreen = size.width > 800;
    final theme = Theme.of(context);

    // Built outside the opacity Obx so the same child instance is reused when
    // playerPaneOpacity / visibility / height tick — Flutter skips rebuilding
    // identical child widget instances.
    // Align top + bottom pad so the progress bar stays at the top of the
    // panel while the system nav/home inset is reserved below the content.
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isWideScreen)
          // Own layer so 10 Hz progress ticks don't repaint the whole
          // mini player (art, title, transport).
          const RepaintBoundary(child: _MiniPlayerWideProgress()),
        Expanded(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: RiffSpacing.md, vertical: RiffSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const _MiniPlayerArt(),
                    const SizedBox(
                      width: RiffSpacing.md,
                    ),
                    const Expanded(
                      child: _MiniPlayerSongInfo(),
                    ),
                    isWideScreen
                        ? const SizedBox(
                            width: _wideTransportWidth,
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
              if (!isWideScreen)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: RepaintBoundary(child: _MiniPlayerThinProgress()),
                ),
            ],
          ),
        ),
      ],
    );

    return Obx(() {
      return Visibility(
        visible: playerController.isPlayerpanelTopVisible.value,
        child: AnimatedOpacity(
          opacity: playerController.playerPaneOpacity.value,
          duration: Duration.zero,
          // The strip is page-coloured; the player itself is a floating
          // pill inside it, with the system inset kept clear below.
          child: ColoredBox(
            color: theme.colorScheme.surface,
            child: SizedBox(
              height: playerController.playerPanelMinHeight.value,
              width: size.width,
              child: Padding(
                padding: EdgeInsets.only(
                  left: RiffSpacing.md,
                  right: RiffSpacing.md,
                  bottom:
                      MediaQuery.viewPaddingOf(context).bottom + RiffSpacing.sm,
                ),
                // Floating surface1 card, hairline edge, no shadow.
                child: Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RiffRadii.miniPlayer),
                    side: BorderSide(color: theme.dividerColor, width: 0),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: content,
                ),
              ),
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
              ? GestureDetector(
                  onLongPress: () {
                    showCurrentSongSheet(
                      song: song,
                      context: playerController.homeScaffoldkey.currentContext,
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 0,
                      ),
                    ),
                    child: ClipOval(
                      child: ImageWidget(
                        size: RiffComponentSizes.miniArt,
                        song: song,
                        borderRadius: 0,
                      ),
                    ),
                  ),
                )
              : const SizedBox.square(
                  dimension: RiffComponentSizes.miniArt,
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
      onLongPress: () {
        showCurrentSongSheet(
          song: playerController.currentSong.value,
          context: playerController.homeScaffoldkey.currentContext,
        );
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
                height: RiffComponentSizes.miniLine,
                child: AnimatedSwitcher(
                  duration: RiffDurations.select,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: _miniTitleLine(
                    playerController,
                    song,
                    songKey,
                    theme,
                  ),
                ),
              ),
              SizedBox(
                height: RiffComponentSizes.miniLine,
                child: err != null && err.isNotEmpty
                    ? Row(
                        children: [
                          Icon(Icons.error_outline,
                              size: RiffComponentSizes.miniErrorIcon,
                              color: theme.colorScheme.error),
                          const SizedBox(width: RiffSpacing.xs),
                          Expanded(
                            child: Text(
                              err,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                          PlaybackErrorActions(
                            compact: true,
                            color: theme.colorScheme.error,
                          ),
                        ],
                      )
                    : AnimatedSwitcher(
                        duration: RiffDurations.select,
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

  /// Title: tap opens the album when extras have an id.
  Widget _miniTitleLine(
    PlayerController playerController,
    MediaItem? song,
    String songKey,
    ThemeData theme,
  ) {
    final line = Text(
      song != null ? song.title : "",
      key: ValueKey<String>('mini_title_$songKey'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: theme.textTheme.titleMedium
          ?.copyWith(color: theme.colorScheme.onSurface),
    );
    if (songAlbumId(song) == null) return line;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openCurrentAlbum(playerController),
      child: line,
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
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
    final scheme = Theme.of(context).colorScheme;
    final skipSize = isWideScreen
        ? RiffComponentSizes.miniWideSkipIcon
        : RiffComponentSizes.miniNextIcon;
    final skipWidth = isWideScreen
        ? RiffComponentSizes.miniWideSkipHit
        : RiffComponentSizes.miniSkipHit;
    const compact = BoxConstraints(
        minWidth: RiffComponentSizes.rowIconHit,
        minHeight: RiffComponentSizes.rowIconHit);
    // Toggled-on = accent; off = secondary text.
    Color toggle(bool on) => on ? scheme.secondary : scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: isWideScreen ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        FavoriteHeartButton(
          iconSize: RiffComponentSizes.trailingIcon,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: compact,
          isFav: playerController.isCurrentSongFav,
          onToggleFav: playerController.toggleFavourite,
          song: () => playerController.currentSong.value,
        ),
        if (isWideScreen)
          IconButton(
              iconSize: RiffComponentSizes.trailingIcon,
              onPressed: playerController.toggleShuffleMode,
              icon: Obx(() => Icon(
                    Ionicons.shuffle,
                    color: toggle(playerController.isShuffleModeEnabled.value),
                  ))),
        SizedBox(
            width: skipWidth,
            child: Obx(() {
              final canPrev = canSkipPrevious(
                hasQueue: playerController.currentQueue.isNotEmpty,
              );
              return InkWell(
                onTap: canPrev ? playerController.prev : null,
                child: Icon(
                  Icons.skip_previous_rounded,
                  color: scheme.onSurface,
                  size: skipSize,
                ),
              );
            })),
        isWideScreen
            ? const AnimatedPlayButton(
                iconSize: RiffComponentSizes.miniWidePlayIcon,
                size: RiffComponentSizes.miniWidePlay,
              )
            // Bare onSurface glyph in the same 38 hit box.
            : AnimatedPlayButton(
                iconSize: RiffComponentSizes.miniPlayIcon,
                size: RiffComponentSizes.miniPlayHit,
                color: Colors.transparent,
                iconColor: scheme.onSurface,
              ),
        SizedBox(
            width: skipWidth,
            child: Obx(() {
              final canNext = canSkipNext(
                queueEmpty: playerController.currentQueue.isEmpty,
                isLast: playerController.currentQueue.isNotEmpty &&
                    playerController.currentQueue.last.id ==
                        playerController.currentSong.value?.id,
                shuffleOn: playerController.isShuffleModeEnabled.isTrue,
                queueLoopOn: playerController.isQueueLoopModeEnabled.isTrue,
                radioOn: playerController.isRadioModeOn,
              );
              return InkWell(
                onTap: canNext ? playerController.next : null,
                child: Icon(
                  Icons.skip_next_rounded,
                  color: !canNext
                      ? Theme.of(context).disabledColor
                      : scheme.onSurface,
                  size: skipSize,
                ),
              );
            })),
        if (!isWideScreen)
          IconButton(
            iconSize: RiffComponentSizes.trailingIcon,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: compact,
            tooltip: 'upNext'.tr,
            onPressed: () {
              final queue = playerController.queuePanelController;
              if (queue.isAttached) {
                queue.open();
              }
            },
            icon: Icon(
              Icons.queue_music,
              color: scheme.onSurface,
            ),
          ),
        if (isWideScreen)
          Row(
            children: [
              IconButton(
                  iconSize: RiffComponentSizes.trailingIcon,
                  onPressed: playerController.toggleLoopMode,
                  icon: Obx(() => Icon(
                        Icons.all_inclusive,
                        color: toggle(playerController.isLoopModeEnabled.value),
                      ))),
              IconButton(
                  iconSize: RiffComponentSizes.trailingIcon,
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
                  icon: Icon(Icons.lyrics_outlined, color: scheme.onSurface)),
            ],
          ),
        if (isWideScreen)
          const SizedBox(
            width: RiffSpacing.xl,
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
                          size: RiffComponentSizes.trailingIcon,
                        ),
                      )),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6.0),
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
                    playerController.homeScaffoldkey.currentState
                        ?.openEndDrawer();
                  },
                  icon: const Icon(Icons.queue_music),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10.0),
                  child: Obx(() => IconButton(
                        tooltip: 'sleepTimer'.tr,
                        onPressed: () {
                          final sheetContext =
                              playerController.homeScaffoldkey.currentContext ??
                                  Get.context;
                          showSleepTimerSheet(sheetContext);
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
                  tooltip: 'addToPlaylist'.tr,
                  onPressed: () {
                    final currentSong = playerController.currentSong.value;
                    if (currentSong == null) return;
                    showAddToPlaylistSheet(context, [currentSong]);
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
                    icon: const Icon(Icons.info,
                        size: RiffComponentSizes.headerIcon),
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
        height: RiffComponentSizes.miniProgress,
        color: Theme.of(context).dividerColor,
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
    final theme = Theme.of(context);
    return GetX<PlayerController>(builder: (controller) {
      return Padding(
        padding: const EdgeInsets.only(
            left: RiffSpacing.lg, top: RiffSpacing.sm, right: RiffSpacing.lg),
        // 2-px divider track, accent progress and thumb, labelSmall times.
        child: ProgressBar(
          timeLabelLocation: TimeLabelLocation.sides,
          thumbRadius: RiffComponentSizes.miniWideThumb,
          barHeight: RiffComponentSizes.miniProgress,
          thumbGlowRadius: RiffComponentSizes.miniWideThumb,
          baseBarColor: theme.dividerColor,
          bufferedBarColor: theme.colorScheme.outline,
          progressBarColor: theme.colorScheme.secondary,
          thumbColor: theme.colorScheme.secondary,
          timeLabelTextStyle: theme.textTheme.labelSmall,
          progress: controller.progressBarStatus.value.current,
          total: controller.progressBarStatus.value.total,
          buffered: controller.progressBarStatus.value.buffered,
          onSeek: controller.seek,
        ),
      );
    });
  }
}
