import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '/services/video_stream_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/utils/media_item_video.dart';

/// Spotify-style in-player video pane for YouTube *videos* only.
///
/// Audio stays on just_audio (source of truth). Video is muted and lightly
/// seek-synced — aggressive sync was a major source of stutter.
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
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;
  bool _seeking = false;
  Worker? _playWorker;
  Worker? _panelWorker;
  Worker? _seekWorker;
  Worker? _speedWorker;
  Timer? _syncTimer;
  Duration _lastAudioPos = Duration.zero;

  PlayerController get _player => Get.find<PlayerController>();

  bool get _panelOpen {
    // Desktop keeps the player visible; on mobile, pause decode while the
    // slide-up panel is collapsed (mini player only).
    if (GetPlatform.isDesktop) return true;
    return _player.isPlayerPanelOpen.value;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot(widget.song);
    _playWorker = ever(_player.buttonState, (_) => _syncPlayPause());
    _panelWorker = ever(_player.isPlayerPanelOpen, (_) => _onPanelOpenChanged());
    _seekWorker = ever(_player.videoSeekSignal, (_) => _onExternalSeek());
    if (Get.isRegistered<SettingsScreenController>()) {
      _speedWorker = ever(
        Get.find<SettingsScreenController>().playbackSpeed,
        (_) => _applySpeed(),
      );
    }
    // Soft-sync rarely — frequent seeks were a major hitch source.
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_panelOpen) return;
      _correctDrift(soft: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(c.pause());
    } else if (state == AppLifecycleState.resumed) {
      _syncPlayPause();
      if (_panelOpen) _correctDrift(soft: false);
    }
  }

  @override
  void didUpdateWidget(covariant PlayerVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _boot(widget.song);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playWorker?.dispose();
    _panelWorker?.dispose();
    _seekWorker?.dispose();
    _speedWorker?.dispose();
    _syncTimer?.cancel();
    final c = _controller;
    _controller = null;
    unawaited(c?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  void _onPanelOpenChanged() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (!_panelOpen) {
      if (c.value.isPlaying) unawaited(c.pause());
      return;
    }
    _correctDrift(soft: false);
    _syncPlayPause();
  }

  void _onExternalSeek() {
    if (!_panelOpen) return;
    _correctDrift(soft: false);
  }

  Future<void> _applySpeed() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (!Get.isRegistered<SettingsScreenController>()) return;
    final speed = Get.find<SettingsScreenController>().playbackSpeed.value;
    try {
      await c.setPlaybackSpeed(speed.clamp(0.25, 2.0));
    } catch (_) {}
  }

  Future<void> _boot(MediaItem song) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final old = _controller;
    _controller = null;
    await old?.dispose();

    if (!song.canShowPlayerVideo) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }

    try {
      final info = await VideoStreamService.resolve(song.id)
          .timeout(const Duration(seconds: 12));
      if (!mounted || widget.song.id != song.id) return;
      if (info == null) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }

      final c = VideoPlayerController.networkUrl(
        Uri.parse(info.url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(false);
      await _applySpeedTo(c);
      final pos = _player.progressBarStatus.value.current;
      if (pos > Duration.zero) {
        await c.seekTo(pos);
      }
      // Only start decoding when the full player is visible.
      if (_panelOpen &&
          _player.buttonState.value == PlayButtonState.playing) {
        unawaited(c.play());
      } else {
        await c.pause();
      }
      if (!mounted || widget.song.id != song.id) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (mounted && widget.song.id == song.id) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _applySpeedTo(VideoPlayerController c) async {
    if (!Get.isRegistered<SettingsScreenController>()) return;
    final speed = Get.find<SettingsScreenController>().playbackSpeed.value;
    try {
      await c.setPlaybackSpeed(speed.clamp(0.25, 2.0));
    } catch (_) {}
  }

  void _syncPlayPause() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (!_panelOpen) {
      if (c.value.isPlaying) unawaited(c.pause());
      return;
    }
    final playing = _player.buttonState.value == PlayButtonState.playing;
    if (playing && !c.value.isPlaying) {
      unawaited(c.play());
    } else if (!playing && c.value.isPlaying) {
      unawaited(c.pause());
    }
  }

  void _correctDrift({required bool soft}) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _seeking) return;
    if (!_panelOpen) return;
    final audioPos = _player.progressBarStatus.value.current;
    final jumped =
        (audioPos - _lastAudioPos).abs() > const Duration(seconds: 1);
    _lastAudioPos = audioPos;
    final drift = (audioPos - c.value.position).abs();
    // Soft periodic sync only corrects large drift; jumps always sync.
    final threshold =
        soft ? const Duration(milliseconds: 2000) : const Duration(milliseconds: 350);
    if (!jumped && drift <= threshold) {
      _syncPlayPause();
      return;
    }
    _seeking = true;
    unawaited(() async {
      try {
        await c.seekTo(audioPos);
        _syncPlayPause();
      } finally {
        _seeking = false;
      }
    }());
  }

  Future<void> _openFullscreen() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _FullscreenVideoPage(
          song: widget.song,
          controller: c,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (mounted) _correctDrift(soft: false);
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.maxHeight ?? (widget.width * 9 / 16);
    final ready = _controller != null && _controller!.value.isInitialized;

    // No ClipRRect — clipping a live texture forces an expensive save layer.
    return SizedBox(
      width: widget.width,
      height: height,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio == 0
                      ? 16 / 9
                      : _controller!.value.aspectRatio,
                  child: RepaintBoundary(
                    child: VideoPlayer(_controller!),
                  ),
                ),
              ),
            if (_loading)
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (_failed && !_loading)
              Center(
                child: Text(
                  'videoUnavailable'.tr,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            if (widget.showControls && !_loading)
              Positioned(
                left: 8,
                top: 8,
                child: _VideoBadge(failed: _failed),
              ),
            if (widget.showControls && !_loading)
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
        ),
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
  const _FullscreenVideoPage({
    required this.song,
    required this.controller,
  });

  final MediaItem song;
  final VideoPlayerController controller;

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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: widget.controller.value.aspectRatio == 0
                    ? 16 / 9
                    : widget.controller.value.aspectRatio,
                child: VideoPlayer(widget.controller),
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
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: cur,
                        max: total,
                        onChanged: (v) {
                          player.seek(Duration(milliseconds: v.round()));
                          widget.controller
                              .seekTo(Duration(milliseconds: v.round()));
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
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
