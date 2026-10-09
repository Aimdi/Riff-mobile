/// Decides whether a position tick should refresh progress UI.
///
/// Side-effects (SponsorBlock, podcast progress, discovery) should still run
/// on every tick; only GetX progress fan-out needs throttling.
class ProgressUiThrottle {
  ProgressUiThrottle({
    this.minInterval = const Duration(milliseconds: 100),
    this.jumpThreshold = const Duration(milliseconds: 350),
  });

  final Duration minInterval;
  final Duration jumpThreshold;

  DateTime? _lastUiAt;

  /// Returns true when the UI should republish [position].
  bool shouldUpdate({
    required Duration position,
    required Duration previousUiPosition,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final jumped = (position - previousUiPosition).abs() >= jumpThreshold;
    if (jumped) {
      _lastUiAt = clock;
      return true;
    }
    if (_lastUiAt == null || clock.difference(_lastUiAt!) >= minInterval) {
      _lastUiAt = clock;
      return true;
    }
    return false;
  }

  void reset() => _lastUiAt = null;
}

/// Decides whether a buffered-position event should refresh progress UI.
///
/// Engines report the buffer far more often than it visibly moves (ExoPlayer
/// video mode with every 250 ms position tick, mostly unchanged). An
/// unchanged value never refreshes; a small move within [minInterval] of the
/// last refresh is skipped.
class BufferedUiThrottle {
  BufferedUiThrottle({
    this.minInterval = const Duration(milliseconds: 200),
    this.jumpThreshold = const Duration(milliseconds: 500),
  });

  final Duration minInterval;
  final Duration jumpThreshold;

  DateTime? _lastUiAt;

  /// Returns true when the UI should republish [buffered].
  bool shouldUpdate({
    required Duration buffered,
    required Duration previousUiBuffered,
    DateTime? now,
  }) {
    if (buffered == previousUiBuffered) return false;
    final clock = now ?? DateTime.now();
    if (_lastUiAt != null &&
        clock.difference(_lastUiAt!) < minInterval &&
        (buffered - previousUiBuffered).abs() < jumpThreshold) {
      return false;
    }
    _lastUiAt = clock;
    return true;
  }
}
