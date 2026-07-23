import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ionicons/ionicons.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/ui/player/components/animated_play_button.dart';
import '/ui/player/components/podcast_transcript_sheet.dart';
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
                    final song = playerController.currentSong.value;
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.08),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        key: ValueKey<String>(song?.id ?? 'none'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _openAlbum(playerController),
                            child: Marquee(
                              delay: const Duration(milliseconds: 300),
                              duration: const Duration(seconds: 10),
                              id: "${song}_title",
                              child: Text(
                                song?.title ?? "NA",
                                textAlign: TextAlign.start,
                                style: Theme.of(context).textTheme.labelMedium!,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _openArtist(playerController),
                            child: Marquee(
                              delay: const Duration(milliseconds: 300),
                              duration: const Duration(seconds: 10),
                              id: "${song}_subtitle",
                              child: Text(
                                song?.artist ?? "NA",
                                textAlign: TextAlign.start,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          )
                        ],
                      ),
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
          // Shownotes + Transcript (podcast only) — above the seek bar like
          // AntennaPod. Transcript appears when the feed publishes a
          // Podcasting 2.0 <podcast:transcript> for the episode.
          Obx(() {
            if (!playerController.isCurrentSongPodcast) {
              return const SizedBox.shrink();
            }
            final song = playerController.currentSong.value;
            final transcriptUrl =
                (song?.extras?['transcriptUrl'] ?? '').toString();
            final style = OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
              side: BorderSide(
                  color: Theme.of(context)
                      .textTheme
                      .titleLarge!
                      .color!
                      .withOpacity(0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openShownotes(playerController, context),
                    icon: const Icon(Icons.info_outline, size: 20),
                    label: Text("shownotes".tr),
                    style: style,
                  ),
                  if (playerController.hasChapters)
                    OutlinedButton.icon(
                      onPressed: () =>
                          _openChapters(playerController, context),
                      icon: const Icon(Icons.list_rounded, size: 20),
                      label: Text("chapters".tr),
                      style: style,
                    ),
                  if (transcriptUrl.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => PodcastTranscriptSheet.open(
                        context,
                        url: transcriptUrl,
                        type:
                            '${song?.extras?['transcriptType'] ?? ''}',
                      ),
                      icon: const Icon(Icons.subtitles_outlined, size: 20),
                      label: Text("transcript".tr),
                      style: style,
                    ),
                ],
              ),
            );
          }),
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
          final state = playerController.repeatState;
          final baseColor = Theme.of(context).textTheme.titleLarge!.color!;
          return IconButton(
              tooltip: state == 2
                  ? "repeatOne".tr
                  : state == 1
                      ? "repeatAll".tr
                      : "repeat".tr,
              onPressed: playerController.cycleRepeatMode,
              icon: Icon(
                // repeat_one shows the "1" badge (Spotify-style).
                state == 2 ? Icons.repeat_one : Icons.repeat,
                color: state == 0 ? baseColor.withOpacity(0.2) : baseColor,
              ));
        }),
      ],
    );
  }

  /// AntennaPod-style transport: autoplay · speed · −10s · play/pause · +30s · next.
  Widget _podcastControls(
      PlayerController playerController, BuildContext context) {
    final color = Theme.of(context).textTheme.titleMedium!.color;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Skip ad" pill — shown while playback is inside a detected ad chapter.
        Obx(() => AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: playerController.inAdChapter.isFalse
                  ? const SizedBox(height: 0, width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ActionChip(
                        avatar: Icon(Icons.fast_forward,
                            size: 18, color: Theme.of(context).colorScheme.onSecondary),
                        label: Text('skipAd'.tr,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSecondary,
                                fontWeight: FontWeight.w600)),
                        backgroundColor: Theme.of(context).colorScheme.secondary,
                        onPressed: playerController.skipAd,
                      ),
                    ),
            )),
        _podcastButtonsRow(playerController, context, color),
      ],
    );
  }

  Widget _podcastButtonsRow(PlayerController playerController,
      BuildContext context, Color? color) {
    final settings = Get.find<SettingsScreenController>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Continuous autoplay toggle (AntennaPod-experimental shortcut).
        Obx(() {
          final on = settings.podcastContinuousPlaybackEnabled.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: on
                    ? 'podcastAutoplayOn'.tr
                    : 'podcastAutoplayOff'.tr,
                iconSize: 26,
                onPressed: () =>
                    settings.togglePodcastContinuousPlayback(!on),
                icon: Icon(
                  on ? Icons.playlist_play_rounded : Icons.playlist_remove_rounded,
                  color: on
                      ? Theme.of(context).colorScheme.secondary
                      : color,
                ),
              ),
              Text(on ? 'auto'.tr : 'stop'.tr,
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          );
        }),
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

  void _openChapters(PlayerController playerController, BuildContext context) {
    final chapters = playerController.chapters;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) {
          String fmt(double sec) {
            final d = Duration(milliseconds: (sec * 1000).round());
            final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
            final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
            final h = d.inHours;
            return h > 0 ? '$h:$m:$s' : '$m:$s';
          }

          return ListView.builder(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
            itemCount: chapters.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Text('chapters'.tr,
                      style: Theme.of(ctx).textTheme.titleLarge),
                );
              }
              final c = chapters[i - 1];
              return ListTile(
                leading: Icon(
                  c.isAd ? Icons.campaign_outlined : Icons.play_arrow_rounded,
                  color: c.isAd
                      ? Theme.of(ctx).colorScheme.error
                      : Theme.of(ctx).colorScheme.secondary,
                ),
                title: Text(c.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(fmt(c.startSec)),
                onTap: () {
                  Navigator.pop(ctx);
                  playerController.seek(
                    Duration(milliseconds: (c.startSec * 1000).round()),
                  );
                },
              );
            },
          );
        },
      ),
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
