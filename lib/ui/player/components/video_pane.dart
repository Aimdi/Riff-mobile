import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../player_controller.dart';
import '../video_mode_controller.dart';

/// Inline 16:9 video pane shown in place of the album art while video mode
/// is active. Rendering comes straight from the mpv engine that also plays
/// the audio, so what you see is engine-synced — the pane adds only the
/// video-off and fullscreen buttons (like the classic layout).
class VideoPane extends StatelessWidget {
  const VideoPane({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final vm = Get.find<VideoModeController>();
    final controller = vm.videoController;
    if (controller == null) {
      return SizedBox.square(dimension: size);
    }
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Video(
                  controller: controller,
                  controls: NoVideoControls,
                  fill: Colors.black,
                ),
                // Tap anywhere on the frame to play/pause (routed through
                // the normal transport, which drives the mpv engine here).
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => Get.find<PlayerController>().playPause(),
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _OverlayButton(
                          icon: Icons.videocam_off_outlined,
                          tooltip: 'video'.tr,
                          onTap: () => vm.disable(),
                        ),
                        const SizedBox(width: 6),
                        _OverlayButton(
                          icon: Icons.fullscreen,
                          tooltip: 'fullscreen'.tr,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const VideoFullscreenPage()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton(
      {required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

/// Landscape, immersive fullscreen for video mode. Transport still routes
/// through PlayerController (which drives the mpv engine while active).
class VideoFullscreenPage extends StatefulWidget {
  const VideoFullscreenPage({super.key});

  @override
  State<VideoFullscreenPage> createState() => _VideoFullscreenPageState();
}

class _VideoFullscreenPageState extends State<VideoFullscreenPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = Get.find<VideoModeController>();
    final playerController = Get.find<PlayerController>();
    final controller = vm.videoController;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        // Video mode ended underneath (song change/background) — leave.
        if (!vm.isActive.value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            if (controller != null)
              Positioned.fill(
                child: Video(
                  controller: controller,
                  controls: NoVideoControls,
                  fill: Colors.black,
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => playerController.playPause(),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _OverlayButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    children: [
                      Obx(() => _OverlayButton(
                            icon: vm.isVideoPlaying.value
                                ? Icons.pause
                                : Icons.play_arrow,
                            onTap: () => playerController.playPause(),
                          )),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Obx(() {
                          final status =
                              playerController.progressBarStatus.value;
                          return ProgressBar(
                            progress: status.current,
                            total: status.total,
                            buffered: status.buffered,
                            onSeek: playerController.seek,
                            timeLabelTextStyle: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                            baseBarColor: Colors.white24,
                            bufferedBarColor: Colors.white38,
                            progressBarColor:
                                Theme.of(context).colorScheme.secondary,
                            thumbColor:
                                Theme.of(context).colorScheme.secondary,
                            thumbRadius: 7,
                            barHeight: 4,
                          );
                        }),
                      ),
                      const SizedBox(width: 12),
                      _OverlayButton(
                        icon: Icons.fullscreen_exit,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
