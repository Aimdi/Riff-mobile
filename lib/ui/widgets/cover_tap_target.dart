import 'package:flutter/material.dart';

import '/ui/theme/riff_spacing.dart';

/// A small button on a cover's corner (the play badge) that a finger
/// reaches across a [RiffSizes.touch] square: the badge keeps its size and
/// place, [inset] from the corner, and the square around it, over the
/// cover, takes the tap too. TalkBack reads the square as one button,
/// [label].
///
/// Place it with `Positioned(right: 0, bottom: 0)` in the cover's stack.
class CoverTapTarget extends StatelessWidget {
  const CoverTapTarget({
    super.key,
    required this.label,
    required this.onTap,
    required this.inset,
    required this.child,
  });

  final String label;
  final VoidCallback? onTap;

  /// The badge's distance from the cover's right and bottom edges.
  final double inset;

  /// The badge as it's drawn (its own ink included).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: RiffSizes.touch,
          child: Padding(
            padding: EdgeInsets.only(right: inset, bottom: inset),
            child: Align(alignment: Alignment.bottomRight, child: child),
          ),
        ),
      ),
    );
  }
}
