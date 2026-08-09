import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/ui/player/components/lyrics_widget.dart';
import '/ui/player/components/player_video_surface.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/utils/theme_controller.dart';
import '/utils/media_item_video.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/sleep_timer_bottom_sheet.dart';
import '../../widgets/songinfo_bottom_sheet.dart';

class AlbumArtNLyrics extends StatelessWidget {
  const AlbumArtNLyrics({super.key, required this.playerArtImageSize});
  final double playerArtImageSize;

  static bool get videoPlaybackEnabled {
    final v = Hive.box('AppPrefs').get('playerShowVideo');
    if (v is bool) return v;
    // Opt-in: cover/thumbnail by default; user taps the video icon to enable.
    return false;
  }

  static Future<void> setVideoPlaybackEnabled(bool on) async {
    await Hive.box('AppPrefs').put('playerShowVideo', on);
  }

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    return Obx(() {
      final song = playerController.currentSong.value;
      if (song == null) return const SizedBox.shrink();

      final canVideo = song.canShowPlayerVideo;
      final isVideo = canVideo && videoPlaybackEnabled;
      // Spotify-style: videos use a 16:9 frame, songs keep the square cover.
      final width = playerArtImageSize;
      final height = isVideo ? (width * 9 / 16) : playerArtImageSize;

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          final scale = Tween<double>(begin: 0.97, end: 1).animate(fade);
          return FadeTransition(
            opacity: fade,
            child: ScaleTransition(scale: scale, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey<String>('${song.id}-$isVideo'),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                GestureDetector(
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
                        calledFromPlayer: true,
                      ),
                    ).whenComplete(() => Get.delete<SongInfoController>());
                  },
                  onTap: () {
                    // Videos: tap toggles play/pause (Spotify-like).
                    // Songs: tap opens lyrics.
                    if (isVideo) {
                      playerController.playPause();
                    } else {
                      playerController.showLyrics();
                    }
                  },
                  onHorizontalDragEnd: (DragEndDetails details) {
                    if (playerController.showLyricsflag.isTrue) return;
                    if (details.primaryVelocity! < 0) {
                      playerController.next();
                    } else if (details.primaryVelocity! > 0) {
                      playerController.prev();
                    }
                  },
                  child: isVideo
                      ? PlayerVideoSurface(
                          song: song,
                          width: width,
                          maxHeight: height,
                          onToggleVideo: () async {
                            await AlbumArtNLyrics.setVideoPlaybackEnabled(false);
                            playerController.currentSong.refresh();
                          },
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(RiffTokens.radiusLg),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.45),
                                blurRadius: 28,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: ImageWidget(
                            size: playerArtImageSize,
                            song: song,
                            isPlayerArtImage: true,
                            borderRadius: RiffTokens.radiusLg,
                          ),
                        ),
                ),
                // Opt-in muted surface: stays off until the user taps show-video.
                if (canVideo && !isVideo)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: PlayerVideoEnableButton(
                      onShow: () async {
                        await AlbumArtNLyrics.setVideoPlaybackEnabled(true);
                        playerController.currentSong.refresh();
                      },
                    ),
                  ),
                Obx(() => playerController.showLyricsflag.isTrue
                    ? InkWell(
                        onTap: () {
                          playerController.showLyrics();
                        },
                        child: Container(
                          height: height,
                          width: width,
                          decoration: BoxDecoration(
                            color: RiffSurfaces.voidBlack.withOpacity(0.82),
                            borderRadius:
                                BorderRadius.circular(RiffTokens.radiusLg),
                          ),
                          child: Stack(
                            children: [
                              LyricsWidget(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 0,
                                      vertical: height / 3.5)),
                              IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                        RiffTokens.radiusLg),
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        RiffSurfaces.voidBlack.withOpacity(0.90),
                                        Colors.transparent,
                                        Colors.transparent,
                                        Colors.transparent,
                                        RiffSurfaces.voidBlack.withOpacity(0.90)
                                      ],
                                      stops: const [0, 0.2, 0.5, 0.8, 1],
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink()),
                if (playerController.isSleepTimerActive.isTrue)
                  SizedBox(
                    width: width,
                    height: height,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Container(
                          height: 50,
                          width: 60,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              border:
                                  Border.all(width: 1.3, color: Colors.white),
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondary
                                  .withAlpha(150)),
                          child: IconButton(
                            onPressed: () {
                              final sheetContext = playerController
                                      .homeScaffoldkey.currentContext ??
                                  Get.context;
                              if (sheetContext == null) return;
                              showModalBottomSheet(
                                constraints:
                                    const BoxConstraints(maxWidth: 500),
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
                            icon: const Icon(
                              Icons.timer,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
              ],
            ),
          ),
        ),
      );
    });
  }
}
