/// A headset's one button, read as Android's own media sessions, Spotify,
/// YouTube Music and AntennaPod read it: pressed once it plays or pauses,
/// twice it goes on, three times it goes back. Headphones' and car
/// stereos' own next and previous buttons go on and back the same way.
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart' show MediaButton;

import 'headphone_controls.dart';

enum MediaButtonAction {
  playPause,
  next,
  previous,
  skipForward,
  skipBack,
  nextChapter,
  previousChapter,
  bookmark,
}

/// What going on ([forward]) or back does in a podcast episode or an
/// audiobook ([longForm]): skip, unless a podcast episode's ([podcast])
/// headphone buttons do otherwise ([HeadphoneControls]: [nextAction],
/// [previousAction]); music goes to the next or previous song.
MediaButtonAction _onOrBack(bool forward,
    {required bool longForm,
    required bool podcast,
    required HeadphoneAction nextAction,
    required HeadphoneAction previousAction}) {
  if (!longForm) {
    return forward ? MediaButtonAction.next : MediaButtonAction.previous;
  }
  if (podcast) {
    switch (forward ? nextAction : previousAction) {
      case HeadphoneAction.chapter:
        return forward
            ? MediaButtonAction.nextChapter
            : MediaButtonAction.previousChapter;
      case HeadphoneAction.bookmark:
        return MediaButtonAction.bookmark;
      case HeadphoneAction.episode:
        return forward ? MediaButtonAction.next : MediaButtonAction.previous;
      case HeadphoneAction.skip:
        break;
    }
  }
  return forward ? MediaButtonAction.skipForward : MediaButtonAction.skipBack;
}

/// What the button does, pressed [presses] times: music goes to the next
/// or previous song; podcast episodes and audiobooks ([longForm]) skip
/// forward or back, as their notification's buttons do, or what an
/// episode's headphone buttons are set to.
MediaButtonAction mediaButtonAction(int presses,
        {required bool longForm,
        bool podcast = false,
        HeadphoneAction nextAction = HeadphoneAction.skip,
        HeadphoneAction previousAction = HeadphoneAction.skip}) =>
    presses <= 1
        ? MediaButtonAction.playPause
        : _onOrBack(presses == 2,
            longForm: longForm,
            podcast: podcast,
            nextAction: nextAction,
            previousAction: previousAction);

/// What a headphone's (or a car stereo's) own [button] does: music goes to
/// the next or previous song; podcast episodes and audiobooks ([longForm])
/// skip forward or back, as AntennaPod and Pocket Casts do, rather than
/// end the episode, or start it over, or what an episode's headphone
/// buttons are set to.
MediaButtonAction mediaButtonPressed(MediaButton button,
        {required bool longForm,
        bool podcast = false,
        HeadphoneAction nextAction = HeadphoneAction.skip,
        HeadphoneAction previousAction = HeadphoneAction.skip}) =>
    button == MediaButton.media
        ? MediaButtonAction.playPause
        : _onOrBack(button == MediaButton.next,
            longForm: longForm,
            podcast: podcast,
            nextAction: nextAction,
            previousAction: previousAction);

/// Counts the button's presses: one within [window] of the last counts
/// with it. [onPresses] gets the count once they stop, or straight away at
/// the third (there's nothing more to wait for).
class MediaButtonPresses {
  MediaButtonPresses(this.onPresses, {this.window = defaultWindow});

  /// Android's double-tap timeout, as its own media sessions wait for a
  /// second press.
  static const defaultWindow = Duration(milliseconds: 300);

  final void Function(int presses) onPresses;
  final Duration window;

  Timer? _timer;
  int _presses = 0;

  void press() {
    _timer?.cancel();
    if (++_presses >= 3) {
      _report();
    } else {
      _timer = Timer(window, _report);
    }
  }

  /// Forgets presses not reported yet.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _presses = 0;
  }

  void _report() {
    final presses = _presses;
    cancel();
    onPresses(presses);
  }
}
