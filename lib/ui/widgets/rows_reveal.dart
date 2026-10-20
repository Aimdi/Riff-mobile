import 'package:flutter/widgets.dart';

import '/ui/theme/riff_tokens.dart';
import 'riff_motion.dart';

/// The rows of an eagerly built list (`ListView(children: …)`, slivers)
/// that come in together: content taking its skeleton's place, a new
/// chip's or range's rows. One animation runs for them all, so a row the
/// list first builds later, as it scrolls there, is already in rather
/// than fading then. (A lazily built list can use LoadedRowsFade.)
///
/// Make one in a State with a ticker, [play] it when the rows change, wrap
/// each of those rows with [row], and [dispose] it with the State.
class RowsReveal {
  RowsReveal({required TickerProvider vsync})
      : _controller = AnimationController(
            vsync: vsync, duration: RiffDurations.content, value: 1);

  final AnimationController _controller;
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: RiffDurations.enterCurve);

  /// The rows fade and rise in from now.
  void play() => _controller.forward(from: 0);

  /// [child] as one of the rows that come in together. A row keeps this
  /// wrapper throughout, so the list's elements keep their state.
  Widget row(Widget child, {Key? key}) =>
      _RevealRow(key: key, animation: _curve, child: child);

  void dispose() {
    _curve.dispose();
    _controller.dispose();
  }
}

class _RevealRow extends AnimatedWidget {
  const _RevealRow(
      {super.key, required Animation<double> animation, required this.child})
      : super(listenable: animation);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    final rise = reduceMotion(context) ? 0.0 : RiffMotionDistances.contentRise;
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, rise * (1 - t)),
        child: child,
      ),
    );
  }
}
