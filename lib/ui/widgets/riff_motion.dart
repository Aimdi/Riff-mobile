import 'package:flutter/material.dart';

import '/ui/theme/riff_tokens.dart';

/// Shared motion for Riff: one place for how things come and go, so a
/// like, a loaded page and a new cover all move alike.
///
/// Android's Remove animations (MediaQuery.disableAnimations) is followed
/// everywhere here: Flutter already shortens one-shot animations to 5 %,
/// and these drop the movement that would still show.

/// Whether the person asked for less motion (Android's Remove animations).
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Fades [child] in (rising [rise] dp into place) the first time it's
/// built: loaded content taking the place of its skeleton, so it doesn't
/// pop in. Later rebuilds don't fade it again; give it a new key to.
class RiffFadeIn extends StatefulWidget {
  const RiffFadeIn({
    super.key,
    required this.child,
    this.duration = RiffDurations.content,
    this.rise = RiffMotionDistances.contentRise,
  });

  final Widget child;
  final Duration duration;
  final double rise;

  @override
  State<RiffFadeIn> createState() => _RiffFadeInState();
}

class _RiffFadeInState extends State<RiffFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: RiffDurations.enterCurve);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rise = reduceMotion(context) ? 0.0 : widget.rise;
    // The same widgets throughout, so the child keeps its state when the
    // fade ends (once done it's a plain opaque layer, no offset).
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, rise * (1 - _curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Crossfades between children as their key changes, with Riff's timing:
/// a section's content giving way to another's, an icon to its next state.
/// [pop]: the new child also grows from [RiffMotionDistances.popFromScale]
/// with a slight overshoot (a like, a download done).
class RiffSwitcher extends StatelessWidget {
  const RiffSwitcher({
    super.key,
    required this.child,
    this.duration = RiffDurations.select,
    this.pop = false,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Duration duration;
  final bool pop;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final grow = pop && !reduceMotion(context);
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: RiffDurations.enterCurve,
      switchOutCurve: RiffDurations.exitCurve,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) {
        final faded = FadeTransition(opacity: animation, child: child);
        if (!grow) return faded;
        return ScaleTransition(
          scale: Tween<double>(begin: RiffMotionDistances.popFromScale, end: 1)
              .animate(CurvedAnimation(
                  parent: animation, curve: RiffDurations.popCurve)),
          child: faded,
        );
      },
      child: child,
    );
  }
}

/// An Image's frameBuilder that fades the picture in once its first frame
/// is ready (a file or network image that wasn't already in memory),
/// instead of it popping in.
Widget riffFadeInFrame(BuildContext context, Widget child, int? frame,
    bool wasSynchronouslyLoaded) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: RiffDurations.image,
    curve: RiffDurations.enterCurve,
    child: child,
  );
}
