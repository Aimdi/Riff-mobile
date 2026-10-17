import 'dart:async';

import 'package:audio_session/audio_session.dart';

/// What a call, another app's audio and unplugged headphones do to Riff's
/// player. just_audio did this itself (handleInterruptions) and paused on
/// every unplug, so Settings › Pause on headset disconnect could be turned
/// off without effect; Riff now does it, the same way otherwise:
/// - a call or a navigation prompt over an episode (an interruption that
///   ends) pauses, and playback goes on after it, unless it was played or
///   paused meanwhile;
/// - another app taking over for good (a video, another player) pauses;
/// - a prompt that only lowers the volume is left to Android, which lowers
///   it itself (just_audio doubled the volume once it was over, which could
///   leave a lowered volume at full);
/// - unplugging (or Bluetooth headphones going) pauses while Pause on
///   headset disconnect is on, and plays on through the speaker when off.
class PlayerInterruptions {
  PlayerInterruptions({
    required this.playing,
    required this.play,
    required this.pause,
    required this.pauseOnUnplug,
  });

  final bool Function() playing;
  final Future<void> Function() play;
  final Future<void> Function() pause;

  /// Settings › Pause on headset disconnect.
  final bool Function() pauseOnUnplug;

  /// Paused by an interruption that will end: played again when it does.
  bool _resumeAfter = false;

  void onInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          _resumeAfter = false;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (playing()) {
            unawaited(pause());
            _resumeAfter = true;
          }
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.pause:
          if (_resumeAfter && !playing()) unawaited(play());
          _resumeAfter = false;
        case AudioInterruptionType.duck:
        case AudioInterruptionType.unknown:
          _resumeAfter = false;
      }
    }
  }

  /// The player started or stopped. Started (by a tap, the lock screen, a
  /// car), what the interruption paused is no longer to be played again.
  void onPlaying(bool playing) {
    if (playing) _resumeAfter = false;
  }

  /// A paused interruption the user then paused themselves (lock screen,
  /// headphones): theirs, not to be undone when the interruption ends.
  void onUserPause() => _resumeAfter = false;

  /// Headphones unplugged or Bluetooth headphones gone (Android's "becoming
  /// noisy"): pause, unless Pause on headset disconnect is off.
  void onBecomingNoisy() {
    if (pauseOnUnplug() && playing()) unawaited(pause());
  }
}
