import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '/services/video_stream_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/player/video_av_sync_policy.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/utils/media_item_video.dart';

/// Spotify-style in-player video pane for YouTube *videos* only.
///
/// Audio stays on just_audio (source of truth). Video is muted and kept in
/// sync with rate nudges for small drift and seeks for larger gaps / jumps.
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
  bool _rateNudging = false;
  PlayButtonState? _lastButtonState;
  Worker? _playWorker;
  Worker? _panelWorker;
  Worker? _seekWorker;
  Worker? _speedWorker;
  Worker? _qualityWorker;
  Timer? _syncTimer;
  Duration _lastAudioPos = Duration.zero;
  DateTime? _lastAudioSampleAt;
  static const _policy = VideoAvSyncPolicy();

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
    // Defer decoder boot until the full player is visible — mini-player
    // should not pay for muted video decode in the background.
    if (_panelOpen) {
      _boot(widget.song);
    } else {
      _loading = false;
    }
    _lastButtonState = _player.buttonState.value;
    _lastAudioPos = _player.progressBarStatus.value.current;
    _playWorker = ever(_player.buttonState, (state) {
      final wasPlaying = _lastButtonState == PlayButtonState.playing;
      final nowPlaying = state == PlayButtonState.playing;
      _lastButtonState = state;
      if (!wasPlaying && nowPlaying && _panelOpen) {
        // Resume often leaves video a frame or two off — realign first.
        _alignToAudio(softOnly: false);
      } else {
        _syncPlayPause();
      }
    });
    _panelWorker = ever(_player.isPlayerPanelOpen, (_) => _onPanelOpenChanged());
    _seekWorker = ever(_player.videoSeekSignal, (_) => _onExternalSeek());
    if (Get.isRegistered<SettingsScreenController>()) {
      final settings = Get.find<SettingsScreenController>();
      _speedWorker = ever(
        settings.playbackSpeed,
        (_) => _applySpeed(forceNominal: true),
      );
      _qualityWorker = ever(settings.videoQuality, (_) {
        if (mounted && _panelOpen) _boot(widget.song);
      });
    }
    // Frequent drift checks; policy decides nudge vs seek so we avoid hitchy
    // periodic seeks while still catching notification / OS seeks.
    _syncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_panelOpen) return;
      _alignToAudio(softOnly: true);
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
      if (_panelOpen) {
        _alignToAudio(softOnly: false);
      } else {
        _syncPlayPause();
      }
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
    _qualityWorker?.dispose();
    _syncTimer?.cancel();
    final c = _controller;
    _controller = null;
    unawaited(c?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  void _onPanelOpenChanged() {
    if (!_panelOpen) {
      // Release the decoder while the slide-up panel is collapsed so audio
      // keeps playing smoothly; recreate when the user opens the player again.
      unawaited(_releaseDecoder());
      return;
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      _boot(widget.song);
      return;
    }
    _alignToAudio(softOnly: false);
  }

  Future<void> _releaseDecoder() async {
    final c = _controller;
    _controller = null;
    if (c != null) {
      try {
        if (c.value.isInitialized && c.value.isPlaying) {
          await c.pause();
        }
      } catch (_) {}
      try {
        await c.dispose();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  void _onExternalSeek() {
    if (!_panelOpen) return;
    _alignToAudio(softOnly: false);
  }

  double get _basePlaybackSpeed {
    if (!Get.isRegistered<SettingsScreenController>()) return 1.0;
    return Get.find<SettingsScreenController>()
        .playbackSpeed
        .value
        .clamp(0.25, 2.0);
  }

  Future<void> _applySpeed({
    double speedFactor = 1.0,
    bool forceNominal = false,
  }) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final factor = forceNominal ? 1.0 : speedFactor;
    if (forceNominal) _rateNudging = false;
    try {
      await c.setPlaybackSpeed(
        _policy.effectiveSpeed(
          baseSpeed: _basePlaybackSpeed,
          speedFactor: factor,
        ),
      );
    } catch (_) {}
  }

  Future<void> _boot(MediaItem song) async {
    if (!_panelOpen) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = false;
        });
      }
      return;
    }
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
      final quality = Get.isRegistered<SettingsScreenController>()
          ? Get.find<SettingsScreenController>().videoQuality.value
          : VideoQuality.high;
      final info = await VideoStreamService.resolve(
        song.id,
        quality: quality,
      ).timeout(const Duration(seconds: 12));
      if (!mounted || widget.song.id != song.id || !_panelOpen) return;
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
      if (!mounted || widget.song.id != song.id || !_panelOpen) {
        await c.dispose();
        return;
      }
      await c.setVolume(0);
      await c.setLooping(false);
      try {
        await c.setPlaybackSpeed(_basePlaybackSpeed);
      } catch (_) {}
      final pos = _player.progressBarStatus.value.current;
      if (pos > Duration.zero) {
        await c.seekTo(pos);
        await _waitForVideoNear(c, pos);
      }
      // Only start decoding when the full player is visible.
      if (_panelOpen &&
          _player.buttonState.value == PlayButtonState.playing) {
        await c.play();
      } else {
        await c.pause();
      }
      if (!mounted || widget.song.id != song.id || !_panelOpen) {
        await c.dispose();
        return;
      }
      _lastAudioPos = _player.progressBarStatus.value.current;
      _rateNudging = false;
      setState(() {
        _controller = c;
        _loading = false;
        _failed = false;
      });
      // Boot latency can leave video a beat behind after play() starts.
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted && widget.song.id == song.id && _panelOpen) {
          _alignToAudio(softOnly: false);
        }
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

  void _alignToAudio({required bool softOnly}) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _seeking) return;
    if (!_panelOpen) return;

    final audioPos = _player.progressBarStatus.value.current;
    final now = DateTime.now();
    final elapsedMs = _lastAudioSampleAt == null
        ? 500
        : now.difference(_lastAudioSampleAt!).inMilliseconds.clamp(1, 5000);
    _lastAudioSampleAt = now;
    final mediaDeltaMs = (audioPos - _lastAudioPos).abs().inMilliseconds;
    // Natural advance ≈ wall time × speed; anything well beyond that is a seek
    // (notification scrub, skip, track restart) — including paths that never
    // bump videoSeekSignal.
    final naturalMaxMs =
        (elapsedMs * _basePlaybackSpeed * 1.4).round() + 300;
    final jumped = mediaDeltaMs > naturalMaxMs &&
        mediaDeltaMs > VideoAvSyncPolicy.audioJumpMs;
    _lastAudioPos = audioPos;

    final signedDriftMs =
        audioPos.inMilliseconds - c.value.position.inMilliseconds;
    final highQuality = Get.isRegistered<SettingsScreenController>() &&
        Get.find<SettingsScreenController>().videoQuality.value ==
            VideoQuality.high;

    final decision = _policy.decide(
      signedDriftMs: signedDriftMs,
      softOnly: softOnly,
      highQuality: highQuality,
      audioJumpDetected: jumped,
    );

    switch (decision.action) {
      case VideoSyncAction.none:
        if (_rateNudging) {
          unawaited(_applySpeed(forceNominal: true));
        }
        _syncPlayPause();
        return;
      case VideoSyncAction.rateNudge:
        _rateNudging = true;
        unawaited(_applySpeed(speedFactor: decision.speedFactor));
        _syncPlayPause();
        return;
      case VideoSyncAction.seek:
        unawaited(_seekVideoToAudio(c));
        return;
    }
  }

  Future<void> _seekVideoToAudio(VideoPlayerController c) async {
    if (_seeking) return;
    _seeking = true;
    try {
      var target = _player.progressBarStatus.value.current;
      await c.seekTo(target);
      await _waitForVideoNear(c, target);
      // Audio may have advanced while the decoder sought — one follow-up if needed.
      target = _player.progressBarStatus.value.current;
      final remain =
          (target.inMilliseconds - c.value.position.inMilliseconds).abs();
      if (remain > VideoAvSyncPolicy.hardSeekMs) {
        await c.seekTo(target);
        await _waitForVideoNear(c, target);
      }
      _lastAudioPos = _player.progressBarStatus.value.current;
      await _applySpeed(forceNominal: true);
      _syncPlayPause();
      // Brief cooldown so we don't seek-thrash if position reports lag.
      await Future<void>.delayed(const Duration(milliseconds: 180));
    } catch (_) {
      // Decoder may be disposing mid-seek.
    } finally {
      _seeking = false;
    }
  }

  Future<void> _waitForVideoNear(
    VideoPlayerController c,
    Duration target, {
    int maxAttempts = 8,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      if (!c.value.isInitialized) return;
      final delta =
          (c.value.position.inMilliseconds - target.inMilliseconds).abs();
      if (delta <= 200) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
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
    if (mounted) _alignToAudio(softOnly: false);
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
