import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

/// The full player's collapsed queue: a slim one-line tab standing on the
/// bottom edge, its top one shallow arc (the top slice of a circle), running
/// edge to edge across the screen. It runs down through the system inset;
/// its label stays above it. The whole tab opens the queue, so a tap never
/// reaches the hidden queue underneath.
class UpNextCard extends StatelessWidget {
  const UpNextCard({
    super.key,
    required this.preview,
    required this.bottomInset,
    required this.onTap,
  });

  /// Height of the strip above the system inset.
  static const double extent = RiffComponentSizes.queueCard;

  /// "First title · N more"; empty when nothing comes next.
  final String preview;
  final double bottomInset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: ArcTopBorder(
          arc: RiffComponentSizes.queueCardArc,
          side: BorderSide(color: theme.dividerColor, width: 0),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            height: RiffComponentSizes.queueCard + bottomInset,
            // The label sits a little lower than the band's middle,
            // where the arc has room for it.
            padding: EdgeInsets.only(
                left: RiffSpacing.lg,
                top: math.min(RiffComponentSizes.queueCardArc / 2, RiffSpacing.xs),
                right: RiffSpacing.lg,
                bottom: bottomInset),
            alignment: Alignment.center,
            // One line: an up-arrow (pull me up), then "Up Next ·
            // next song".
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.keyboard_arrow_up_rounded,
                    size: RiffComponentSizes.trailingIcon, color: muted),
                const SizedBox(width: RiffSpacing.xs),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: 'upNext'.tr,
                        style:
                            theme.textTheme.labelSmall?.copyWith(color: muted),
                      ),
                      if (preview.isNotEmpty) ...[
                        TextSpan(
                          text: ' · ',
                          style:
                              theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                        TextSpan(
                          text: preview,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurface),
                        ),
                      ],
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
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

/// A box whose top edge is one circular arc through the middle of the top
/// and the two sides [arc] below it, eased into the straight sides by
/// [corner]; the bottom is straight.
class ArcTopBorder extends OutlinedBorder {
  const ArcTopBorder(
      {super.side, required this.arc, this.corner = RiffRadii.lg});

  /// Drop from the middle of the top edge to its ends.
  final double arc;

  /// Rounding where the arc meets the straight sides.
  final double corner;

  Path _path(Rect rect) {
    final d = arc.clamp(0.0, rect.height).toDouble();
    final c = corner.clamp(0.0, rect.width / 2).toDouble();
    final half = rect.width / 2;
    final path = Path()..moveTo(rect.left, rect.bottom);
    if (d == 0) {
      return path
        ..lineTo(rect.left, rect.top + c)
        ..quadraticBezierTo(rect.left, rect.top, rect.left + c, rect.top)
        ..lineTo(rect.right - c, rect.top)
        ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + c)
        ..lineTo(rect.right, rect.bottom)
        ..close();
    }
    // The circle through both top ends and the apex.
    final r = (half * half + d * d) / (2 * d);
    final centerY = rect.top + r;
    double arcY(double x) {
      final dx = x - rect.center.dx;
      return centerY - math.sqrt(math.max(0, r * r - dx * dx));
    }

    final leftIn = Offset(rect.left + c, arcY(rect.left + c));
    final rightIn = Offset(rect.right - c, arcY(rect.right - c));
    return path
      ..lineTo(rect.left, rect.top + d + c)
      ..quadraticBezierTo(rect.left, rect.top + d, leftIn.dx, leftIn.dy)
      ..arcToPoint(rightIn, radius: Radius.circular(r))
      ..quadraticBezierTo(
          rect.right, rect.top + d, rect.right, rect.top + d + c)
      ..lineTo(rect.right, rect.bottom)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect), side.toPaint());
  }

  @override
  ArcTopBorder copyWith({BorderSide? side, double? arc, double? corner}) =>
      ArcTopBorder(
          side: side ?? this.side,
          arc: arc ?? this.arc,
          corner: corner ?? this.corner);

  @override
  ShapeBorder scale(double t) =>
      ArcTopBorder(side: side.scale(t), arc: arc * t, corner: corner * t);

  @override
  bool operator ==(Object other) =>
      other is ArcTopBorder &&
      other.side == side &&
      other.arc == arc &&
      other.corner == corner;

  @override
  int get hashCode => Object.hash(side, arc, corner);
}
