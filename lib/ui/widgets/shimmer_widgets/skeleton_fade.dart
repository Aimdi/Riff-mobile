import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/riff_motion.dart';

/// [skeleton] until [child] is ready (non-null), then [child] fading in
/// where the skeleton was, so loaded content doesn't cut in. A [child]
/// that's ready from the start (nothing to load) just shows.
class SkeletonFadeIn extends StatefulWidget {
  const SkeletonFadeIn({super.key, required this.skeleton, this.child});

  final Widget skeleton;

  /// The loaded content; null while it loads.
  final Widget? child;

  @override
  State<SkeletonFadeIn> createState() => _SkeletonFadeInState();
}

class _SkeletonFadeInState extends State<SkeletonFadeIn> {
  /// Whether the skeleton has shown, so the content fades in after it.
  /// Set at mount (a lazy initializer would first run once content is
  /// there, and never fade it).
  bool _fade = false;

  @override
  void initState() {
    super.initState();
    _fade = widget.child == null;
  }

  @override
  void didUpdateWidget(covariant SkeletonFadeIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child == null) _fade = true;
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (child == null) return widget.skeleton;
    return _fade ? RiffFadeIn(child: child) : child;
  }
}

/// For a lazily built list whose rows take its loading skeleton's place:
/// the rows built as it loads fade in together, rows scrolled into view
/// later just appear. Keep one per list (in a State or the screen's
/// controller) and call [skeleton] whenever the skeleton is built.
class LoadedRowsFade {
  bool _armed = false;
  Duration? _since;

  /// The skeleton is showing: the rows that replace it fade in.
  void skeleton() {
    _armed = true;
    _since = null;
  }

  /// [row], fading in (with [key]) when it's one of the rows replacing the
  /// skeleton. Every row gets the same wrapper, so the list's elements keep
  /// their shape whether or not they faded.
  Widget row(Widget row, {Key? key}) =>
      RiffFadeIn(key: key, duration: _duration(), child: row);

  Duration _duration() {
    if (!_armed) return Duration.zero;
    final binding = SchedulerBinding.instance;
    // Rows are built during a frame; outside one, count it as the first.
    if (binding.schedulerPhase == SchedulerPhase.idle) {
      return RiffDurations.content;
    }
    final now = binding.currentFrameTimeStamp;
    final since = _since ??= now;
    if (now - since < RiffDurations.content) return RiffDurations.content;
    _armed = false;
    return Duration.zero;
  }
}
