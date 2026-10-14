import 'package:flutter/material.dart';
import 'package:widget_marquee/widget_marquee.dart';

/// A line too long for its row scrolls by, as titles do in Spotify's and
/// YouTube Music's players. With the phone's Remove animations on (an
/// Android accessibility setting) it holds still and ends in "…", as Apple
/// Music keeps still under Reduce Motion.
class RiffMarquee extends StatelessWidget {
  const RiffMarquee({
    super.key,
    required this.delay,
    required this.duration,
    this.id,
    required this.child,
  });

  /// Before it starts scrolling.
  final Duration delay;

  /// One pass.
  final Duration duration;

  /// Keeps it scrolling through rebuilds of the same line.
  final String? id;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return DefaultTextStyle.merge(
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        child: child,
      );
    }
    return Marquee(delay: delay, duration: duration, id: id, child: child);
  }
}
