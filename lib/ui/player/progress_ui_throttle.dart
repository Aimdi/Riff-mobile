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
