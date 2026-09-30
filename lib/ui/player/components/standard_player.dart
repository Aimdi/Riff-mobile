import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../screens/Settings/settings_screen_controller.dart';
import '../../utils/theme_controller.dart';
import '/models/playling_from.dart';
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

    return Obx(() {
      final isVideo = playerController.isCurrentSongVideo;
      final showVideo = isVideo &&
          AlbumArtNLyrics.videoPlaybackEnabledFor(
              playerController.currentSong.value);
      final canvasOn = Get.isRegistered<SettingsScreenController>() &&
          Get.find<SettingsScreenController>().playerCanvas.isTrue;

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
            if (canvasOn)
              const Positioned.fill(
                child: RepaintBoundary(child: PlayerCanvasBackdrop()),
              ),
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
            padding: const EdgeInsets.symmetric(horizontal: 24),
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
                          height:
                              Get.mediaQuery.padding.top + PlayerTopBar.height),
                      if (!isVideo) const LyricsSwitch(),
                      // Cover / video takes whatever height the controls
                      // leave, so nothing overlaps on short phones.
                      Expanded(
                        child: LayoutBuilder(builder: (context, box) {
                          final w = box.maxWidth.clamp(0.0, 500.0);
                          final h = (box.maxHeight - 8).clamp(0.0, 1e9);
                          final art = showVideo
                              ? (w * 9 / 16 <= h ? w : h * 16 / 9)
                              : (w < h ? w : h);
                          return Center(
                            child: AlbumArtNLyrics(playerArtImageSize: art),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),
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
            const PlayerTopBar(),
        ],
      );
    });
  }
}

/// Now-playing header: collapse · where playback comes from · more.
/// Lyrics and the sleep timer live in the action bar under the transport.
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({super.key});

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final fg = Theme.of(context).textTheme.titleMedium?.color ??
        RiffSurfaces.textPrimary;
    return Padding(
      padding: EdgeInsets.only(
          top: Get.mediaQuery.padding.top + 8, left: 8, right: 8),
      child: SizedBox(
        height: height - 8,
        child: Row(
          children: [
            IconButton(
              tooltip: 'close'.tr,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
              onPressed: playerController.playerPanelController.close,
            ),
            Expanded(
              child: Obx(() {
                final label =
                    playingFromLabel(playerController.playinfrom.value);
                if (label == null) return const SizedBox.shrink();
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label.type.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w600,
                        color: fg.withOpacity(0.6),
                      ),
                    ),
                    if (label.name.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        label.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                    ],
                  ],
                );
              }),
            ),
            IconButton(
              tooltip: 'moreOptions'.tr,
              icon: const Icon(Icons.more_vert_rounded, size: 24),
              onPressed: () => openNowPlayingSheet(playerController),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Playing from" header split into its kind ("Playing from playlist") and
/// source name; null when there is nothing to show.
({String type, String name})? playingFromLabel(PlaylingFrom from) {
  final type = '${from.typeString}'.trim();
  final name = '${from.nameString}'.trim();
  if (type.isEmpty && name.isEmpty) return null;
  if (type.isEmpty) return (type: name, name: '');
  return (type: type, name: name);
}

/// Song options for the current track (radio, play next, share, sleep
/// timer, album / artist …).
void openNowPlayingSheet(PlayerController playerController) {
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
    builder: (context) => SongInfoBottomSheet(song, calledFromPlayer: true),
  ).whenComplete(() => Get.delete<SongInfoController>());
}
