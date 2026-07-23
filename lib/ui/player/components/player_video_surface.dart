import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '/services/video_stream_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/image_widget.dart';
import '/utils/media_item_video.dart';

/// Spotify-style in-player video pane for YouTube *videos* only.
///
/// Audio stays on just_audio (source of truth). Video is muted and seek-synced
/// so lips stay roughly aligned without fighting the audio pipeline.
class PlayerVideoSurface extends StatefulWidget {
  const PlayerVideoSurface({
    super.key,
    required this.song,
    required this.width,
    this.maxHeight,
    this.showControls = true,
  });

  final MediaItem song;
  final double width;
  final double? maxHeight;
  final bool showControls;

  @override
  State<PlayerVideoSurface> createState() => _PlayerVideoSurfaceState();
}

class _PlayerVideoSurfaceState extends State<PlayerVideoSurface> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;
  Worker? _playWorker;
  Worker? _songWorker;
  Timer? _syncTimer;
  Duration _lastAudioPos = Duration.zero;

  PlayerController get _player => Get.find<PlayerController>();

  @override
  void initState() {
    super.initState();
    _boot(widget.song);
    _playWorker = ever(_player.buttonState, (_) => _syncPlayPause());
    _songWorker = ever(_player.currentSong, (MediaItem? s) {
      if (s == null) return;
      if (s.id != widget.song.id) return;
    });
    _syncTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      _correctDrift();
    });
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
    _playWorker?.dispose();
    _songWorker?.dispose();
    _syncTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _boot(MediaItem song) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    await _controller?.dispose();
    _controller = null;

    if (!song.isYoutubeVideo) {
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
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(false);
      final pos = _player.progressBarStatus.value.current;
      if (pos > Duration.zero) {
        await c.seekTo(pos);
      }
      if (_player.buttonState.value == PlayButtonState.playing) {
        unawaited(c.play());
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

  void _syncPlayPause() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final playing = _player.buttonState.value == PlayButtonState.playing;
    if (playing && !c.value.isPlaying) {
      unawaited(c.play());
    } else if (!playing && c.value.isPlaying) {
      unawaited(c.pause());
    }
  }

  void _correctDrift() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final audioPos = _player.progressBarStatus.value.current;
    // Detect seeks (large jumps) and soft drift.
    final jumped = (audioPos - _lastAudioPos).abs() > const Duration(seconds: 2);
    _lastAudioPos = audioPos;
    final videoPos = c.value.position;
    final drift = (audioPos - videoPos).abs();
    if (jumped || drift > const Duration(milliseconds: 450)) {
      unawaited(c.seekTo(audioPos));
    }
    _syncPlayPause();
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
    if (mounted) _correctDrift();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.maxHeight ?? (widget.width * 9 / 16);
    final radius = BorderRadius.circular(10);

    return SizedBox(
      width: widget.width,
      height: height,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Soft art fallback while loading / if video fails.
            ColoredBox(
              color: Colors.black,
              child: Opacity(
                opacity: (_controller?.value.isInitialized ?? false) ? 0 : 1,
                child: ImageWidget(
                  size: height,
                  song: widget.song,
                  isPlayerArtImage: true,
                ),
              ),
            ),
            if (_controller != null && _controller!.value.isInitialized)
              FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
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
            if (widget.showControls && !_loading)
              Positioned(
                left: 10,
                top: 10,
                child: _VideoBadge(failed: _failed),
              ),
            if (widget.showControls &&
                !_loading &&
                !_failed &&
                _controller != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: Material(
                  color: Colors.black.withOpacity(0.45),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'videoFullscreen'.tr,
                    visualDensity: VisualDensity.compact,
                    onPressed: _openFullscreen,
                    icon: const Icon(Icons.fullscreen, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
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
