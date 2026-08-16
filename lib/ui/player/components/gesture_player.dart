import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/components/backgroud_image.dart';
import 'package:ionicons/ionicons.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../widgets/favorite_heart_button.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import '../../utils/riff_tokens.dart';
import '../../utils/theme_controller.dart';
import '../player_controller.dart';
import '../player_media_nav.dart';
import 'playback_error_actions.dart';

class GesturePlayer extends StatelessWidget {
  const GesturePlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    final accent = Theme.of(context).colorScheme.secondary;
    return Stack(
      children: [
        GestureDetector(
          /// Full screen Background image is acting as album art
          child: const BackgroudImage(),
          onHorizontalDragEnd: (DragEndDetails details) {
            if (details.primaryVelocity! < 0) {
              playerController.next();
            } else if (details.primaryVelocity! > 0) {
              playerController.prev();
            }
          },
          onDoubleTap: () {
            playerController.playPause();
          },
          onLongPress: () {
            final sheetContext =
                playerController.homeScaffoldkey.currentContext ?? Get.context;
            final song = playerController.currentSong.value;
            if (sheetContext == null || song == null) return;
            showModalBottomSheet(
              useRootNavigator: true,
              constraints: const BoxConstraints(maxWidth: 500),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
              ),
              isScrollControlled: true,
              context: sheetContext,
              barrierColor: Colors.transparent.withAlpha(100),
              builder: (context) => SongInfoBottomSheet(
                song,
                calledFromPlayer: true,
              ),
            ).whenComplete(() => Get.delete<SongInfoController>());
          },
        ),
        IgnorePointer(
          child: Align(
            child: Center(
              child: Obx(
                () => FadeTransition(
                  opacity: playerController.gesturePlayerStateAnimation!,
                  child: playerController.gesturePlayerVisibleState.value == 2
                      ? const SizedBox.shrink()
                      : Icon(
                          playerController.gesturePlayerVisibleState.value == 1
                              ? Icons.play_arrow
                              : Icons.pause,
                          size: 72,
                          color: accent,
                        ),
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(
                bottom: Get.mediaQuery.padding.bottom != 0
                    ? Get.mediaQuery.padding.bottom + 10
                    : 20,
                left: 20,
                right: 20),
            child: Container(
              decoration: BoxDecoration(
                color: RiffSurfaces.elevated.withOpacity(0.92),
                borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
                border: Border.all(
                  color: RiffSurfaces.hairline,
                  width: RiffTokens.hairline,
                ),
              ),
              constraints: const BoxConstraints(maxWidth: 500),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
                // No BackdropFilter — blur here was expensive during gestures.
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Obx(() {
                                  final song =
                                      playerController.currentSong.value;
                                  final title = song?.title;
                                  final titleText = Marquee(
                                    delay: const Duration(milliseconds: 300),
                                    duration: const Duration(seconds: 10),
                                    id: "${song}_title",
                                    child: Text(
                                      (title != null && title.isNotEmpty)
                                          ? title
                                          : "—",
                                      textAlign: TextAlign.start,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium!
                                          .copyWith(
                                              color: RiffSurfaces.textPrimary),
                                    ),
                                  );
                                  if (songAlbumId(song) == null) {
                                    return titleText;
                                  }
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () =>
                                        openCurrentAlbum(playerController),
                                    child: titleText,
                                  );
                                }),
                                const SizedBox(
                                  height: 7,
                                ),
                                GetX<PlayerController>(builder: (controller) {
                                  final song = controller.currentSong.value;
                                  final artist = song?.artist;
                                  final artistText = Marquee(
                                    delay: const Duration(milliseconds: 300),
                                    duration: const Duration(seconds: 10),
                                    id: "${song}_subtitle",
                                    child: Text(
                                      (artist != null && artist.isNotEmpty)
                                          ? artist
                                          : "—",
                                      textAlign: TextAlign.start,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall!
                                          .copyWith(
                                              color: RiffSurfaces.textMuted,
                                              fontWeight: FontWeight.normal),
                                    ),
                                  );
                                  if (songArtistId(song) == null) {
                                    return artistText;
                                  }
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () =>
                                        openCurrentArtist(playerController),
                                    child: artistText,
                                  );
                                }),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 75,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                FavoriteHeartButton(
                                  splashRadius: 10,
                                  iconSize: 20,
                                  visualDensity: const VisualDensity(
                                      horizontal: -4, vertical: -4),
                                  isFav: playerController.isCurrentSongFav,
                                  onToggleFav: playerController.toggleFavourite,
                                  song: () =>
                                      playerController.currentSong.value,
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Obx(() {
                                      return IconButton(
                                          splashRadius: 10,
                                          visualDensity: const VisualDensity(
                                              horizontal: -4, vertical: -4),
                                          iconSize: 18,
                                          onPressed:
                                              playerController.toggleLoopMode,
                                          icon: Icon(
                                            Icons.all_inclusive,
                                            color: playerController
                                                    .isLoopModeEnabled.value
                                                ? RiffSurfaces.textPrimary
                                                : RiffSurfaces.textMuted
                                                    .withOpacity(0.45),
                                          ));
                                    }),
                                    IconButton(
                                      iconSize: 18,
                                      splashRadius: 10,
                                      visualDensity: const VisualDensity(
                                          horizontal: -4, vertical: -4),
                                      onPressed:
                                          playerController.toggleShuffleMode,
                                      icon: Obx(
                                        () => Icon(
                                          Ionicons.shuffle,
                                          color: playerController
                                                  .isShuffleModeEnabled.value
                                              ? RiffSurfaces.textPrimary
                                              : RiffSurfaces.textMuted
                                                  .withOpacity(0.45),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 5,
                      ),
                      Obx(() {
                        final err = playerController.playbackError.value;
                        if (err == null || err.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final theme = Theme.of(context);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  size: 16, color: theme.colorScheme.error),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  err,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: RiffSurfaces.textMuted,
                                  ),
                                ),
                              ),
                              PlaybackErrorActions(
                                compact: true,
                                color: theme.colorScheme.error,
                              ),
                            ],
                          ),
                        );
                      }),
                      GetX<PlayerController>(builder: (controller) {
                        return ProgressBar(
                          thumbRadius: 6,
                          timeLabelLocation: TimeLabelLocation.sides,
                          baseBarColor: RiffSurfaces.hairline,
                          bufferedBarColor: RiffSurfaces.elevatedSoft,
                          progressBarColor: accent,
                          thumbColor: RiffSurfaces.textPrimary,
                          timeLabelTextStyle: Theme.of(context)
                              .textTheme
                              .titleSmall!
                              .copyWith(
                                  color: RiffSurfaces.textMuted, fontSize: 12),
                          progress: controller.progressBarStatus.value.current,
                          total: controller.progressBarStatus.value.total,
                          buffered: controller.progressBarStatus.value.buffered,
                          onSeek: controller.seek,
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // absorb pointer to prevent the next,prev gesture from being triggered when the user tries to switch app
        Align(
          alignment: Alignment.bottomCenter,
          child: AbsorbPointer(
            child: SizedBox(
              height: Get.mediaQuery.padding.bottom + 20,
              child: Container(),
            ),
          ),
        )
      ],
    );
  }
}
