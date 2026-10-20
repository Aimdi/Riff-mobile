import 'dart:async';

import 'package:flutter/material.dart';

import '/ui/theme/riff_tokens.dart';

/// A new track's cover fading in over the last one, in the player and the
/// mini player alike.
///
/// Unlike a plain [AnimatedSwitcher], the cover going away stays fully
/// drawn underneath until the new one has faded all the way in, so the
/// page never shows through mid-change (a dip to the page colour). Given
/// [precache], the last cover also stays until the new one's image is
/// decoded (at most [maxHold]), so the new cover fades in whole instead of
/// popping in after its fade.
class TrackCrossfade extends StatefulWidget {
  const TrackCrossfade({
    super.key,
    required this.trackKey,
    required this.child,
    this.precache,
    this.onSettled,
    this.duration = RiffDurations.trackChange,
    this.maxHold = RiffDurations.colour,
    this.fit = StackFit.expand,
  });

  /// What [child] shows (a song id); a new value cross-fades.
  final Object? trackKey;
  final Widget child;

  /// Completes once [child]'s image can be painted at once (precacheImage);
  /// called with this widget's context when [trackKey] changes. Null (or
  /// a null future): nothing to wait for.
  final Future<void>? Function(BuildContext context)? precache;

  /// Called once a track is on screen and its fade has ended (and after the
  /// first build): a good moment to get the next one ready.
  final VoidCallback? onSettled;

  final Duration duration;

  /// Longest the last cover waits for the new one's image.
  final Duration maxHold;

  final StackFit fit;

  @override
  State<TrackCrossfade> createState() => _TrackCrossfadeState();
}

class _Layer {
  _Layer(this.id, this.trackKey, this.child, this.controller)
      : opacity = CurvedAnimation(
            parent: controller, curve: RiffDurations.enterCurve);

  final int id;
  final Object? trackKey;
  Widget child;
  final AnimationController controller;
  final CurvedAnimation opacity;

  void dispose() {
    opacity.dispose();
    controller.dispose();
  }
}

class _TrackCrossfadeState extends State<TrackCrossfade>
    with TickerProviderStateMixin {
  final _layers = <_Layer>[];
  int _nextId = 0;

  /// The track waiting for its image, and the token of that wait (a newer
  /// track supersedes it).
  Object? _pendingKey;
  bool _pending = false;
  int _wait = 0;
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _layers.add(_newLayer(widget.trackKey, widget.child, shown: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSettled?.call();
    });
  }

  _Layer _newLayer(Object? key, Widget child, {bool shown = false}) {
    final controller = AnimationController(
        vsync: this, duration: widget.duration, value: shown ? 1 : 0);
    final layer = _Layer(_nextId++, key, child, controller);
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _settled(layer);
    });
    return layer;
  }

  /// [layer] is fully in: everything under it can go.
  void _settled(_Layer layer) {
    if (!mounted) return;
    final i = _layers.indexOf(layer);
    if (i > 0) {
      setState(() {
        for (final gone in _layers.sublist(0, i)) {
          gone.dispose();
        }
        _layers.removeRange(0, i);
      });
    }
    if (identical(_layers.last, layer)) widget.onSettled?.call();
  }

  @override
  void didUpdateWidget(covariant TrackCrossfade oldWidget) {
    super.didUpdateWidget(oldWidget);
    final top = _layers.last;
    if (widget.trackKey == top.trackKey) {
      // Same track (or back to it before the new one was ready): update it
      // in place.
      _cancelWait();
      top.child = widget.child;
      return;
    }
    if (_pending && widget.trackKey == _pendingKey) return;
    _cancelWait();
    _pending = true;
    _pendingKey = widget.trackKey;
    final wait = ++_wait;
    final precache = widget.precache;
    Future<void>? ready;
    try {
      ready = precache?.call(context);
    } catch (_) {
      ready = null;
    }
    if (ready == null) {
      // Nothing to wait for: in now (build follows this).
      _push();
      return;
    }
    _hold = Timer(widget.maxHold, () => _show(wait));
    ready.then((_) => _show(wait), onError: (_) => _show(wait));
  }

  void _cancelWait() {
    _hold?.cancel();
    _hold = null;
    _pending = false;
    _pendingKey = null;
    _wait++;
  }

  void _show(int wait) {
    if (!mounted || wait != _wait || !_pending) return;
    setState(_push);
  }

  /// The waiting track's layer goes on top and starts fading in. With
  /// animations paused here (TickerMode: the player collapsed behind the
  /// mini player, or the mini player behind the open player) it's out of
  /// sight: it takes over at once, rather than the old cover showing
  /// through the start of the next open.
  void _push() {
    final key = _pendingKey;
    _cancelWait();
    final watched = TickerMode.getNotifier(context).value;
    final layer = _newLayer(key, widget.child, shown: !watched);
    if (!watched) {
      for (final gone in _layers) {
        gone.dispose();
      }
      _layers
        ..clear()
        ..add(layer);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_layers.last, layer)) {
          widget.onSettled?.call();
        }
      });
      return;
    }
    _layers.add(layer);
    layer.controller.forward();
  }

  @override
  void dispose() {
    _hold?.cancel();
    for (final layer in _layers) {
      layer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: widget.fit,
      alignment: Alignment.center,
      children: [
        for (final layer in _layers)
          FadeTransition(
            key: ValueKey<int>(layer.id),
            opacity: layer.opacity,
            child: layer.child,
          ),
      ],
    );
  }
}
