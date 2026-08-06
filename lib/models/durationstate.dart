class ProgressBarState {
  ProgressBarState({
    required this.current,
    required this.buffered,
    required this.total,
  });
  Duration current;
  Duration buffered;
  Duration total;
}

/// Immutable by-value copy of the *outgoing* item's progress, taken at the
/// moment the player switches to a new media item.
///
/// Needed because [ProgressBarState] has mutable fields and GetX's
/// `Rx.update` is `fn(_value); subject.add(_value)` — it mutates the very same
/// object the controller already holds a reference to. Reading
/// `progressBarStatus.value.total` *after* the update therefore yields the
/// incoming item's duration, which would then be persisted as the outgoing
/// episode's duration (wrong resume denominator: episodes get wiped or get a
/// nonsense progress bar).
class OutgoingProgress {
  const OutgoingProgress({required this.position, required this.total});

  /// Where the outgoing item was when playback moved on.
  final Duration position;

  /// The outgoing item's own duration — never the incoming item's.
  final Duration total;
}

/// Retargets the shared, mutable [state] at the incoming item's duration and
/// returns the outgoing item's position/total captured *before* the switch.
///
/// Callers must persist progress using the returned snapshot, not [state].
OutgoingProgress retargetProgressBar(
    ProgressBarState state, Duration? incomingDuration) {
  final snapshot =
      OutgoingProgress(position: state.current, total: state.total);
  state.total = incomingDuration ?? Duration.zero;
  return snapshot;
}
