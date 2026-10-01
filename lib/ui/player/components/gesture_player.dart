import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../widgets/favorite_heart_button.dart';
import '../../widgets/lyrics_dialog.dart';
import '../../widgets/sleep_timer_bottom_sheet.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import '../../utils/theme_controller.dart';
import '/utils/content_filters.dart';
import '../player_controller.dart';
import 'animated_play_button.dart';
import 'backgroud_image.dart';
import 'player_control.dart';
import 'standard_player.dart';

/// Full-bleed cover player: the artwork fills the screen and is the control
/// surface (swipe for next / previous, double-tap to play or pause,
/// long-press for song options). Title, seek bar, transport and actions sit
/// on a gradient at the bottom, styled like the standard player.
class GesturePlayer extends StatelessWidget {
  const GesturePlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final pc = Get.find<PlayerController>();
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final bottomInset = Get.mediaQuery.padding.bottom;
    return Stack(
      children: [
        GestureDetector(
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v < 0) {
              pc.next();
            } else if (v > 0) {
              pc.prev();
            }
          },
          onDoubleTap: pc.playPause,
          onLongPress: () => showCurrentSongSheet(
            song: pc.currentSong.value,
            context: pc.homeScaffoldkey.currentContext,
          ),
          child: const BackgroudImage(),
        ),
        // Readable bottom: fade the cover into the page colour.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.35),
                  Colors.transparent,
                  theme.primaryColor.withOpacity(0.85),
                  theme.primaryColor,
                ],
                stops: const [0, 0.25, 0.62, 0.85],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        // Play / pause flash after a double-tap.
        if (pc.gesturePlayerStateAnimation != null)
          IgnorePointer(
            child: Center(
              child: Obx(() => FadeTransition(
                    opacity: pc.gesturePlayerStateAnimation!,
                    child: pc.gesturePlayerVisibleState.value == 2
                        ? const SizedBox.shrink()
                        : Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.45),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              pc.gesturePlayerVisibleState.value == 1
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              size: 60,
                              color: accent,
                            ),
                          ),
                  )),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 80 + bottomInset),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Obx(() {
                          final song = pc.currentSong.value;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (song?.title ?? '').isEmpty
                                    ? '—'
                                    : song!.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                song?.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: (theme.textTheme.titleMedium?.color ??
                                          RiffSurfaces.textPrimary)
                                      .withOpacity(0.7),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                      const SizedBox(width: 8),
                      FavoriteHeartButton(
                        isFav: pc.isCurrentSongFav,
                        onToggleFav: pc.toggleFavourite,
                        song: () => pc.currentSong.value,
                        iconSize: 28,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const PlaybackErrorBanner(),
                  const RepaintBoundary(child: PlayerSeekScrubber()),
                  const SizedBox(height: 6),
                  _Transport(pc: pc),
                  const SizedBox(height: 10),
                  _Actions(pc: pc),
                ],
              ),
            ),
          ),
        ),
        const PlayerTopBar(),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.pc});
  final PlayerController pc;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).textTheme.titleMedium?.color ??
        RiffSurfaces.textPrimary;
    final accent = Theme.of(context).colorScheme.secondary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Obx(() => IconButton(
              tooltip: 'shuffle'.tr,
              iconSize: 24,
              onPressed: pc.toggleShuffleMode,
              icon: Icon(Icons.shuffle_rounded,
                  color: pc.isShuffleModeEnabled.value
                      ? accent
                      : fg.withOpacity(0.75)),
            )),
        IconButton(
          tooltip: 'previous'.tr,
          iconSize: 38,
          onPressed: pc.prev,
          icon: Icon(Icons.skip_previous_rounded, color: fg),
        ),
        const AnimatedPlayButton(key: Key('gesturePlayButton'), size: 68),
        IconButton(
          tooltip: 'next'.tr,
          iconSize: 38,
          onPressed: pc.next,
          icon: Icon(Icons.skip_next_rounded, color: fg),
        ),
        Obx(() {
          final state = pc.repeatState;
          return IconButton(
            tooltip: state == 2
                ? 'repeatOne'.tr
                : state == 1
                    ? 'repeatAll'.tr
                    : 'repeat'.tr,
            iconSize: 24,
            onPressed: pc.cycleRepeatMode,
            icon: Icon(
              state == 2 ? Icons.repeat_one_rounded : Icons.repeat_rounded,
              color: state != 0 ? accent : fg.withOpacity(0.75),
            ),
          );
        }),
      ],
    );
  }
}

/// Lyrics · sleep timer · share.
class _Actions extends StatelessWidget {
  const _Actions({required this.pc});
  final PlayerController pc;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final song = pc.currentSong.value;
      final sleepOn = pc.isSleepTimerActive.isTrue;
      return PlayerActionBar(actions: [
        PlayerAction(
          icon: Icons.lyrics_outlined,
          activeIcon: Icons.lyrics,
          tooltip: 'lyrics'.tr,
          active: pc.showLyricsflag.isTrue,
          onTap: () {
            pc.showLyrics();
            pc.isDesktopLyricsDialogOpen = true;
            showDialog(
              context: context,
              builder: (context) => const LyricsDialog(),
            ).whenComplete(() {
              pc.isDesktopLyricsDialogOpen = false;
              pc.showLyricsflag.value = false;
            });
          },
        ),
        PlayerAction(
          icon: Icons.bedtime_outlined,
          activeIcon: Icons.bedtime,
          tooltip: 'sleepTimer'.tr,
          active: sleepOn,
          badge: sleepOn ? sleepTimerBadge(pc.timerDurationLeft.value) : null,
          onTap: () =>
              showSleepTimerSheet(pc.homeScaffoldkey.currentContext ?? context),
        ),
        PlayerAction(
          icon: Icons.share_outlined,
          tooltip: 'shareSong'.tr,
          onTap: song == null
              ? null
              : () => Share.share(SongLinkShare.shareText(song)),
        ),
      ]);
    });
  }
}
