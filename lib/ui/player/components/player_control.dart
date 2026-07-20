import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ionicons/ionicons.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/ui/player/components/animated_play_button.dart';
import '../../navigator.dart';
import '../../screens/Settings/settings_screen_controller.dart';
import '../../widgets/discovery/player_similar_row.dart';
import '../player_controller.dart';

class PlayerControlWidget extends StatelessWidget {
  const PlayerControlWidget({super.key});

  /// Open the album/single of the currently-playing song (no-op when the track
  /// carries no album, e.g. a podcast episode).
  void _openAlbum(PlayerController playerController) {
    final song = playerController.currentSong.value;
    final album = song?.extras?['album'];
    if (album is Map && album['id'] != null) {
      playerController.playerPanelController.close();
      Get.toNamed(ScreenNavigationSetup.albumScreen,
          id: ScreenNavigationSetup.id, arguments: (null, album['id']));
    }
  }

  /// Open the artist page for the currently-playing song. Uses the first
  /// artist that has a browse id (no-op when none is available).
  void _openArtist(PlayerController playerController) {
    final song = playerController.currentSong.value;
    final artists = song?.extras?['artists'];
    String? artistId;
    if (artists is List) {
      for (final a in artists) {
        if (a is Map && a['id'] != null) {
          artistId = '${a['id']}';
          break;
        }
      }
    }
    if (artistId != null) {
      playerController.playerPanelController.close();
      Get.toNamed(ScreenNavigationSetup.artistScreen,
          id: ScreenNavigationSetup.id,
          preventDuplicates: true,
          arguments: [true, artistId]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: ShaderMask(
                  shaderCallback: (rect) {
                    return const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.transparent
                      ],
                    ).createShader(
                        Rect.fromLTWH(0, 0, rect.width, rect.height));
                  },
                  blendMode: BlendMode.dstIn,
                  child: Obx(() {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          // Tap the title -> open its album/single (if any).
                          onTap: () => _openAlbum(playerController),
                          child: Marquee(
                            delay: const Duration(milliseconds: 300),
                            duration: const Duration(seconds: 10),
                            id: "${playerController.currentSong.value}_title",
                            child: Text(
                              playerController.currentSong.value != null
                                  ? playerController.currentSong.value!.title
                                  : "NA",
                              textAlign: TextAlign.start,
                              style: Theme.of(context).textTheme.labelMedium!,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          // Tap the artist -> open the artist page.
                          onTap: () => _openArtist(playerController),
                          child: Marquee(
                            delay: const Duration(milliseconds: 300),
                            duration: const Duration(seconds: 10),
                            id: "${playerController.currentSong.value}_subtitle",
                            child: Text(
                              playerController.currentSong.value != null
                                  ? playerController.currentSong.value!.artist!
                                  : "NA",
                              textAlign: TextAlign.start,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        )
                      ],
                    );
                  }),
                ),
              ),
              SizedBox(
                width: 45,
                child: IconButton(
                    onPressed: playerController.toggleFavourite,
                    icon: Obx(() => Icon(
                          playerController.isCurrentSongFav.isFalse
                              ? Icons.favorite_border
                              : Icons.favorite,
                          color: Theme.of(context).textTheme.titleMedium!.color,
                        ))),
              ),
            ],
          ),
          const SizedBox(
            height: 20,
          ),
          // Shownotes (podcast only) — sits above the seek bar like AntennaPod.
          Obx(() => playerController.isCurrentSongPodcast
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: OutlinedButton.icon(
                    onPressed: () => _openShownotes(playerController, context),
                    icon: const Icon(Icons.info_outline, size: 20),
                    label: Text("shownotes".tr),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).textTheme.titleMedium!.color,
                      side: BorderSide(
                          color: Theme.of(context)
                              .textTheme
                              .titleLarge!
                              .color!
                              .withOpacity(0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                )
              : const SizedBox.shrink()),
          // The seek control IS the SoundCloud-style waveform (no separate
          // slider line): it fills with the accent colour as the track plays,
          // shows the elapsed/total time beneath, and is tap/drag seekable.
          GetX<PlayerController>(builder: (controller) {
            final status = controller.progressBarStatus.value;
            final totalMs = status.total.inMilliseconds;
            final frac = totalMs > 0
                ? (status.current.inMilliseconds / totalMs).clamp(0.0, 1.0)
                : 0.0;
            final song = controller.currentSong.value;
            final seed = (song?.id ?? song?.title ?? '').hashCode;
            final timeStyle = Theme.of(context)
                .textTheme
                .titleMedium!
                .copyWith(fontSize: 14);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                children: [
                  LayoutBuilder(builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    void seekTo(double dx) {
                      if (totalMs <= 0 || width <= 0) return;
                      final f = (dx / width).clamp(0.0, 1.0);
                      controller.seek(status.total * f);
                    }

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => seekTo(d.localPosition.dx),
                      onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
                      child: SizedBox(
                        height: 34,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _WaveformPainter(
                            progress: frac,
                            seed: seed,
                            playedColor: Theme.of(context)
                                    .sliderTheme
                                    .activeTrackColor ??
                                Theme.of(context).colorScheme.secondary,
                            unplayedColor: (Theme.of(context)
                                        .sliderTheme
                                        .inactiveTrackColor ??
                                    Colors.grey)
                                .withOpacity(0.55),
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmtDuration(status.current), style: timeStyle),
                      Text(_fmtDuration(status.total), style: timeStyle),
                    ],
                  ),
                ],
              ),
            );
          }),
          Obx(() => playerController.isCurrentSongPodcast
              ? _podcastControls(playerController, context)
              : _musicControls(playerController, context)),
          // Similar songs are music-only; hide for podcast episodes.
          Obx(() => playerController.isCurrentSongPodcast
              ? const SizedBox.shrink()
              : const PlayerSimilarRow()),
        ]);
  }

  Widget _musicControls(
      PlayerController playerController, BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
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
        _previousButton(playerController, context),
        const CircleAvatar(
            radius: 35, child: AnimatedPlayButton(key: Key("playButton"))),
        _nextButton(playerController, context),
        Obx(() {
          return IconButton(
              onPressed: playerController.toggleLoopMode,
              icon: Icon(
                Icons.all_inclusive,
                color: playerController.isLoopModeEnabled.value
                    ? Theme.of(context).textTheme.titleLarge!.color
                    : Theme.of(context)
                        .textTheme
                        .titleLarge!
                        .color!
                        .withOpacity(0.2),
              ));
        }),
      ],
    );
  }

  /// AntennaPod-style transport: speed · −10s · play/pause · +30s · next.
  Widget _podcastControls(
      PlayerController playerController, BuildContext context) {
    final color = Theme.of(context).textTheme.titleMedium!.color;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Playback speed — tap to cycle common podcast speeds.
        _SpeedButton(color: color),
        // Skip back 10s
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              iconSize: 32,
              onPressed: () =>
                  playerController.seekBy(const Duration(seconds: -10)),
              icon: Icon(Icons.replay_10, color: color),
            ),
            Text("10", style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        const CircleAvatar(
            radius: 35,
            child: AnimatedPlayButton(key: Key("podcastPlayButton"))),
        // Skip forward 30s
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              iconSize: 32,
              onPressed: () =>
                  playerController.seekBy(const Duration(seconds: 30)),
              icon: Icon(Icons.forward_30, color: color),
            ),
            Text("30", style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        _nextButton(playerController, context),
      ],
    );
  }

  void _openShownotes(PlayerController playerController, BuildContext context) {
    final song = playerController.currentSong.value;
    final notes = (song?.extras?['description'] ?? '').toString().trim();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(song?.title ?? '',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(song?.artist ?? '',
                  style: Theme.of(ctx).textTheme.titleSmall),
              const Divider(height: 24),
              Text(
                notes.isEmpty ? "noShownotes".tr : notes,
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _previousButton(
      PlayerController playerController, BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.skip_previous,
        color: Theme.of(context).textTheme.titleMedium!.color,
      ),
      iconSize: 30,
      onPressed: playerController.prev,
    );
  }
}

/// Podcast playback-speed control: shows the current speed, tap cycles through
/// common podcast speeds. Persists via SettingsScreenController like the
/// speed/pitch dialog.
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.color});
  final Color? color;

  static const _speeds = [0.8, 1.0, 1.2, 1.5, 1.75, 2.0];

  void _cycle() {
    final settings = Get.find<SettingsScreenController>();
    final cur = settings.playbackSpeed.value;
    final idx = _speeds.indexWhere((s) => (s - cur).abs() < 0.01);
    final next = _speeds[(idx + 1) % _speeds.length];
    settings.setBox.put("playbackSpeed", next);
    settings.playbackSpeed.value = next;
    Get.find<PlayerController>()
        .setSpeedAndPitch(speed: next, pitch: settings.playbackPitch.value);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsScreenController>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 30,
          onPressed: _cycle,
          icon: Icon(Icons.speed, color: color),
        ),
        Obx(() => Text(
              settings.playbackSpeed.value.toStringAsFixed(2),
              style: Theme.of(context).textTheme.labelSmall,
            )),
      ],
    );
  }
}

Widget _nextButton(PlayerController playerController, BuildContext context) {
  return Obx(() {
    final isLastSong = playerController.currentQueue.isEmpty ||
        (!(playerController.isShuffleModeEnabled.isTrue ||
                playerController.isQueueLoopModeEnabled.isTrue) &&
            (playerController.currentQueue.last.id ==
                playerController.currentSong.value?.id));
    return IconButton(
        icon: Icon(
          Icons.skip_next,
          color: isLastSong
              ? Theme.of(context).textTheme.titleLarge!.color!.withOpacity(0.2)
              : Theme.of(context).textTheme.titleMedium!.color,
        ),
        iconSize: 30,
        onPressed: isLastSong ? null : playerController.next);
  });
}

/// Format a playback position as m:ss (or h:mm:ss for long tracks).
String _fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// A thin SoundCloud-style waveform. Bar heights are deterministic per song
/// (hashed from a seed) so they stay stable across rebuilds; the played portion
/// is drawn in [playedColor], the rest in [unplayedColor].
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.seed,
    required this.playedColor,
    required this.unplayedColor,
  });

  final double progress; // 0..1
  final int seed;
  final Color playedColor;
  final Color unplayedColor;

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 2.0;
    const gap = 2.0;
    const step = barWidth + gap;
    final count = (size.width / step).floor();
    if (count <= 0) return;
    final midY = size.height / 2;
    final playedBars = (count * progress).round();
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;
    for (int i = 0; i < count; i++) {
      // Deterministic pseudo-random amplitude in [0.30, 1.0].
      final n = (seed ^ (i * 2654435761)) & 0x7fffffff;
      final amp = 0.30 + (n % 1000) / 1000.0 * 0.70;
      final barH = size.height * amp;
      final x = i * step + barWidth / 2;
      paint.color = i < playedBars ? playedColor : unplayedColor;
      canvas.drawLine(
          Offset(x, midY - barH / 2), Offset(x, midY + barH / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress ||
      old.seed != seed ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}
