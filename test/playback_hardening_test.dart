import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/playback_hardening.dart';

WatchdogSample s(int t, int pos,
        {bool playing = true,
        WatchdogProcessing p = WatchdogProcessing.ready,
        bool? session,
        bool busy = false}) =>
    WatchdogSample(
        nowMs: t,
        positionMs: pos,
        playerPlaying: playing,
        processing: p,
        sessionPlaying: session ?? playing,
        busy: busy);

void main() {
  group('command sources', () {
    final now = DateTime(2026, 10, 3, 12);

    test('who counts as a person', () {
      expect(
          PlaybackCommandSource.values.where((s) => s.isUserIntent).toSet(), {
        PlaybackCommandSource.user,
        PlaybackCommandSource.notification,
        PlaybackCommandSource.androidAuto,
      });
    });

    test('external commands: headset, car, recent Android Auto, notification',
        () {
      expect(
          classifyExternalCommand(
              mediaButton: true, carMode: true, now: now),
          PlaybackCommandSource.system);
      expect(
          classifyExternalCommand(
              mediaButton: false, carMode: true, now: now),
          PlaybackCommandSource.androidAuto);
      expect(
          classifyExternalCommand(
              mediaButton: false,
              carMode: false,
              lastBrowseAt: now.subtract(const Duration(minutes: 5)),
              now: now),
          PlaybackCommandSource.androidAuto);
      expect(
          classifyExternalCommand(
              mediaButton: false,
              carMode: false,
              lastBrowseAt: now.subtract(const Duration(hours: 2)),
              now: now),
          PlaybackCommandSource.notification);
      expect(
          classifyExternalCommand(
              mediaButton: false, carMode: false, now: now),
          PlaybackCommandSource.notification);
    });

    test('parse', () {
      expect(PlaybackCommandSource.parse('watchdog'),
          PlaybackCommandSource.watchdog);
      expect(PlaybackCommandSource.parse(null), PlaybackCommandSource.user);
      expect(
          PlaybackCommandSource.parse('nope',
              fallback: PlaybackCommandSource.system),
          PlaybackCommandSource.system);
    });
  });

  group('auto-skip rules', () {
    SeekRecord seek(PlaybackCommandSource src, int at, int target) =>
        SeekRecord(source: src, atMs: at, targetMs: target);

    test('no seek, or an automatic one: skip', () {
      expect(
          autoSkipAllowed(
              lastSeek: null, nowMs: 1000, segStartSec: 10, segEndSec: 20),
          isTrue);
      expect(
          autoSkipAllowed(
              lastSeek: seek(PlaybackCommandSource.autoSkip, 900, 9500),
              nowMs: 1000,
              segStartSec: 10,
              segEndSec: 20),
          isTrue);
    });

    test('right after a person seeks — app, notification or car: no skip',
        () {
      for (final src in [
        PlaybackCommandSource.user,
        PlaybackCommandSource.notification,
        PlaybackCommandSource.androidAuto,
      ]) {
        expect(
            autoSkipAllowed(
                lastSeek: seek(src, 100000, 500000),
                nowMs: 104000,
                segStartSec: 10,
                segEndSec: 20),
            isFalse,
            reason: src.name);
      }
      // ...but fine once the grace period is over, elsewhere in the episode.
      expect(
          autoSkipAllowed(
              lastSeek: seek(PlaybackCommandSource.user, 100000, 500000),
              nowMs: 100000 + userSeekGrace.inMilliseconds,
              segStartSec: 10,
              segEndSec: 20),
          isTrue);
    });

    test('a seek aimed at the segment holds it for a minute', () {
      // Sought to 2 s before a segment at 100–130 s.
      final r = seek(PlaybackCommandSource.notification, 0, 98000);
      expect(
          autoSkipAllowed(
              lastSeek: r, nowMs: 30000, segStartSec: 100, segEndSec: 130),
          isFalse);
      expect(
          autoSkipAllowed(
              lastSeek: r,
              nowMs: userSeekSegmentHold.inMilliseconds,
              segStartSec: 100,
              segEndSec: 130),
          isTrue);
      // Sought well before it: only the short grace applies.
      final far = seek(PlaybackCommandSource.user, 0, 40000);
      expect(
          autoSkipAllowed(
              lastSeek: far, nowMs: 30000, segStartSec: 100, segEndSec: 130),
          isTrue);
      // Sought past it: not aiming at it.
      final past = seek(PlaybackCommandSource.user, 0, 130000);
      expect(
          autoSkipAllowed(
              lastSeek: past, nowMs: 30000, segStartSec: 100, segEndSec: 130),
          isTrue);
    });

    test('a clock going backwards never skips', () {
      expect(
          autoSkipAllowed(
              lastSeek: seek(PlaybackCommandSource.user, 5000, 1),
              nowMs: 1000,
              segStartSec: 100,
              segEndSec: 130),
          isFalse);
    });

    test('pending skip is dropped by a seek or a track change', () {
      expect(
          autoSkipStillValid(
              seekSerialAtStart: 3,
              seekSerialNow: 3,
              itemAtStart: 'a',
              itemNow: 'a'),
          isTrue);
      expect(
          autoSkipStillValid(
              seekSerialAtStart: 3,
              seekSerialNow: 4,
              itemAtStart: 'a',
              itemNow: 'a'),
          isFalse);
      expect(
          autoSkipStillValid(
              seekSerialAtStart: 3,
              seekSerialNow: 3,
              itemAtStart: 'a',
              itemNow: 'b'),
          isFalse);
    });

    test('volume ramp', () {
      const len = Duration(milliseconds: 200);
      expect(volumeRamp(from: 1, to: 0.1, elapsed: Duration.zero, length: len),
          1);
      expect(
          volumeRamp(
              from: 1,
              to: 0.1,
              elapsed: const Duration(milliseconds: 100),
              length: len),
          closeTo(0.55, 1e-9));
      expect(
          volumeRamp(
              from: 0.1, to: 1, elapsed: const Duration(seconds: 9), length: len),
          1);
      expect(volumeRamp(from: 1, to: 0, elapsed: Duration.zero, length: Duration.zero),
          0);
    });
  });

  group('watchdog', () {
    test('playing normally: nothing to do', () {
      final w = PlaybackWatchdog();
      for (var t = 0; t < 30000; t += 2000) {
        expect(w.tick(s(t, t)), WatchdogAction.none);
      }
    });

    test('stuck position escalates: reseek, replay, give up', () {
      final w = PlaybackWatchdog();
      final actions = [
        for (var t = 0; t <= 40000; t += 2000) w.tick(s(t, 5000))
      ].where((a) => a != WatchdogAction.none).toList();
      expect(actions, [
        WatchdogAction.reseek,
        WatchdogAction.replay,
        WatchdogAction.giveUp,
      ]);
    });

    test('waits more than 5 s before acting, then a cooldown', () {
      final w = PlaybackWatchdog();
      expect(w.tick(s(0, 1000)), WatchdogAction.none);
      expect(w.tick(s(2000, 1000)), WatchdogAction.none);
      expect(w.tick(s(4000, 1000)), WatchdogAction.none);
      expect(w.tick(s(5000, 1000)), WatchdogAction.none); // exactly 5 s
      expect(w.tick(s(6000, 1000)), WatchdogAction.reseek);
      expect(w.tick(s(8000, 1000)), WatchdogAction.none); // cooldown
      expect(w.tick(s(12000, 1000)), WatchdogAction.replay);
    });

    test('moving again resets the escalation', () {
      final w = PlaybackWatchdog();
      w.tick(s(0, 1000));
      expect(w.tick(s(6000, 1000)), WatchdogAction.reseek);
      expect(w.tick(s(8000, 3000)), WatchdogAction.none); // moving
      expect(w.tick(s(14100, 3000)), WatchdogAction.reseek); // fresh start
    });

    test('paused, buffering, loading or busy: never a stall', () {
      final w = PlaybackWatchdog();
      for (var t = 0; t < 30000; t += 2000) {
        expect(w.tick(s(t, 0, playing: false)), WatchdogAction.none);
        expect(w.tick(s(t, 0, p: WatchdogProcessing.buffering)),
            WatchdogAction.none);
        expect(w.tick(s(t, 0, busy: true)), WatchdogAction.none);
      }
    });

    test('player and session disagree twice in a row: republish', () {
      final w = PlaybackWatchdog();
      expect(w.tick(s(0, 0, playing: false, session: true)),
          WatchdogAction.none);
      expect(w.tick(s(2000, 0, playing: false, session: true)),
          WatchdogAction.republish);
      // A single blip doesn't count.
      expect(w.tick(s(4000, 0, playing: false, session: true)),
          WatchdogAction.none);
      expect(w.tick(s(6000, 0, playing: false, session: false)),
          WatchdogAction.none);
      expect(w.tick(s(8000, 0, playing: false, session: true)),
          WatchdogAction.none);
    });

    test('never restarts playback the player stopped (audio focus)', () {
      final w = PlaybackWatchdog();
      final out = {
        for (var t = 0; t < 60000; t += 2000)
          w.tick(s(t, 1000, playing: false))
      };
      expect(out, {WatchdogAction.none});
    });
  });
}
