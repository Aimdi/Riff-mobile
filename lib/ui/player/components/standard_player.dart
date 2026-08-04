import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../screens/Settings/settings_screen_controller.dart';
import '../../utils/theme_controller.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import '../player_controller.dart';
import 'albumart_lyrics.dart';
import 'backgroud_image.dart';
import 'lyrics_switch.dart';
import 'player_canvas_backdrop.dart';
import 'player_control.dart';

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
      final canvasOn = Get.isRegistered<SettingsScreenController>() &&
          Get.find<SettingsScreenController>().playerCanvas.isTrue;

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
          // Skip HQ album-art decode + blur under live video — solid scrim only.
          if (showVideo) ...[
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).primaryColor,
              ),
            ),
          ] else ...[
            const BackgroudImage(),
            if (canvasOn) const Positioned.fill(child: PlayerCanvasBackdrop()),
            // Lighter than BackdropFilter blur — solid tint keeps art readable
            // without per-frame save-layer cost while the panel animates.
            Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.82),
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
                              bottom: 80 + Get.mediaQuery.padding.bottom),
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
                      // Center the video/art in the remaining space above controls.
                      // Video is opt-in via the videocam icon on the cover art.
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
                          const EdgeInsets.only(top: 10.0, left: 5, right: 5),
                      child: Obx(
                        () {
                          final from = playerController.playinfrom.value;
                          final type = from.typeString.trim();
                          final name = from.nameString.trim();
                          final label = name.isEmpty
                              ? (type.isEmpty ? '' : type)
                              : type.isEmpty
                                  ? name
                                  : '$type · $name';
                          if (label.isEmpty) return const SizedBox.shrink();
                          return Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: RiffSurfaces.textMuted,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 25),
                    onPressed: () {
                      showModalBottomSheet(
                        useRootNavigator: true,
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
