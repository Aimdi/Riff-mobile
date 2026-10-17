import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/ui/theme/riff_tokens.dart';

/// The mini player's track block that follows a horizontal drag, like the
/// Spotify / YouTube Music / Apple Music mini players: the playing track
/// slides with the finger while the next (drag left) or previous (drag
/// right) one slides in beside it. Past a third of the width, or on a
/// fling, it skips; otherwise it springs back. Where there is nothing to
/// skip to it gives a little and springs back.
class TrackSwipe extends StatefulWidget {
  const TrackSwipe({
    super.key,
    required this.currentKey,
    required this.current,
    required this.canNext,
    required this.canPrevious,
    required this.onNext,
    required this.onPrevious,
    this.peekNext,
    this.peekPrevious,
  });

  /// Identity of the playing track; when it changes after a skip, the
  /// block settles back onto the (now new) playing track.
  final String? currentKey;

  /// The playing track's block.
  final Widget current;

  /// What slides in from the right / left, when it's known (it isn't under
  /// shuffle, where the player picks the order as it goes).
  final Widget? peekNext;
  final Widget? peekPrevious;

  final bool canNext;
  final bool canPrevious;

  /// Start the skip; false when nothing started (the block springs back).
  final Future<bool> Function() onNext;
  final Future<bool> Function() onPrevious;

  /// Share of the width past which a released drag skips.
  static const double commitShare = 0.35;

  /// A fling at least this fast (logical px/s) skips from any distance.
  static const double flingVelocity = 700;

  /// How far a drag goes where there is nothing to skip to.
  static const double blockedGive = 0.12;

  static const Duration slideOut = Duration(milliseconds: 220);
  static const Duration springBack = Duration(milliseconds: 320);

  /// Longest the block waits on the new track before settling anyway.
  static const Duration settleTimeout = Duration(milliseconds: 2500);

  @override
  State<TrackSwipe> createState() => _TrackSwipeState();
}

class _TrackSwipeState extends State<TrackSwipe>
    with SingleTickerProviderStateMixin {
  // Horizontal offset of the playing track's block in logical pixels.
  late final AnimationController _dx = AnimationController.unbounded(
    vsync: this,
  );
  double _width = 1;

  /// Finger travel since the drag started (the offset itself is damped
  /// where there is nothing to skip to, so it can't be accumulated).
  double _drag = 0;

  /// Set while a committed skip waits for the new track: the direction
  /// (-1 next, 1 previous), the track it left and the peek it showed, held
  /// so a queue update mid-skip can't swap what's on screen.
  int _committed = 0;
  String? _leftKey;
  Widget? _heldPeek;
  Timer? _settle;

  @override
  void dispose() {
    _settle?.cancel();
    _dx.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TrackSwipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_committed != 0 && widget.currentKey != _leftKey) {
      // New track is playing: let its title cross-fade in off screen, then
      // put the block back in the middle — both show the same track then.
      _settle?.cancel();
      _settle = Timer(RiffDurations.select, _reset);
    }
  }

  void _reset() {
    if (!mounted) return;
    _settle?.cancel();
    setState(() {
      _committed = 0;
      _leftKey = null;
      _heldPeek = null;
    });
    _dx.value = 0;
  }

  bool get _busy => _committed != 0;

  void _onStart(DragStartDetails _) {
    if (_busy) return;
    _dx.stop();
    _drag = _dx.value;
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_busy) return;
    _drag += d.delta.dx;
    final allowed = _drag < 0 ? widget.canNext : widget.canPrevious;
    _dx.value = allowed
        ? _drag.clamp(-_width, _width)
        : blockedDragOffset(_drag, _width * TrackSwipe.blockedGive);
  }

  void _onEnd(DragEndDetails d) {
    if (_busy) return;
    final v = d.velocity.pixelsPerSecond.dx;
    final dx = _dx.value;
    final pastNext = dx < -_width * TrackSwipe.commitShare ||
        (v <= -TrackSwipe.flingVelocity && dx < 0);
    final pastPrevious = dx > _width * TrackSwipe.commitShare ||
        (v >= TrackSwipe.flingVelocity && dx > 0);
    if (pastNext && widget.canNext) {
      _commit(-1);
    } else if (pastPrevious && widget.canPrevious) {
      _commit(1);
    } else {
      _springBack();
    }
  }

  void _springBack() {
    // No overshoot: crossing the middle would flash the other neighbour.
    _dx.animateTo(0,
        duration: TrackSwipe.springBack, curve: RiffDurations.selectCurve);
  }

  Future<void> _commit(int direction) async {
    HapticFeedback.selectionClick();
    setState(() {
      _committed = direction;
      _leftKey = widget.currentKey;
      _heldPeek = direction < 0 ? widget.peekNext : widget.peekPrevious;
    });
    // Slide the rest of the way while the skip starts.
    final slide = _dx.animateTo(direction * _width,
        duration: TrackSwipe.slideOut, curve: RiffDurations.selectCurve);
    final started =
        await (direction < 0 ? widget.onNext() : widget.onPrevious())
            .catchError((Object _) => false);
    await slide.orCancel.catchError((Object _) {});
    if (!mounted || _committed != direction) return;
    if (!started) {
      setState(() {
        _committed = 0;
        _leftKey = null;
        _heldPeek = null;
      });
      _springBack();
      return;
    }
    // Usually the track has already changed; if not, don't hold forever.
    if (widget.currentKey == _leftKey) {
      _settle?.cancel();
      _settle = Timer(TrackSwipe.settleTimeout, _reset);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _width = box.maxWidth > 0 ? box.maxWidth : 1;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _onStart,
        onHorizontalDragUpdate: _onUpdate,
        onHorizontalDragEnd: _onEnd,
        onHorizontalDragCancel: () {
          if (!_busy) _springBack();
        },
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _dx,
            builder: (context, child) {
              final dx = _dx.value;
              final peek = _busy
                  ? _heldPeek
                  : dx < 0
                      ? widget.peekNext
                      : dx > 0
                          ? widget.peekPrevious
                          : null;
              final peekOffset =
                  dx < 0 || _committed < 0 ? dx + _width : dx - _width;
              return Stack(
                children: [
                  Transform.translate(offset: Offset(dx, 0), child: child),
                  if (peek != null && dx != 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Transform.translate(
                            offset: Offset(peekOffset, 0), child: peek),
                      ),
                    ),
                ],
              );
            },
            child: widget.current,
          ),
        ),
      );
    });
  }
}

/// Where a drag of [drag] px ends up when there is nothing to skip to: it
/// follows at first, then stiffens, never passing [give].
double blockedDragOffset(double drag, double give) {
  if (give <= 0 || drag == 0) return 0;
  return drag.sign * give * (1 - 1 / (1 + drag.abs() / give));
}

/// What the mini player can swipe to from where the queue is: whether
/// next / previous are possible and, outside shuffle, which tracks they
/// are (index into [queueLength]-long queue, or null when unknown).
({bool canNext, bool canPrevious, int? next, int? previous}) swipeNeighbours({
  required int queueLength,
  required int index,
  required bool shuffleOn,
  required bool queueLoopOn,
  required bool radioOn,
}) {
  if (queueLength <= 0 || index < 0 || index >= queueLength) {
    return (canNext: false, canPrevious: false, next: null, previous: null);
  }
  final isLast = index == queueLength - 1;
  // Mirrors the player: past the last track only shuffle, queue loop or
  // radio go on; previous never wraps outside shuffle.
  final canNext = shuffleOn || queueLoopOn || radioOn || !isLast;
  final canPrevious = shuffleOn || index > 0;
  int? next;
  int? previous;
  if (!shuffleOn) {
    if (!isLast) {
      next = index + 1;
    } else if (queueLoopOn && queueLength > 1) {
      next = 0;
    }
    if (index > 0) previous = index - 1;
  }
  return (
    canNext: canNext,
    canPrevious: canPrevious,
    next: next,
    previous: previous,
  );
}
