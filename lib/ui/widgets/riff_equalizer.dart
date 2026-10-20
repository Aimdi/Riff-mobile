import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '/ui/theme/riff_tokens.dart';

/// Small bar equalizer. Moves while [animate] is true, rests as a static
/// waveform otherwise (no ticking on an idle Home), and with the phone's
/// Remove animations on (accessibility).
class RiffEqualizer extends StatefulWidget {
  const RiffEqualizer({
    super.key,
    required this.animate,
    this.color = RiffPalette.onImage,
    this.size = 24,
    this.bars = 4,
  });

  final bool animate;
  final Color color;
  final double size;
  final int bars;

  @override
  State<RiffEqualizer> createState() => _RiffEqualizerState();
}

class _RiffEqualizerState extends State<RiffEqualizer>
    with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: RiffDurations.equalizerLoop);

  /// 0 while the bars move, 1 standing still: stopping eases them down to
  /// the resting waveform (and starting lifts them back) instead of
  /// snapping.
  late final AnimationController _rest = AnimationController(
      vsync: this, duration: RiffDurations.select, value: 1);
  late final Listenable _frame = Listenable.merge([_c, _rest]);

  bool _reducedMotion = false;
  bool _synced = false;

  bool get _moving => widget.animate && !_reducedMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant RiffEqualizer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_moving && !_c.isAnimating) {
      _c.repeat();
    } else if (!_moving && _c.isAnimating) {
      _c.stop();
    }
    final rest = _moving ? 0.0 : 1.0;
    if (!_synced || _reducedMotion) {
      // As it first shows, or with Remove animations on: straight there.
      _rest.value = rest;
    } else if (_rest.value != rest) {
      _rest.animateTo(rest, curve: RiffDurations.selectCurve);
    }
    _synced = true;
  }

  @override
  void dispose() {
    _c.dispose();
    _rest.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _frame,
          builder: (context, _) => CustomPaint(
            painter: _BarsPainter(
              t: _c.value,
              rest: _rest.value,
              color: widget.color,
              bars: widget.bars,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(
      {required this.t,
      required this.rest,
      required this.color,
      required this.bars});
  final double t;

  /// 0 moving, 1 at rest; between, the bars settle from one to the other.
  final double rest;
  final Color color;
  final int bars;

  static const _rest = [0.45, 0.85, 0.6, 0.95, 0.5, 0.75];

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width / (bars * 3 - 1);
    final w = gap * 2;
    final paint = Paint()..color = color;
    for (var i = 0; i < bars; i++) {
      final still = _rest[i % _rest.length];
      final h = rest >= 1
          ? still
          : lerpDouble(
              0.3 +
                  0.7 *
                      (0.5 +
                          0.5 *
                              math.sin((t * 2 * math.pi * (1 + i * 0.37)) +
                                  i * 1.7)),
              still,
              rest)!;
      final barH = size.height * h;
      final x = i * (w + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - barH, w, barH),
          Radius.circular(w / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.t != t || old.rest != rest || old.color != color;
}
