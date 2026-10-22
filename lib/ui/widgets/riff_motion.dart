import 'package:flutter/gestures.dart';
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
/// with a slight overshoot (a like, a download done). A child on its way
/// out no longer takes taps. [fit]: how the children are sized against
/// each other (passthrough keeps a tight size, e.g. a stretched button).
class RiffSwitcher extends StatelessWidget {
  const RiffSwitcher({
    super.key,
    required this.child,
    this.duration = RiffDurations.select,
    this.pop = false,
    this.alignment = Alignment.center,
    this.fit = StackFit.loose,
  });

  final Widget child;
  final Duration duration;
  final bool pop;
  final AlignmentGeometry alignment;
  final StackFit fit;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: RiffDurations.enterCurve,
      switchOutCurve: RiffDurations.exitCurve,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        fit: fit,
        children: [
          // Same widget type for every entry, so one leaving keeps its
          // state; it just stops taking taps.
          for (final child in previous)
            IgnorePointer(key: child.key, child: child),
          if (current != null)
            IgnorePointer(key: current.key, ignoring: false, child: current),
        ],
      ),
      // Top-level functions: the same builder every build, so entries
      // aren't wrapped again each time the switcher rebuilds.
      transitionBuilder:
          pop && !reduceMotion(context) ? _popTransition : _fadeTransition,
      child: child,
    );
  }
}

Widget _fadeTransition(Widget child, Animation<double> animation) =>
    FadeTransition(opacity: animation, child: child);

Widget _popTransition(Widget child, Animation<double> animation) =>
    ScaleTransition(
      // drive() listens to the animation only while the transition does
      // (a CurvedAnimation would hold a listener for good).
      scale: animation
          .drive(CurveTween(curve: RiffDurations.popCurve))
          .drive(Tween<double>(begin: RiffMotionDistances.popFromScale, end: 1)),
      child: FadeTransition(opacity: animation, child: child),
    );

/// Shrinks [child] a touch while a finger rests on it, the way cards do
/// in Spotify and Apple Music, and lets it spring back when the finger
/// lifts, slides away to scroll or holds for a long press. It only
/// watches: the child's own InkWell still gets the tap.
class RiffPressScale extends StatefulWidget {
  const RiffPressScale({super.key, required this.child});

  final Widget child;

  @override
  State<RiffPressScale> createState() => _RiffPressScaleState();
}

class _RiffPressScaleState extends State<RiffPressScale> {
  bool _down = false;

  void _set(bool down) {
    if (mounted && _down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _down && !reduceMotion(context);
    // A tap recogniser that never wins against the child's: it hears the
    // press once it's held past the tap slop window (a scroll takes the
    // gesture first) and is told when the child's tap or a drag wins.
    return RawGestureDetector(
      gestures: {
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          TapGestureRecognizer.new,
          (r) => r
            ..onTapDown = ((_) => _set(true))
            ..onTapUp = ((_) => _set(false))
            ..onTapCancel = (() => _set(false)),
        ),
      },
      child: AnimatedScale(
        scale: pressed ? RiffMotionDistances.pressScale : 1,
        duration: pressed ? RiffDurations.press : RiffDurations.select,
        curve: RiffDurations.selectCurve,
        child: widget.child,
      ),
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
