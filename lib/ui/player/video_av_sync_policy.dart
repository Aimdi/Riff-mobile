/// Pure A/V sync policy for muted [video_player] driven by just_audio.
///
/// Audio position is the clock. Video is corrected with rate nudges for small
/// drift and seeks for larger drift / jumps — without aggressive periodic seeks.
enum VideoSyncAction {
  /// Within tolerance; keep (or restore) nominal playback speed.
  none,

  /// Slightly speed up / slow down video to close a small gap smoothly.
  rateNudge,

  /// Seek video to the audio clock.
  seek,
}

class VideoSyncDecision {
  const VideoSyncDecision({
    required this.action,
    this.speedFactor = 1.0,
  });

  final VideoSyncAction action;

  /// Multiplier applied on top of the user's base playback speed.
  /// Only meaningful for [VideoSyncAction.rateNudge].
  final double speedFactor;

  static const none = VideoSyncDecision(action: VideoSyncAction.none);
}

class VideoAvSyncPolicy {
  const VideoAvSyncPolicy();

  /// Ignore signed drift at or below this (ms).
  static const ignoreDriftMs = 90;

  /// Prefer rate correction up to this absolute drift (ms).
  static const rateNudgeMaxMs = 480;

  /// Soft (periodic) seek threshold — standard quality (ms).
  static const softSeekMs = 750;

  /// Soft seek threshold when High video quality makes seeks hitchier (ms).
  static const softSeekHighQualityMs = 1100;

  /// Hard events (user seek, resume, panel open) seek above this (ms).
  static const hardSeekMs = 120;

  /// Audio position jump that implies an external seek (ms).
  static const audioJumpMs = 900;

  /// Rate nudge when video is behind audio.
  static const catchUpFactor = 1.06;

  /// Rate nudge when video is ahead of audio.
  static const slowDownFactor = 0.94;

  /// [signedDriftMs] = audioMs − videoMs. Positive ⇒ video behind.
  VideoSyncDecision decide({
    required int signedDriftMs,
    required bool softOnly,
    required bool highQuality,
    required bool audioJumpDetected,
  }) {
    final abs = signedDriftMs.abs();

    if (audioJumpDetected) {
      return abs > ignoreDriftMs
          ? const VideoSyncDecision(action: VideoSyncAction.seek)
          : VideoSyncDecision.none;
    }

    if (!softOnly) {
      return abs > hardSeekMs
          ? const VideoSyncDecision(action: VideoSyncAction.seek)
          : VideoSyncDecision.none;
    }

    if (abs <= ignoreDriftMs) {
      return VideoSyncDecision.none;
    }

    final softSeek = highQuality ? softSeekHighQualityMs : softSeekMs;
    if (abs >= softSeek) {
      return const VideoSyncDecision(action: VideoSyncAction.seek);
    }

    if (abs <= rateNudgeMaxMs) {
      final factor = signedDriftMs > 0 ? catchUpFactor : slowDownFactor;
      return VideoSyncDecision(
        action: VideoSyncAction.rateNudge,
        speedFactor: factor,
      );
    }

    // Between rate band and soft seek: still nudge — better than waiting.
    final factor = signedDriftMs > 0 ? catchUpFactor : slowDownFactor;
    return VideoSyncDecision(
      action: VideoSyncAction.rateNudge,
      speedFactor: factor,
    );
  }

  double effectiveSpeed({
    required double baseSpeed,
    required double speedFactor,
  }) {
    return (baseSpeed * speedFactor).clamp(0.25, 2.0);
  }
}
