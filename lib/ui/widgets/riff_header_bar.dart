import 'package:flutter/material.dart';

import '/ui/theme/riff_tokens.dart';

/// Page-header chrome (§ Phase 3): black background, 22 dp header icons in
/// the primary text colour, and a one-physical-pixel hairline along the
/// bottom that fades in (200 ms) only while content is scrolled under it.
///
/// It adds no layout: [child] keeps its size and place, the hairline is
/// painted over its bottom edge. A header that itself scrolls with the
/// content (it sits inside a scroll view) never shows the hairline, since
/// nothing can pass under it.
class RiffHeaderBar extends StatefulWidget {
  const RiffHeaderBar(
      {super.key, required this.child, this.bleed = 0, this.hairline = true});

  final Widget child;

  /// False when more pinned chrome (tabs, a sort row) sits between this
  /// header and the content; [RiffScrollUnder] then draws the hairline
  /// above the content instead.
  final bool hairline;

  /// Extends the hairline this far past [child]'s left and right edges,
  /// for a header that sits inside a page's side padding.
  final double bleed;

  @override
  State<RiffHeaderBar> createState() => _RiffHeaderBarState();
}

class _RiffHeaderBarState extends State<RiffHeaderBar> {
  ScrollNotificationObserverState? _observer;
  bool _scrolledUnder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_onScroll);
    // Pinned headers only: inside a scroll view the header moves with the
    // content.
    _observer = widget.hairline && Scrollable.maybeOf(context) == null
        ? ScrollNotificationObserver.maybeOf(context)
        : null;
    _observer?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll(ScrollNotification n) {
    final under = _scrolledUnderBy(n);
    if (under != null && under != _scrolledUnder && mounted) {
      setState(() => _scrolledUnder = under);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Stack(
        // Same constraints as without the hairline.
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          IconTheme.merge(
            data: IconThemeData(
              color: theme.colorScheme.onSurface,
              size: RiffComponentSizes.headerIcon,
            ),
            child: widget.child,
          ),
          if (widget.hairline)
            Positioned(
              left: -widget.bleed,
              right: -widget.bleed,
              bottom: 0,
              child: _Hairline(visible: _scrolledUnder),
            ),
        ],
      ),
    );
  }
}

/// [RiffHeaderBar] around an [AppBar], keeping its preferred size.
class RiffAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RiffAppBar(this.appBar, {super.key});

  final AppBar appBar;

  @override
  Size get preferredSize => appBar.preferredSize;

  @override
  Widget build(BuildContext context) => RiffHeaderBar(child: appBar);
}

/// Content below a pinned header block (title, tabs, sort row): draws the
/// header hairline along its own top edge while its vertical content is
/// scrolled. Adds no layout.
class RiffScrollUnder extends StatefulWidget {
  const RiffScrollUnder({super.key, required this.child, this.bleed = 0});

  final Widget child;

  /// Extends the hairline past the left and right edges (page padding).
  final double bleed;

  @override
  State<RiffScrollUnder> createState() => _RiffScrollUnderState();
}

class _RiffScrollUnderState extends State<RiffScrollUnder> {
  bool _scrolledUnder = false;

  bool _onScroll(ScrollNotification n) {
    final under = _scrolledUnderBy(n);
    if (under != null && under != _scrolledUnder) {
      setState(() => _scrolledUnder = under);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      // Same constraints as without the hairline.
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
        Positioned(
          left: -widget.bleed,
          right: -widget.bleed,
          top: 0,
          child: _Hairline(visible: _scrolledUnder),
        ),
      ],
    );
  }
}

/// Whether [n] says the page content is scrolled (null: not page content).
/// Horizontal shelves and pagers don't count.
bool? _scrolledUnderBy(ScrollNotification n) {
  if (n is! ScrollUpdateNotification && n is! ScrollEndNotification) {
    return null;
  }
  if (axisDirectionToAxis(n.metrics.axisDirection) != Axis.vertical) {
    return null;
  }
  return n.metrics.extentBefore > 0;
}

class _Hairline extends StatelessWidget {
  const _Hairline({required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: RiffDurations.headerHairline,
        child: const Divider(height: 0),
      ),
    );
  }
}
