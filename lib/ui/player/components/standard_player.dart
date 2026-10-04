import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/screens/Podcasts/podcast_segment_ui.dart';

import '../../screens/Settings/settings_screen_controller.dart';
import '../../utils/theme_controller.dart';
import '/models/playling_from.dart';
import '/utils/media_item_video.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import '../player_controller.dart';
import 'albumart_lyrics.dart';
import 'backgroud_image.dart';
import 'lyrics_switch.dart';
import 'lyrics_widget.dart';
import 'player_video_surface.dart';
import 'player_canvas_backdrop.dart';
import 'player_control.dart';
import '/ui/theme/riff_tokens.dart';

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
                // Portrait: the cover fills the top of the screen and fades
                // into the tinted backdrop where the controls start.
                if (!context.isLandscape)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: _heroArtHeight(size),
                    child: const _HeroArtBackdrop(),
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
                      // The cover itself is the backdrop; this layer takes
                      // the taps and swipes and hosts lyrics / video.
                      Expanded(
                        child: _HeroArtRegion(
                            isVideo: isVideo, showVideo: showVideo),
                      ),
                      const SizedBox(height: 8),
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
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: fg.withOpacity(0.6)),
                    ),
                    if (label.name.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        label.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: fg),
                      ),
                    ],
                  ],
                );
              }),
            ),
            // Podcast episodes: segments menu. Music: balances the collapse
            // button (song options sit by the title).
            Obx(() => playerController.isCurrentSongPodcast
                ? const PodcastPlayerMenuButton()
                : const SizedBox(width: 48)),
          ],
        ),
      ),
    );
  }
}

/// Height of the full-bleed cover at the top of the portrait player.
double _heroArtHeight(Size size) =>
    size.width > size.height * 0.58 ? size.width : size.height * 0.58;

/// Sharp cover across the top that fades out towards the controls, over
/// the tinted ambience the rest of the player uses.
class _HeroArtBackdrop extends StatelessWidget {
  const _HeroArtBackdrop();

  @override
  Widget build(BuildContext context) {
    final riff = RiffColors.of(context);
    return ShaderMask(
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [riff.onImage, riff.onImage, Colors.transparent],
        stops: const [0, 0.5, 1],
      ).createShader(Rect.fromLTWH(0, 0, rect.width, rect.height)),
      blendMode: BlendMode.dstIn,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const BackgroudImage(),
          // Keeps the "playing from" header readable on bright covers.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [riff.scrim.withOpacity(0.54), Colors.transparent],
                stops: const [0, 0.3],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Transparent layer over the cover: tap for lyrics (or play/pause on a
/// video), swipe to skip, long-press for the song menu. Hosts the lyrics
/// overlay, the video surface and the show-video button.
class _HeroArtRegion extends StatelessWidget {
  const _HeroArtRegion({required this.isVideo, required this.showVideo});
  final bool isVideo;
  final bool showVideo;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Obx(() {
      final song = playerController.currentSong.value;
      final lyricsOn = playerController.showLyricsflag.isTrue;
      if (song == null) return const SizedBox.shrink();
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (showVideo) {
            playerController.playPause();
          } else {
            playerController.showLyrics();
          }
        },
        onLongPress: () => openNowPlayingSheet(playerController),
        onHorizontalDragEnd: (details) {
          if (lyricsOn) return;
          final v = details.primaryVelocity ?? 0;
          if (v < 0) {
            playerController.next();
          } else if (v > 0) {
            playerController.prev();
          }
        },
        child: LayoutBuilder(builder: (context, box) {
          return Stack(
            fit: StackFit.expand,
            children: [
              if (showVideo)
                Center(
                  child: PlayerVideoSurface(
                    song: song,
                    width: box.maxWidth,
                    maxHeight: box.maxHeight,
                    onToggleVideo: () async {
                      await AlbumArtNLyrics.setVideoPlaybackEnabled(
                          song, false);
                      playerController.currentSong.refresh();
                    },
                  ),
                ),
              if (lyricsOn)
                ColoredBox(
                  color: RiffSurfaces.voidBlack.withOpacity(0.78),
                  child: Stack(
                    children: [
                      LyricsWidget(
                          padding: EdgeInsets.symmetric(
                              vertical: box.maxHeight / 4)),
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                RiffSurfaces.voidBlack.withOpacity(0.9),
                                Colors.transparent,
                                Colors.transparent,
                                RiffSurfaces.voidBlack.withOpacity(0.9),
                              ],
                              stops: const [0, 0.2, 0.8, 1],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!isVideo)
                const Align(
                    alignment: Alignment.topCenter, child: LyricsSwitch()),
              if (song.canShowPlayerVideo && !showVideo)
                Positioned(
                  right: 16,
                  top: 8,
                  child: PlayerVideoEnableButton(
                    onShow: () async {
                      await AlbumArtNLyrics.setVideoPlaybackEnabled(song, true);
                      playerController.currentSong.refresh();
                    },
                  ),
                ),
            ],
          );
        }),
      );
    });
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
    barrierColor: RiffColors.of(sheetContext).scrim.withAlpha(100),
    builder: (context) => SongInfoBottomSheet(song, calledFromPlayer: true),
  ).whenComplete(() => Get.delete<SongInfoController>());
}
