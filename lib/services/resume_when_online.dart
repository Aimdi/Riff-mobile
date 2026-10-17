/// What Spotify's and YouTube Music's players do when the connection goes
/// (a tunnel, a lift): playback that stopped for want of one goes on, from
/// where it stopped, once it's back. Riff used to spend its retries, pass
/// the songs after over and stop, for you to press Play again.
library;

/// Where playback stopped for want of a connection, kept until it's back.
class ResumeWhenOnline {
  ResumeWhenOnline({this.window = const Duration(minutes: 10)});

  /// How long a stop is picked up again: after that, music starting by
  /// itself would come as a surprise.
  final Duration window;

  ({String id, Duration position, DateTime at})? _waiting;

  /// Whether something waits for the connection.
  bool get isWaiting => _waiting != null;

  /// Playback stopped at [position] in the song [id] at [now], for want
  /// of a connection.
  void stopped(String id, Duration position, DateTime now) =>
      _waiting = (id: id, position: position, at: now);

  /// You did something else meanwhile (played, paused, stopped, started
  /// another song): nothing goes on by itself.
  void cancel() => _waiting = null;

  /// Back online at [now]: what to go on with, once; null when nothing
  /// waits, it's been longer than [window], or something is [playing].
  ({String id, Duration position})? take(DateTime now,
      {required bool playing}) {
    final waiting = _waiting;
    _waiting = null;
    if (waiting == null || playing || now.difference(waiting.at) > window) {
      return null;
    }
    return (id: waiting.id, position: waiting.position);
  }
}
