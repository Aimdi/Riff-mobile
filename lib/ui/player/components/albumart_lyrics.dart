import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '/models/media_item_extras.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';

import '/ui/player/components/lyrics_widget.dart';
import '/ui/player/components/player_video_surface.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/utils/media_item_video.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import '/ui/theme/riff_tokens.dart';

class AlbumArtNLyrics extends StatelessWidget {
  const AlbumArtNLyrics({super.key, required this.playerArtImageSize});
  final double playerArtImageSize;

  /// Music videos remember the choice. Podcast episodes keep it only for
  /// this launch, and off to begin with: the cover is shown until the user
  /// taps Video, so starting an episode never spins up the video engine on
  /// its own (that engine is native code, and a fault there takes the whole
  /// app down rather than showing an error).
  static bool videoPlaybackEnabledFor(MediaItem? song) {
    if (song != null && song.isPodcastEpisode) {
      return Get.isRegistered<SettingsScreenController>() &&
          Get.find<SettingsScreenController>().podcastVideoEnabled.isTrue;
    }
    final v = Hive.box('AppPrefs').get('playerShowVideo');
    if (v is bool) return v;
    // Cover until the user taps the video button.
    return false;
  }

  static Future<void> setVideoPlaybackEnabled(MediaItem? song, bool on) async {
    if (song != null && song.isPodcastEpisode) {
      if (Get.isRegistered<SettingsScreenController>()) {
        Get.find<SettingsScreenController>().podcastVideoEnabled.value = on;
      }
      return;
    }
    await Hive.box('AppPrefs').put('playerShowVideo', on);
  }

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    return Obx(() {
      final song = playerController.currentSong.value;
      if (song == null) return const SizedBox.shrink();

      // Lyrics dim the cover with the page colour, so their text reads in
      // the page's text colours.
      final page = Theme.of(context).colorScheme.surface;
      final canVideo = song.canShowPlayerVideo;
      final isVideo = canVideo && videoPlaybackEnabledFor(song);
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
                    final sheetContext =
                        playerController.homeScaffoldkey.currentContext ??
                            Get.context;
                    if (sheetContext == null) return;
                    HapticFeedback.mediumImpact();
                    showModalBottomSheet(
                      useRootNavigator: true,
                      constraints: const BoxConstraints(maxWidth: 500),
                      isScrollControlled: true,
                      context: sheetContext,
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
                            await AlbumArtNLyrics.setVideoPlaybackEnabled(
                                song, false);
                            playerController.currentSong.refresh();
                          },
                        )
                      : DecoratedBox(
                          // Flat artwork: no shadow (§2.1).
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(RiffRadii.sm),
                          ),
                          child: ImageWidget(
                            size: playerArtImageSize,
                            song: song,
                            isPlayerArtImage: true,
                            borderRadius: RiffRadii.sm,
                          ),
                        ),
                ),
                // Opt-in muted surface: stays off until the user taps show-video.
                if (canVideo && !isVideo)
                  Positioned(
                    right: RiffSpacing.sm,
                    top: RiffSpacing.sm,
                    child: PlayerVideoEnableButton(
                      onShow: () async {
                        await AlbumArtNLyrics.setVideoPlaybackEnabled(
                            song, true);
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
                            color: page.withOpacity(0.82),
                            borderRadius: BorderRadius.circular(RiffRadii.sm),
                          ),
                          child: Stack(
                            children: [
                              LyricsWidget(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 0, vertical: height / 3.5)),
                              IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.circular(RiffRadii.sm),
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        page.withOpacity(0.90),
                                        Colors.transparent,
                                        Colors.transparent,
                                        Colors.transparent,
                                        page.withOpacity(0.90)
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
              ],
            ),
          ),
        ),
      );
    });
  }
}
