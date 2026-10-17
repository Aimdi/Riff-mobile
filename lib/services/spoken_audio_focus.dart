import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import '/models/media_item_extras.dart';

/// Spoken word (a podcast episode, an audiobook) pauses while a navigation
/// prompt or a notification sound plays over it and goes on after, as
/// Android asks of speech apps and Pocket Casts, AntennaPod and Apple
/// Podcasts do: played on quieter under it, words are lost. Music plays on
/// quieter under them, as before.
///
/// Android settles how Riff gives way when Riff asks for audio focus, which
/// it does once and keeps (audio_session ignores a second request while it
/// holds focus). So when what plays turns from music to speech or back, the
/// session is set up for it, focus given back and, while playing, asked for
/// again.
class SpokenAudioFocus {
  SpokenAudioFocus({
    required this.configure,
    required this.setActive,
    required this.playing,
    required this.pauseForInterruptions,
  });

  /// [AudioSession.configure].
  final Future<void> Function(AudioSessionConfiguration configuration)
      configure;

  /// [AudioSession.setActive]: true asks for focus, false gives it back.
  final Future<bool> Function(bool active) setActive;

  /// Whether the player is playing, and so holds focus.
  final bool Function() playing;

  /// Podcast settings' Pause for interruptions; off, speech plays on
  /// quieter as music does.
  final bool Function() pauseForInterruptions;

  bool? _pauses;
  Future<void> _last = Future.value();

  /// A podcast episode or an audiobook chapter.
  static bool isSpoken(MediaItem item) =>
      item.isPodcastEpisode || item.isAudiobook;

  /// Speech pauses when another app asks to play over it (Android's
  /// "will pause when ducked"); music lets Android play it quieter.
  static AudioSessionConfiguration configurationFor({required bool pauses}) =>
      pauses
          ? const AudioSessionConfiguration.speech()
          : const AudioSessionConfiguration.music();

  /// Sets the session up for [item] (again after the setting changes) if
  /// it isn't already; one change at a time, in the order they came.
  /// Nothing playing ([item] null) leaves it as it is.
  Future<void> follow(MediaItem? item) {
    if (item == null) return _last;
    return _last =
        _last.then((_) => _apply(isSpoken(item) && pauseForInterruptions()));
  }

  Future<void> _apply(bool pauses) async {
    if (pauses == _pauses) return;
    // The session starts out set up for music (PlaybackRulesService, or
    // audio_session's own default).
    final first = _pauses == null;
    _pauses = pauses;
    if (first && !pauses) return;
    try {
      await configure(configurationFor(pauses: pauses));
      // Focus asked for before keeps the old setup: give it back and, when
      // playing, ask again (a play from here asks for it itself).
      await setActive(false);
      if (playing()) await setActive(true);
    } catch (_) {
      // The session can't be set up here: it plays on as it was.
    }
  }
}
