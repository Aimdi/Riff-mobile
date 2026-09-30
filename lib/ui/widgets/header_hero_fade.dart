import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Full-width header art for the playlist / album screens.
///
/// Replaces an `Opacity` + two huge blurred `BoxShadow`s (spread 200,
/// blur 100) that were re-rasterized with a save-layer on every scroll
/// frame. The edge fades are now cheap linear gradients that follow the same
/// Gaussian profile, and the scroll-driven opacity is applied through a
/// [FadeTransition] — which only updates the composited layer's alpha — over
/// a [RepaintBoundary], so scrolling never repaints the image.
class HeaderHeroFade extends StatelessWidget {
  const HeaderHeroFade({
    super.key,
    required this.opacity,
    required this.color,
    required this.leftShadowOffset,
    required this.bottomShadowOffset,
    required this.child,
  });

  /// 0–1 scroll-driven opacity.
  final double opacity;

  /// Fade colour (the screen background).
  final Color color;

  /// Horizontal offset of the (former) left shadow, e.g. `-size.height`.
  final double leftShadowOffset;

  /// Vertical offset of the (former) bottom shadow.
  final double bottomShadowOffset;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: AlwaysStoppedAnimation<double>(opacity.clamp(0.0, 1.0)),
      child: RepaintBoundary(
        child: CustomPaint(
          foregroundPainter: HeaderEdgeFadePainter(
            color: color,
            leftShadowOffset: leftShadowOffset,
            bottomShadowOffset: bottomShadowOffset,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Paints the equivalent of two `BoxShadow(spreadRadius: 200,
/// blurRadius: 100)` of [color] shifted by `(leftShadowOffset, 0)` and
/// `(0, bottomShadowOffset)` — only the edge facing the art matters, which
/// is a 1-D Gaussian ramp, approximated with a multi-stop linear gradient.
class HeaderEdgeFadePainter extends CustomPainter {
  HeaderEdgeFadePainter({
    required this.color,
    required this.leftShadowOffset,
    required this.bottomShadowOffset,
  });

  final Color color;
  final double leftShadowOffset;
  final double bottomShadowOffset;

  static const double spread = 200;
  static const double blurRadius = 100;

  /// Standard normal CDF sampled at -3σ … +3σ.
  static const List<double> _cdfAt = [-3, -2, -1, -0.5, 0, 0.5, 1, 2, 3];
  static const List<double> _cdf = [
    0.0013,
    0.0228,
    0.1587,
    0.3085,
    0.5,
    0.6915,
    0.8413,
    0.9772,
    0.9987
  ];

  List<Color> get _colors =>
      [for (final v in _cdf) color.withOpacity(color.opacity * v)];

  @override
  void paint(Canvas canvas, Size size) {
    final sigma = ui.Shadow.convertRadiusToSigma(blurRadius);
    final reach = 3 * sigma;
    final stops = [for (final t in _cdfAt) (t + 3) / 6];

    // Former left shadow: its right edge is the fade line.
    final left =
        (Offset.zero & size).shift(Offset(leftShadowOffset, 0)).inflate(spread);
    final lx = left.right;
    if (lx + reach > 0) {
      canvas.drawRect(
        Rect.fromLTRB(left.left, left.top, lx + reach, left.bottom),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(lx + reach, 0),
            Offset(lx - reach, 0),
            _colors,
            stops,
          ),
      );
    }

    // Former bottom shadow: its top edge is the fade line.
    final bottom = (Offset.zero & size)
        .shift(Offset(0, bottomShadowOffset))
        .inflate(spread);
    final by = bottom.top;
    canvas.drawRect(
      Rect.fromLTRB(bottom.left, by - reach, bottom.right, bottom.bottom),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, by - reach),
          Offset(0, by + reach),
          _colors,
          stops,
        ),
    );
  }

  @override
  bool shouldRepaint(covariant HeaderEdgeFadePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.leftShadowOffset != leftShadowOffset ||
      oldDelegate.bottomShadowOffset != bottomShadowOffset;
}
