import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ionicons/ionicons.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/ui/player/components/animated_play_button.dart';
import '../../screens/Settings/settings_screen_controller.dart';
import '../../widgets/discovery/player_similar_row.dart';
import '../player_controller.dart';

class PlayerControlWidget extends StatelessWidget {
  const PlayerControlWidget({super.key});

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
                        Marquee(
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
                        const SizedBox(
                          height: 5,
                        ),
                        Marquee(
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
          GetX<PlayerController>(builder: (controller) {
            return ProgressBar(
              thumbRadius: 7,
              barHeight: 4.5,
              baseBarColor: Theme.of(context).sliderTheme.inactiveTrackColor,
              bufferedBarColor:
                  Theme.of(context).sliderTheme.valueIndicatorColor,
              progressBarColor: Theme.of(context).sliderTheme.activeTrackColor,
              thumbColor: Theme.of(context).sliderTheme.thumbColor,
              timeLabelTextStyle: Theme.of(context)
                  .textTheme
                  .titleMedium!
                  .copyWith(fontSize: 14),
              progress: controller.progressBarStatus.value.current,
              total: controller.progressBarStatus.value.total,
              buffered: controller.progressBarStatus.value.buffered,
              onSeek: controller.seek,
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
