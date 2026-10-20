import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '/ui/theme/riff_tokens.dart';
import 'riff_motion.dart';

/// Swaps whole pages in place as [child]'s key changes (the rail's tabs,
/// the search result filters) with Material's shared-axis fade-through:
/// the old page fades out, then the new one fades in, sliding
/// [RiffMotionDistances.sharedAxis] along the axis the tabs are laid out
/// on, the way the rail or the chip row moved.
///
/// [enabled] false (the in-app "disable transition animation" setting):
/// the new page shows at once. Remove animations: a plain fade-through,
/// no slide.
class AnimatedScreenTransition extends StatelessWidget {
  const AnimatedScreenTransition(
      {super.key,
      this.enabled = true,
      this.forward = true,
      this.horizontalTransition = false,
      required this.child});
  final bool enabled;

  /// The new page comes after the old one (lower on the rail, further
  /// along the chips): it comes in from below (the right); otherwise from
  /// above (the left).
  final bool forward;
  final Widget child;
  final bool horizontalTransition;

  // Remove animations: the old page fades out (over the first 30 %), then
  // the new one fades in, as the shared axis does but without moving.
  static final Animatable<double> _fadeIn =
      CurveTween(curve: const Interval(0.3, 1));
  static final Animatable<double> _fadeOut =
      CurveTween(curve: const Interval(0.7, 1));

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final slide = !reduceMotion(context);
    final fill = Theme.of(context).scaffoldBackgroundColor;
    return PageTransitionSwitcher(
      duration: RiffDurations.page,
      reverse: !forward,
      transitionBuilder: (child, primary, secondary) => slide
          ? SharedAxisTransition(
              animation: primary,
              secondaryAnimation: secondary,
              transitionType: horizontalTransition
                  ? SharedAxisTransitionType.horizontal
                  : SharedAxisTransitionType.vertical,
              fillColor: fill,
              child: child,
            )
          : FadeTransition(
              opacity: primary.drive(_fadeIn),
              child: FadeTransition(
                opacity: ReverseAnimation(secondary).drive(_fadeOut),
                child: child,
              ),
            ),
      child: child,
    );
  }
}
