import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/songinfo_bottom_sheet.dart';
import '../player_controller.dart';
import 'albumart_lyrics.dart';
import 'backgroud_image.dart';
import 'lyrics_switch.dart';
import 'player_control.dart';
import 'player_video_surface.dart';

/// Standard player widget
///
/// Album art / video surface, lyrics switch, and player controls.
class StandardPlayer extends StatelessWidget {
  const StandardPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final PlayerController playerController = Get.find<PlayerController>();

    double playerArtImageSize = size.width - 60;
    final spaceAvailableForArtImage =
        size.height - (70 + Get.mediaQuery.padding.bottom + 330);
    playerArtImageSize = playerArtImageSize > spaceAvailableForArtImage
        ? spaceAvailableForArtImage
        : playerArtImageSize;

    return Obx(() {
      final isVideo = playerController.isCurrentSongVideo;
      final showVideo = isVideo && AlbumArtNLyrics.videoPlaybackEnabled;

      // Video frame: full width minus padding, capped so 16:9 fits between
      // header and transport without floating under the status bar.
      var artSize = playerArtImageSize;
      if (showVideo) {
        final topReserve = Get.mediaQuery.padding.top + 72;
        final bottomReserve = 80 + Get.mediaQuery.padding.bottom + 220;
        final maxH =
            (size.height - topReserve - bottomReserve).clamp(160.0, 420.0);
        final byWidth = size.width - 48;
        final heightFromWidth = byWidth * 9 / 16;
        artSize = heightFromWidth <= maxH ? byWidth : maxH * 16 / 9;
      }

      return Stack(
        children: [
          // Static blur is expensive under a live video surface — use a flat
          // scrim for videos instead.
          if (showVideo) ...[
            const BackgroudImage(),
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).primaryColor.withOpacity(0.88),
              ),
            ),
          ] else ...[
            const BackgroudImage(),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.8),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 65 + Get.mediaQuery.padding.bottom + 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor,
                            Theme.of(context).primaryColor,
                            Theme.of(context).primaryColor.withOpacity(0.4),
                            Theme.of(context).primaryColor.withOpacity(0),
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          stops: const [0, 0.5, 0.8, 1],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          Padding(
            padding: const EdgeInsets.only(left: 24, right: 24),
            child: (context.isLandscape)
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: size.width * .45,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 90.0, top: 40),
                          child: Center(
                            child: AlbumArtNLyrics(
                              playerArtImageSize: size.width * .29,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: size.width * .48,
                        child: Padding(
                          padding: EdgeInsets.only(
                              left: 10.0,
                              right: 10,
                              bottom: Get.mediaQuery.padding.bottom),
                          child: const PlayerControlWidget(),
                        ),
                      )
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                        height: Get.mediaQuery.padding.top +
                            (isVideo
                                ? 56
                                : (playerController.showLyricsflag.value
                                    ? (size.height < 750 ? 60 : 90)
                                    : (size.height < 750 ? 110 : 140))),
                      ),
                      if (!isVideo) const LyricsSwitch(),
                      if (isVideo && !showVideo)
                        PlayerVideoShowChip(
                          onShow: () async {
                            await AlbumArtNLyrics.setVideoPlaybackEnabled(true);
                            playerController.currentSong.refresh();
                          },
                        ),
                      // Center the video/art in the remaining space above controls.
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 500),
                            child: AlbumArtNLyrics(
                              playerArtImageSize: artSize,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                            bottom: 80 + Get.mediaQuery.padding.bottom),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: const PlayerControlWidget(),
                        ),
                      ),
                    ],
                  ),
          ),

          if (!(context.isLandscape && GetPlatform.isMobile))
            Padding(
              padding: EdgeInsets.only(
                  top: Get.mediaQuery.padding.top + 20, left: 10, right: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                    onPressed: playerController.playerPanelController.close,
                  ),
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.only(top: 8.0, left: 5, right: 5),
                      child: Obx(
                        () => Column(
                          children: [
                            Text(playerController.playinfrom.value.typeString,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold)),
                            Obx(
                              () => Text(
                                "\"${playerController.playinfrom.value.nameString}\"",
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 25),
                    onPressed: () {
                      showModalBottomSheet(
                        constraints: const BoxConstraints(maxWidth: 500),
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(10.0)),
                        ),
                        isScrollControlled: true,
                        context: playerController
                            .homeScaffoldkey.currentState!.context,
                        barrierColor: Colors.transparent.withAlpha(100),
                        builder: (context) => SongInfoBottomSheet(
                          playerController.currentSong.value!,
                          calledFromPlayer: true,
                        ),
                      ).whenComplete(() => Get.delete<SongInfoController>());
                    },
                  ),
                ],
              ),
            )
        ],
      );
    });
  }
}
