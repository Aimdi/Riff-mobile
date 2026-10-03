/// Playback hardening: who asked for a transport command, the stall /
/// state-mismatch watchdog, and the rules that keep automatic segment skips
/// from fighting the listener. Pure Dart so it can be unit-tested; the audio
/// handler and player controller wire it up.
library;

/// Where a play / pause / seek / skip came from.
enum PlaybackCommandSource {
  /// The app's own UI.
  user,

  /// Media notification or lock screen.
  notification,

  /// Android Auto (car UI).
  androidAuto,

  /// Automatic segment skipping (podcast segments, SponsorBlock).
  autoSkip,

  /// Sleep timer.
  sleepTimer,

  /// Playback watchdog recovering from a stall.
  watchdog,

  /// Everything else the app does by itself (end of track, error recovery,
  /// headset / Bluetooth buttons, audio focus).
  system;

  /// A person asked for this, so automation must not undo it.
  bool get isUserIntent =>
      this == user || this == notification || this == androidAuto;

  static PlaybackCommandSource parse(Object? raw,
          {PlaybackCommandSource fallback = PlaybackCommandSource.user}) =>
      PlaybackCommandSource.values.firstWhere((s) => s.name == raw,
          orElse: () => fallback);
}

/// How long Android Auto counts as connected after it last browsed us.
const androidAutoBrowseWindow = Duration(minutes: 30);

/// Source of a command that reached the audio handler from outside the app
/// (audio_service doesn't say who sent it). Media buttons (headset,
/// Bluetooth) are [PlaybackCommandSource.system]; in car mode, or soon after
/// Android Auto browsed the library, it's Android Auto; otherwise the
/// notification / lock screen.
PlaybackCommandSource classifyExternalCommand({
  required bool mediaButton,
  required bool carMode,
  DateTime? lastBrowseAt,
  required DateTime now,
}) {
  if (mediaButton) return PlaybackCommandSource.system;
  if (carMode) return PlaybackCommandSource.androidAuto;
  if (lastBrowseAt != null &&
      now.difference(lastBrowseAt) <= androidAutoBrowseWindow) {
    return PlaybackCommandSource.androidAuto;
  }
  return PlaybackCommandSource.notification;
}

// ── Source-aware automatic skips ──────────────────────────────────────

/// A seek someone made, for the auto-skip rules.
class SeekRecord {
  const SeekRecord(
      {required this.source, required this.atMs, required this.targetMs});
  final PlaybackCommandSource source;
  final int atMs;
  final int targetMs;
}

/// After a person seeks, no automatic skip for this long.
const userSeekGrace = Duration(seconds: 8);

/// A person who seeks to just before (or into) a segment wants to hear it:
/// that segment is left alone for this long.
const userSeekSegmentHold = Duration(minutes: 1);

/// How far before a segment a seek still counts as "aiming at it".
const userSeekLeadIn = Duration(seconds: 15);

/// Whether an automatic skip of the segment [segStartSec]–[segEndSec] may
/// run now, given the last seek. Never right after a person's seek
/// (notification and Android Auto included), and not for a segment they
/// just jumped to or to just before it. Automatic seeks don't count.
bool autoSkipAllowed({
  required SeekRecord? lastSeek,
  required int nowMs,
  required double segStartSec,
  required double segEndSec,
}) {
  final s = lastSeek;
  if (s == null || !s.source.isUserIntent) return true;
  final age = nowMs - s.atMs;
  if (age < 0) return false;
  if (age < userSeekGrace.inMilliseconds) return false;
  final startMs = (segStartSec * 1000).round();
  final endMs = (segEndSec * 1000).round();
  final aimedAt = s.targetMs >= startMs - userSeekLeadIn.inMilliseconds &&
      s.targetMs < endMs;
  if (aimedAt && age < userSeekSegmentHold.inMilliseconds) return false;
  return true;
}

/// A pending automatic skip goes ahead only if no person has sought since
/// it started (the seek counter didn't move) and the same item still plays.
bool autoSkipStillValid({
  required int seekSerialAtStart,
  required int seekSerialNow,
  required String? itemAtStart,
  required String? itemNow,
}) =>
    seekSerialAtStart == seekSerialNow && itemAtStart == itemNow;

// ── Volume ramps (sleep fade, auto-skip duck) ─────────────────────────

/// Duck before an automatic skip.
const autoSkipDuck = Duration(milliseconds: 200);

/// Fade back in after it.
const autoSkipFadeIn = Duration(milliseconds: 300);

/// Volume factor while ducked.
const autoSkipDuckLevel = 0.1;

/// Linear ramp from [from] to [to] over [length], at [elapsed].
double volumeRamp(
    {required double from,
    required double to,
    required Duration elapsed,
    required Duration length}) {
  if (length <= Duration.zero) return to;
  final t = (elapsed.inMicroseconds / length.inMicroseconds).clamp(0.0, 1.0);
  return from + (to - from) * t;
}

// ── Watchdog ──────────────────────────────────────────────────────────

/// The player's own processing state, as the watchdog needs it.
enum WatchdogProcessing { idle, loading, buffering, ready, completed }

/// One look at the player and the media session.
class WatchdogSample {
  const WatchdogSample({
    required this.nowMs,
    required this.positionMs,
    required this.playerPlaying,
    required this.processing,
    required this.sessionPlaying,
    this.busy = false,
  });

  final int nowMs;
  final int positionMs;

  /// What the player says.
  final bool playerPlaying;
  final WatchdogProcessing processing;

  /// What the media session (notification, Android Auto, the app's UI)
  /// says.
  final bool sessionPlaying;

  /// Something is legitimately changing playback right now (a track
  /// loading, video mode, a crossfade, error recovery): don't judge.
  final bool busy;
}

enum WatchdogAction {
  none,

  /// Stalled: seek to where it is, which restarts the renderer.
  reseek,

  /// Still stalled: pause and play again.
  replay,

  /// Still stalled after both: stop trying until it moves again.
  giveUp,

  /// Player and media session disagree: publish the player's real state.
  republish,
}

/// Decides, every couple of seconds while something should be playing,
/// whether playback is stuck or the session shows the wrong state.
///
/// Stall: the player says ready and playing but the position hasn't moved
/// for over [stallLimit]. Remedies escalate (re-seek, then pause + play),
/// at most one per [cooldown], then it gives up until playback moves again.
/// Mismatch: player and session disagree on playing for [mismatchTicks]
/// looks in a row.
///
/// It never starts playback the player itself stopped: audio focus (a
/// call, another app) pauses on purpose.
class PlaybackWatchdog {
  PlaybackWatchdog({
    this.stallLimit = const Duration(seconds: 5),
    this.cooldown = const Duration(seconds: 6),
    this.mismatchTicks = 2,
    this.minAdvanceMs = 250,
  });

  final Duration stallLimit;
  final Duration cooldown;
  final int mismatchTicks;

  /// Movement smaller than this doesn't count as playing on.
  final int minAdvanceMs;

  int? _lastPosMs;
  int? _lastAdvanceAt;
  int? _lastActionAt;
  int _attempts = 0;
  bool _gaveUp = false;
  int _mismatch = 0;

  /// Forget everything (new track, explicit seek, pause).
  void reset() {
    _lastPosMs = null;
    _lastAdvanceAt = null;
    _attempts = 0;
    _gaveUp = false;
    _mismatch = 0;
  }

  WatchdogAction tick(WatchdogSample s) {
    if (s.busy) {
      _mismatch = 0;
      _rebase(s);
      return WatchdogAction.none;
    }

    // Session vs player.
    if (s.sessionPlaying != s.playerPlaying) {
      _mismatch++;
      if (_mismatch >= mismatchTicks) {
        _mismatch = 0;
        return WatchdogAction.republish;
      }
    } else {
      _mismatch = 0;
    }

    final running =
        s.playerPlaying && s.processing == WatchdogProcessing.ready;
    if (!running) {
      _rebase(s);
      return WatchdogAction.none;
    }

    final last = _lastPosMs;
    if (last == null || (s.positionMs - last).abs() >= minAdvanceMs) {
      // Moving (or the first look): all good.
      _lastPosMs = s.positionMs;
      _lastAdvanceAt = s.nowMs;
      _attempts = 0;
      _gaveUp = false;
      return WatchdogAction.none;
    }

    if (_gaveUp) return WatchdogAction.none;
    final since = s.nowMs - (_lastAdvanceAt ?? s.nowMs);
    if (since <= stallLimit.inMilliseconds) return WatchdogAction.none;
    final lastAction = _lastActionAt;
    if (lastAction != null &&
        s.nowMs - lastAction < cooldown.inMilliseconds) {
      return WatchdogAction.none;
    }
    _lastActionAt = s.nowMs;
    _attempts++;
    switch (_attempts) {
      case 1:
        return WatchdogAction.reseek;
      case 2:
        return WatchdogAction.replay;
      default:
        _gaveUp = true;
        return WatchdogAction.giveUp;
    }
  }

  void _rebase(WatchdogSample s) {
    _lastPosMs = s.positionMs;
    _lastAdvanceAt = s.nowMs;
  }
}
