import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

/// A draggable thumb along the right edge of a long list, as Spotify's
/// long lists and the phone's own music players have: it shows while the
/// list scrolls, and dragging it moves through the whole list at once.
/// While it's dragged, a bubble names where it is ([labelFor]: the first
/// letter of the title or the artist when the list is sorted by it).
///
/// Builds the list itself through [builder] with the controller to use
/// ([controller], or one of its own). Lists shorter than
/// [RiffFastScroll.minScreens] screens get no thumb.
class RiffFastScroller extends StatefulWidget {
  const RiffFastScroller({
    super.key,
    required this.builder,
    required this.itemExtent,
    this.controller,
    this.labelFor,
  });

  final Widget Function(BuildContext context, ScrollController controller)
      builder;

  /// Every row's height (the list has fixed-extent rows).
  final double itemExtent;
  final ScrollController? controller;

  /// What the bubble says for the row at an index, or null for no bubble.
  final String? Function(int index)? labelFor;

  @override
  State<RiffFastScroller> createState() => _RiffFastScrollerState();
}

class _RiffFastScrollerState extends State<RiffFastScroller> {
  ScrollController? _own;
  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());

  bool _shown = false;
  bool _dragging = false;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    _own?.dispose();
    super.dispose();
  }

  /// Long enough to need it: more than a few screens to scroll.
  bool _long(ScrollMetrics m) =>
      m.maxScrollExtent > m.viewportDimension * RiffFastScroll.minScreens;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || !_long(n.metrics)) return false;
    if (n is ScrollUpdateNotification || n is ScrollStartNotification) {
      _show();
    }
    return false;
  }

  void _show() {
    _hide?.cancel();
    if (!_shown) setState(() => _shown = true);
    if (!_dragging) {
      _hide = Timer(RiffFastScroll.linger, () {
        if (mounted && !_dragging) setState(() => _shown = false);
      });
    }
  }

  void _jumpTo(double dy, double track) {
    final position = _controller.position;
    const thumb = RiffFastScroll.thumbHeight;
    final room = track - thumb;
    if (room <= 0) return;
    final fraction = ((dy - thumb / 2) / room).clamp(0.0, 1.0);
    position.jumpTo(fraction * position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.builder(context, _controller),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: RiffFastScroll.touchWidth,
            child: LayoutBuilder(builder: (context, box) {
              final track = box.maxHeight;
              return IgnorePointer(
                ignoring: !_shown,
                child: AnimatedOpacity(
                  opacity: _shown ? 1 : 0,
                  duration: RiffDurations.select,
                  curve: RiffDurations.selectCurve,
                  // TalkBack scrolls the list itself; the thumb is for
                  // fingers only.
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragStart: (d) {
                        _hide?.cancel();
                        setState(() => _dragging = true);
                        _jumpTo(d.localPosition.dy, track);
                      },
                      onVerticalDragUpdate: (d) =>
                          _jumpTo(d.localPosition.dy, track),
                      onVerticalDragEnd: (_) {
                        setState(() => _dragging = false);
                        _show();
                      },
                      onVerticalDragCancel: () {
                        setState(() => _dragging = false);
                        _show();
                      },
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) => _thumb(context, track, scheme),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _thumb(BuildContext context, double track, ColorScheme scheme) {
    if (!_controller.hasClients) return const SizedBox.shrink();
    final position = _controller.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
      return const SizedBox.shrink();
    }
    const thumb = RiffFastScroll.thumbHeight;
    final fraction =
        (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);
    final top = fraction * (track - thumb);
    final index = (position.pixels / widget.itemExtent).floor();
    final label = _dragging ? widget.labelFor?.call(index) : null;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: top,
          right: RiffSpacing.xs,
          child: Container(
            key: const ValueKey('fastScrollThumb'),
            width: RiffFastScroll.thumbWidth,
            height: thumb,
            decoration: BoxDecoration(
              color: _dragging ? scheme.onSurface : scheme.onSurfaceVariant,
              borderRadius: BorderRadius.circular(RiffRadii.pill),
            ),
          ),
        ),
        if (label != null && label.isNotEmpty)
          Positioned(
            top: top + thumb / 2 - RiffFastScroll.bubble / 2,
            right: RiffFastScroll.touchWidth,
            child: _Bubble(label: label),
          ),
      ],
    );
  }
}

/// The letter beside the thumb while it's dragged.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: RiffFastScroll.bubble,
      height: RiffFastScroll.bubble,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: BoxShape.circle,
      ),
      child: Text(label,
          style: theme.textTheme.headlineSmall
              ?.copyWith(color: theme.colorScheme.onSurface)),
    );
  }
}

/// The bubble's label for each row of [songs], when they're in order of
/// title (its first letter) or of artist (the artist's first letter);
/// null when they're in neither (by date, length or the playlist's own
/// order), so the thumb shows without a bubble.
String? Function(int index)? songFastScrollLabels(List<MediaItem> songs) {
  String initial(String s) {
    final t = s.trim();
    if (t.isEmpty) return '#';
    final c = t.characters.first.toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(c) || c.toLowerCase() != c ? c : '#';
  }

  bool ordered(String Function(MediaItem) key) {
    if (songs.length < 2) return false;
    var up = true;
    var down = true;
    for (var i = 1; i < songs.length; i++) {
      final c = key(songs[i - 1])
          .toLowerCase()
          .compareTo(key(songs[i]).toLowerCase());
      if (c > 0) up = false;
      if (c < 0) down = false;
      if (!up && !down) return false;
    }
    return true;
  }

  if (ordered((s) => s.title)) {
    return (i) => i < 0 || i >= songs.length ? null : initial(songs[i].title);
  }
  if (ordered((s) => s.artist ?? '')) {
    return (i) =>
        i < 0 || i >= songs.length ? null : initial(songs[i].artist ?? '');
  }
  return null;
}
