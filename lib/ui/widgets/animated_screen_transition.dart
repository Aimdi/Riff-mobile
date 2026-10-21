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
/// no slide (the same widgets, so turning it on keeps the page as it is).
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

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final distance =
        reduceMotion(context) ? 0.0 : RiffMotionDistances.sharedAxis;
    final fill = Theme.of(context).scaffoldBackgroundColor;
    return PageTransitionSwitcher(
      duration: RiffDurations.page,
      reverse: !forward,
      transitionBuilder: (child, primary, secondary) => _SharedAxisFade(
        primary: primary,
        secondary: secondary,
        horizontal: horizontalTransition,
        distance: distance,
        fill: fill,
        child: child,
      ),
      child: child,
    );
  }
}

/// One page of the swap. Entering ([primary] 0 → 1): fades in after the
/// first 30 % while sliding in from [distance] away. Leaving ([secondary]
/// 0 → 1): fades out over the first 30 % while sliding on. Run backwards
/// for a move the other way. A page on its way out takes no taps, even
/// faded out (it was left on top when moving back).
class _SharedAxisFade extends StatelessWidget {
  const _SharedAxisFade({
    required this.primary,
    required this.secondary,
    required this.horizontal,
    required this.distance,
    required this.fill,
    required this.child,
  });

  final Animation<double> primary;
  final Animation<double> secondary;
  final bool horizontal;
  final double distance;
  final Color fill;
  final Widget child;

  // Material's fade-through split: out over the first 30 %, in after.
  static const _fadeIn = Interval(0.3, 1, curve: RiffDurations.enterCurve);
  static const _fadeOut = Interval(0, 0.3, curve: RiffDurations.exitCurve);
  static const _slide = RiffDurations.enterCurve;

  bool get _leaving =>
      primary.status == AnimationStatus.reverse ||
      secondary.status == AnimationStatus.forward ||
      secondary.status == AnimationStatus.completed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([primary, secondary]),
      builder: (context, page) {
        final shift = distance * (1 - _slide.transform(primary.value)) -
            distance * _slide.transform(secondary.value);
        final opacity = _fadeIn.transform(primary.value) *
            (1 - _fadeOut.transform(secondary.value));
        return IgnorePointer(
          ignoring: _leaving,
          child: Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: horizontal ? Offset(shift, 0) : Offset(0, shift),
              child: page,
            ),
          ),
        );
      },
      child: ColoredBox(color: fill, child: child),
    );
  }
}
