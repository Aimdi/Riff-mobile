/// Decides whether a `mediaItem` event represents the start of a *new* play.
///
/// `AudioHandler.mediaItem` is a plain `BehaviorSubject` with no `distinct()`,
/// and the handler re-emits the currently playing item on several non-play
/// events (duration discovery at queue index 0, queue reorder, shuffle, item
/// removal). Without a gate every one of those re-emissions is logged as a
/// fresh play: a duplicate Stats entry, a duplicate ListenBrainz scrobble, and
/// a bogus "quick skip" fed to the taste model for the song that is actually
/// still playing.
///
/// Pure and synchronous on purpose — [accept] must be called before any `await`
/// in the listener so the second event is rejected while the first callback is
/// still suspended.
class PlayLogGate {
  String? _lastId;

  /// Returns true the first time [id] is seen, false for consecutive repeats.
  bool accept(String id) {
    if (_lastId == id) return false;
    _lastId = id;
    return true;
  }

  /// Forget the last accepted id so the same track can be logged again.
  ///
  /// Used for an intentional user re-tap of the current queue row, which is a
  /// genuine new play. Not used for retries of a failed play.
  void reset() => _lastId = null;
}
