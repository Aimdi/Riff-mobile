import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/video_av_sync_policy.dart';

void main() {
  const policy = VideoAvSyncPolicy();

  group('VideoAvSyncPolicy.decide', () {
    test('ignores tiny drift on soft ticks', () {
      final d = policy.decide(
        signedDriftMs: 40,
        softOnly: true,
        highQuality: false,
        audioJumpDetected: false,
      );
      expect(d.action, VideoSyncAction.none);
    });

    test('rate-nudges medium drift instead of seeking', () {
      final behind = policy.decide(
        signedDriftMs: 280,
        softOnly: true,
        highQuality: false,
        audioJumpDetected: false,
      );
      expect(behind.action, VideoSyncAction.rateNudge);
      expect(behind.speedFactor, VideoAvSyncPolicy.catchUpFactor);

      final ahead = policy.decide(
        signedDriftMs: -280,
        softOnly: true,
        highQuality: false,
        audioJumpDetected: false,
      );
      expect(ahead.action, VideoSyncAction.rateNudge);
      expect(ahead.speedFactor, VideoAvSyncPolicy.slowDownFactor);
    });

    test('soft-seeks when drift exceeds threshold', () {
      final d = policy.decide(
        signedDriftMs: 900,
        softOnly: true,
        highQuality: false,
        audioJumpDetected: false,
      );
      expect(d.action, VideoSyncAction.seek);
    });

    test('high quality tolerates more soft drift before seek', () {
      final mid = policy.decide(
        signedDriftMs: 900,
        softOnly: true,
        highQuality: true,
        audioJumpDetected: false,
      );
      expect(mid.action, VideoSyncAction.rateNudge);

      final large = policy.decide(
        signedDriftMs: 1200,
        softOnly: true,
        highQuality: true,
        audioJumpDetected: false,
      );
      expect(large.action, VideoSyncAction.seek);
    });

    test('hard events seek sooner than soft ticks', () {
      final soft = policy.decide(
        signedDriftMs: 200,
        softOnly: true,
        highQuality: false,
        audioJumpDetected: false,
      );
      expect(soft.action, VideoSyncAction.rateNudge);

      final hard = policy.decide(
        signedDriftMs: 200,
        softOnly: false,
        highQuality: false,
        audioJumpDetected: false,
      );
      expect(hard.action, VideoSyncAction.seek);
    });

    test('audio jumps always prefer seek when not tiny', () {
      final d = policy.decide(
        signedDriftMs: 150,
        softOnly: true,
        highQuality: true,
        audioJumpDetected: true,
      );
      expect(d.action, VideoSyncAction.seek);
    });
  });

  test('effectiveSpeed clamps and applies factor', () {
    expect(
      policy.effectiveSpeed(baseSpeed: 1.0, speedFactor: 1.06),
      closeTo(1.06, 0.001),
    );
    expect(
      policy.effectiveSpeed(baseSpeed: 1.5, speedFactor: 1.06),
      closeTo(1.59, 0.001),
    );
    expect(
      policy.effectiveSpeed(baseSpeed: 2.0, speedFactor: 1.06),
      2.0,
    );
  });
}
