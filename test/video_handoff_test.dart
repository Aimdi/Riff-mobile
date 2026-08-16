import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/video_handoff.dart';

void main() {
  test('skip hands off video only while video mode is active', () {
    expect(shouldHandoffVideoBeforeSkip(true), isTrue);
    expect(shouldHandoffVideoBeforeSkip(false), isFalse);
  });

  test('failed video enable resumes audio that was playing', () {
    expect(
      shouldResumeAudioAfterVideoEnableFailed(
        videoActive: false,
        wasPlayingBeforeAttempt: true,
      ),
      isTrue,
    );
    expect(
      shouldResumeAudioAfterVideoEnableFailed(
        videoActive: true,
        wasPlayingBeforeAttempt: true,
      ),
      isFalse,
    );
    expect(
      shouldResumeAudioAfterVideoEnableFailed(
        videoActive: false,
        wasPlayingBeforeAttempt: false,
      ),
      isFalse,
    );
  });

  test('skip-next advanced only when the index changes', () {
    expect(skipNextDidAdvance(fromIndex: 0, toIndex: 1), isTrue);
    expect(skipNextDidAdvance(fromIndex: 3, toIndex: 3), isFalse);
  });
}
