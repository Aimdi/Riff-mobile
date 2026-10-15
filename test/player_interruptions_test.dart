import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/player_interruptions.dart';

/// Calls, other apps' audio and unplugged headphones (what just_audio's
/// handleInterruptions did, but Pause on headset disconnect is obeyed).
void main() {
  late bool playing;
  late bool pauseOnUnplug;
  late List<String> calls;
  late PlayerInterruptions interruptions;

  setUp(() {
    playing = true;
    pauseOnUnplug = true;
    calls = [];
    interruptions = PlayerInterruptions(
      playing: () => playing,
      play: () async {
        calls.add('play');
        playing = true;
      },
      pause: () async {
        calls.add('pause');
        playing = false;
      },
      pauseOnUnplug: () => pauseOnUnplug,
    );
  });

  void begin(AudioInterruptionType type) =>
      interruptions.onInterruption(AudioInterruptionEvent(true, type));
  void end(AudioInterruptionType type) =>
      interruptions.onInterruption(AudioInterruptionEvent(false, type));

  test('a call pauses, and playback goes on after it', () async {
    begin(AudioInterruptionType.pause);
    expect(calls, ['pause']);
    end(AudioInterruptionType.pause);
    expect(calls, ['pause', 'play']);
  });

  test('nothing playing when it began: nothing to go on with', () {
    playing = false;
    begin(AudioInterruptionType.pause);
    end(AudioInterruptionType.pause);
    expect(calls, isEmpty);
  });

  test('played meanwhile, then paused: not played again when it ends', () {
    begin(AudioInterruptionType.pause);
    // Played from the lock screen during it (the player says so)...
    playing = true;
    interruptions.onPlaying(true);
    // ...and paused again.
    playing = false;
    interruptions.onPlaying(false);
    end(AudioInterruptionType.pause);
    expect(calls, ['pause']);
  });

  test('paused by you meanwhile (a sleep timer too): stays paused', () {
    begin(AudioInterruptionType.pause);
    interruptions.onUserPause();
    end(AudioInterruptionType.pause);
    expect(calls, ['pause']);
  });

  test('another app taking over for good pauses, for good', () {
    begin(AudioInterruptionType.unknown);
    expect(calls, ['pause']);
    end(AudioInterruptionType.unknown);
    // A later interruption ending doesn't bring it back either.
    end(AudioInterruptionType.pause);
    expect(calls, ['pause']);
  });

  test('a prompt that lowers the volume is left to Android', () {
    begin(AudioInterruptionType.duck);
    end(AudioInterruptionType.duck);
    expect(calls, isEmpty);
    expect(playing, isTrue);
  });

  group('headphones unplugged', () {
    test('pause, with Pause on headset disconnect on', () {
      interruptions.onBecomingNoisy();
      expect(calls, ['pause']);
    });

    test('play on through the speaker with it off (it paused regardless)', () {
      pauseOnUnplug = false;
      interruptions.onBecomingNoisy();
      expect(calls, isEmpty);
      expect(playing, isTrue);
    });

    test('nothing playing: nothing to do', () {
      playing = false;
      interruptions.onBecomingNoisy();
      expect(calls, isEmpty);
    });
  });
}
