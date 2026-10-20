import 'package:flutter/widgets.dart';

import '/ui/theme/riff_tokens.dart';

/// Grows open and fades in when [child] arrives (non-null), and folds shut
/// fading out when it goes (null), keeping its last child while it folds:
/// a row that comes and goes with a setting, or the hidden part of a list,
/// instead of popping in and out. At rest it takes [child]'s size, or none.
class RiffReveal extends StatefulWidget {
  const RiffReveal({super.key, this.child});

  /// What shows; null folds it away.
  final Widget? child;

  @override
  State<RiffReveal> createState() => _RiffRevealState();
}

class _RiffRevealState extends State<RiffReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;

  /// The child shown, kept while it folds away.
  Widget? _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.child;
    _controller = AnimationController(
      vsync: this,
      duration: RiffDurations.select,
      value: _shown == null ? 0 : 1,
    )..addStatusListener(_onStatus);
    _curve =
        CurvedAnimation(parent: _controller, curve: RiffDurations.selectCurve);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() => _shown = null);
    }
  }

  @override
  void didUpdateWidget(covariant RiffReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    final child = widget.child;
    if (child != null) {
      _shown = child;
      _controller.forward();
    } else if (oldWidget.child != null) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    return SizeTransition(
      sizeFactor: _curve,
      axisAlignment: -1,
      child: FadeTransition(opacity: _curve, child: shown),
    );
  }
}

/// Crossfades whole panes that fill their space (one mode's list giving
/// way to another's) as [child]'s key changes. Each pane gets the full
/// space, as it would without the switcher, so nothing moves at rest; the
/// one leaving takes no taps. Needs bounded constraints (an Expanded, a
/// page body).
///
/// Both panes are built while they crossfade: for two panes sharing a
/// ScrollController or a GlobalKey, use a keyed RiffFadeIn instead.
class RiffPaneSwitcher extends StatelessWidget {
  const RiffPaneSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: RiffDurations.content,
      switchInCurve: RiffDurations.enterCurve,
      switchOutCurve: RiffDurations.exitCurve,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [
          // As RiffSwitcher: one pane on its way out takes no taps (and,
          // the same widget type for every entry, keeps its state).
          for (final child in previous)
            IgnorePointer(key: child.key, child: child),
          if (current != null)
            IgnorePointer(key: current.key, ignoring: false, child: current),
        ],
      ),
      child: child,
    );
  }
}
