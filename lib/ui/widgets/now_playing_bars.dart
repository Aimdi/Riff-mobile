import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/player/player_controller.dart';
import '/ui/theme/riff_tokens.dart';

/// The playing row's mark, as in Spotify, Apple Music and YouTube Music:
/// three accent bars that bounce while it plays and stand still while it's
/// paused (or with reduced motion). Read as "Now playing" by screen readers.
class NowPlayingBars extends StatefulWidget {
  const NowPlayingBars(
      {super.key, this.size = RiffComponentSizes.trailingIcon, this.color});

  final double size;

  /// Defaults to the accent (progress, §2.5).
  final Color? color;

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars>
    with TickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: RiffDurations.nowPlayingBars);

  /// 0 while the bars bounce, 1 standing still: a pause eases them down to
  /// rest (and playing again lifts them back into the bounce) instead of
  /// snapping.
  late final AnimationController _rest = AnimationController(
      vsync: this, duration: RiffDurations.select, value: 1);
  late final Listenable _frame = Listenable.merge([_loop, _rest]);
  Worker? _playing;
  bool _reducedMotion = false;
  bool _synced = false;

  PlayerController? get _player => Get.isRegistered<PlayerController>()
      ? Get.find<PlayerController>()
      : null;

  @override
  void initState() {
    super.initState();
    final player = _player;
    if (player != null) {
      _playing = ever<PlayButtonState>(player.buttonState, (_) => _sync());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  void _sync() {
    final playing = _player?.buttonState.value == PlayButtonState.playing;
    final moving = playing && !_reducedMotion;
    if (moving) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
    }
    final rest = moving ? 0.0 : 1.0;
    if (!_synced || _reducedMotion) {
      // As they first show, or with Remove animations on: straight there.
      _rest.value = rest;
    } else if (_rest.value != rest) {
      _rest.animateTo(rest, curve: RiffDurations.selectCurve);
    }
    _synced = true;
  }

  @override
  void dispose() {
    _playing?.dispose();
    _loop.dispose();
    _rest.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.secondary;
    return Semantics(
      label: 'nowPlaying'.tr,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _frame,
            builder: (context, _) => CustomPaint(
              painter: NowPlayingBarsPainter(
                t: _loop.value,
                rest: _rest.value,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three bottom-aligned, round-capped bars. Moving, each rises and falls at
/// its own pace ([t] runs 0 → 1 over a loop); still, they keep the
/// equalizer icon's stepped shape. [rest] blends from the first (0) to the
/// second (1), so they settle rather than snap.
class NowPlayingBarsPainter extends CustomPainter {
  NowPlayingBarsPainter(
      {required this.t, required this.rest, required this.color});

  final double t;
  final double rest;
  final Color color;

  /// Bar width and gap as shares of the icon box, like Material's icons.
  static const _barShare = 0.2;
  static const _gapShare = 0.12;

  /// Heights at rest, and the lowest a moving bar drops to.
  static const _restHeights = [0.45, 0.85, 0.6];
  static const _minHeight = 0.2;

  /// Whole bounces per loop for each bar (integers, so the loop is seamless)
  /// and where in its bounce each starts.
  static const _bounces = [2, 3, 2];
  static const _phases = [0.0, 0.35, 0.7];

  /// Height (share of the box) of bar [i].
  static double heightOf(int i, double t, {required bool moving}) {
    if (!moving) return _restHeights[i];
    final wave = math.sin(math.pi * (t * _bounces[i] + _phases[i])).abs();
    return _minHeight + (1 - _minHeight) * wave;
  }

  /// Height of bar [i] on its way between bouncing ([rest] 0) and standing
  /// still (1).
  static double settlingHeightOf(int i, double t, double rest) {
    if (rest >= 1) return _restHeights[i];
    if (rest <= 0) return heightOf(i, t, moving: true);
    return lerpDouble(heightOf(i, t, moving: true), _restHeights[i], rest)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final bar = size.width * _barShare;
    final gap = size.width * _gapShare;
    final left = (size.width - (bar * 3 + gap * 2)) / 2;
    for (var i = 0; i < 3; i++) {
      final h = size.height * settlingHeightOf(i, t, rest);
      final x = left + i * (bar + gap);
      canvas.drawRRect(
        RRect.fromLTRBR(
            x, size.height - h, x + bar, size.height, Radius.circular(bar / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(NowPlayingBarsPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.rest != rest ||
      oldDelegate.color != color;
}
