import 'dart:math' as math;

import 'package:flutter/material.dart';

import '/ui/theme/riff_tokens.dart';

/// Small bar equalizer. Moves while [animate] is true, rests as a static
/// waveform otherwise (no ticking on an idle Home).
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant RiffEqualizer old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _BarsPainter(
              t: _c.value,
              moving: widget.animate,
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
      required this.moving,
      required this.color,
      required this.bars});
  final double t;
  final bool moving;
  final Color color;
  final int bars;

  static const _rest = [0.45, 0.85, 0.6, 0.95, 0.5, 0.75];

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width / (bars * 3 - 1);
    final w = gap * 2;
    final paint = Paint()..color = color;
    for (var i = 0; i < bars; i++) {
      final h = moving
          ? 0.3 +
              0.7 *
                  (0.5 +
                      0.5 *
                          math.sin(
                              (t * 2 * math.pi * (1 + i * 0.37)) + i * 1.7))
          : _rest[i % _rest.length];
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
      old.t != t || old.moving != moving || old.color != color;
}
