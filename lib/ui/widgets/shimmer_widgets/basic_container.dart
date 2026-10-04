import 'package:flutter/material.dart';

import '/ui/theme/riff_tokens.dart';

/// Loading-skeleton pulse (§5.13): fades its child between 50% and 100%
/// opacity, one cycle per [RiffDurations.skeletonPulse]. Holds still at full
/// opacity when the platform asks for reduced motion.
class RiffSkeletonPulse extends StatefulWidget {
  const RiffSkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<RiffSkeletonPulse> createState() => _RiffSkeletonPulseState();
}

class _RiffSkeletonPulseState extends State<RiffSkeletonPulse>
    with SingleTickerProviderStateMixin {
  static const double _low = 0.5;
  static const double _high = 1.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Half the cycle up, half back down.
    duration: RiffDurations.skeletonPulse ~/ 2,
    value: _high,
  );

  late final Animation<double> _opacity = Tween<double>(begin: _low, end: _high)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller
        ..stop()
        ..value = _high;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}

/// One skeleton box in `surfaceContainerLow` (surface1). Pulses only inside a
/// [RiffSkeletonPulse].
class BasicShimmerContainer extends StatelessWidget {
  const BasicShimmerContainer(this.size,
      {super.key, this.radius = RiffRadii.sm});
  final Size size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: Theme.of(context).colorScheme.surfaceContainerLow),
      height: size.height,
      width: size.width,
    );
  }
}
