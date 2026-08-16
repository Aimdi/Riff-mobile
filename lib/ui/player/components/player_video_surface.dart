import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '/ui/player/player_controller.dart';
import '/ui/player/video_mode_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';

/// In-player video pane for YouTube *videos*.
///
/// Unlike the old muted-surface approach (a second ExoPlayer chasing the
/// audio clock with rate nudges and periodic seeks — the source of the
/// notorious lag/desync), this pane hands playback to [VideoModeController]:
/// ONE mpv engine plays the video stream plus the exact audio stream the
/// music pipeline uses, so A/V sync is the engine's own frame scheduling.
/// While the pane is visible the engine owns playback; collapsing the
/// panel, hiding video, changing songs or backgrounding hands playback
/// back to the audio pipeline at the same position.
class PlayerVideoSurface extends StatefulWidget {
  const PlayerVideoSurface({
    super.key,
    required this.song,
    required this.width,
    this.maxHeight,
    this.showControls = true,
    this.onToggleVideo,
  });

  final MediaItem song;
  final double width;
  final double? maxHeight;
  final bool showControls;
  final VoidCallback? onToggleVideo;

  @override
  State<PlayerVideoSurface> createState() => _PlayerVideoSurfaceState();
}

class _PlayerVideoSurfaceState extends State<PlayerVideoSurface>
    with WidgetsBindingObserver {
  bool _failed = false;
  Worker? _panelWorker;
  Worker? _qualityWorker;

  PlayerController get _player => Get.find<PlayerController>();
  VideoModeController get _vm => Get.find<VideoModeController>();

  bool get _panelOpen {
    if (GetPlatform.isDesktop) return true;
    return _player.isPlayerPanelOpen.value;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Engine boots only while the full player is visible — the mini
    // player keeps the plain audio pipeline.
    if (_panelOpen) _engage();
    _panelWorker =
        ever(_player.isPlayerPanelOpen, (_) => _onPanelOpenChanged());
    if (Get.isRegistered<SettingsScreenController>()) {
      _qualityWorker =
          ever(Get.find<SettingsScreenController>().videoQuality, (_) {
        if (mounted && _panelOpen) _engage(reload: true);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding is handled inside VideoModeController (hand back to
    // audio); on return, re-engage if the pane is still what's on screen.
    if (state == AppLifecycleState.resumed && mounted && _panelOpen) {
      _engage();
    }
  }

  @override
  void didUpdateWidget(covariant PlayerVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id && _panelOpen) {
      _engage();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _panelWorker?.dispose();
    _qualityWorker?.dispose();
    // Only tear down the session this surface owns — a replacement surface
    // for the next song may already have engaged the engine.
    unawaited(_vm.disableIfActiveFor(widget.song.id));
    super.dispose();
  }

  Future<void> _engage({bool reload = false}) async {
    final wasPlaying = _player.buttonState.value == PlayButtonState.playing ||
        _vm.isVideoPlaying.value;
    if (reload) await _vm.disableIfActiveFor(widget.song.id, resume: false);
    final ok = await _vm.enable(wasPlayingBeforeHandoff: wasPlaying);
    if (mounted && !ok) {
      setState(() => _failed = true);
    } else if (mounted && _failed) {
      setState(() => _failed = false);
    }
  }

  void _onPanelOpenChanged() {
    if (!_panelOpen) {
      // Collapsed to the mini player — audio pipeline takes over, engine
      // stops decoding entirely.
      unawaited(_vm.disableIfActiveFor(widget.song.id));
    } else {
      _engage();
    }
  }

  Future<void> _openFullscreen() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _FullscreenVideoPage(song: widget.song),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.maxHeight ?? (widget.width * 9 / 16);
    return SizedBox(
      width: widget.width,
      height: height,
      child: ColoredBox(
        color: Colors.black,
        child: Obx(() {
          final ready = _vm.isActive.value && _vm.videoController != null;
          final loading = _vm.isLoading.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (ready)
                Center(
                  child: AspectRatio(
                    aspectRatio: _vm.videoAspect.value <= 0
                        ? 16 / 9
                        : _vm.videoAspect.value,
                    child: RepaintBoundary(
                      child: Video(
                        controller: _vm.videoController!,
                        controls: NoVideoControls,
                        fill: Colors.black,
                      ),
                    ),
                  ),
                ),
              if (loading)
                const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (_failed && !loading)
                Center(
                  child: Text(
                    'videoUnavailable'.tr,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              if (widget.showControls && !loading)
                Positioned(
                  left: 8,
                  top: 8,
                  child: _VideoBadge(failed: _failed),
                ),
              if (widget.showControls && !loading)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onToggleVideo != null)
                        _OverlayIconButton(
                          tooltip: 'videoHide'.tr,
                          icon: Icons.videocam_off_outlined,
                          onPressed: widget.onToggleVideo!,
                        ),
                      if (!_failed && ready)
                        _OverlayIconButton(
                          tooltip: 'videoFullscreen'.tr,
                          icon: Icons.fullscreen,
                          onPressed: _openFullscreen,
                        ),
                    ],
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.45),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _VideoBadge extends StatelessWidget {
  const _VideoBadge({required this.failed});
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        failed ? 'videoUnavailable'.tr : 'video'.tr,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({required this.song});

  final MediaItem song;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    final vm = Get.find<VideoModeController>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Obx(() {
          // Video mode ended underneath (song change / background) — leave.
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
              if (vm.videoController != null)
                Center(
                  child: AspectRatio(
                    aspectRatio:
                        vm.videoAspect.value <= 0 ? 16 / 9 : vm.videoAspect.value,
                    child: Video(
                      controller: vm.videoController!,
                      controls: NoVideoControls,
                      fill: Colors.black,
                    ),
                  ),
                ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => player.playPause(),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: IconButton(
                  tooltip: 'close'.tr,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    if ((widget.song.artist ?? '').isNotEmpty)
                      Text(
                        widget.song.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Obx(() {
                      final st = player.progressBarStatus.value;
                      final total = st.total.inMilliseconds <= 0
                          ? 1.0
                          : st.total.inMilliseconds.toDouble();
                      final cur = st.current.inMilliseconds
                          .clamp(0, total.toInt())
                          .toDouble();
                      return SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: cur,
                          max: total,
                          // Routed through the transport, which drives the
                          // engine that owns playback.
                          onChanged: (v) =>
                              player.seek(Duration(milliseconds: v.round())),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// Compact circular control on album/cover art — tap to opt into video.
class PlayerVideoEnableButton extends StatelessWidget {
  const PlayerVideoEnableButton({super.key, required this.onShow});

  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.55),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: 'videoShow'.tr,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: onShow,
        icon: const Icon(Icons.videocam_outlined, color: Colors.white, size: 22),
      ),
    );
  }
}

/// Compact toggle used when video is hidden (audio-only mode for a video item).
class PlayerVideoShowChip extends StatelessWidget {
  const PlayerVideoShowChip({super.key, required this.onShow});

  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onShow,
      icon: const Icon(Icons.videocam_outlined, size: 18),
      label: Text('videoShow'.tr),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
