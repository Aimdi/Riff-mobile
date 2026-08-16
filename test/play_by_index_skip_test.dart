import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/play_by_index_skip.dart';

void main() {
  test('skips once when next index differs and loop-one is off', () {
    expect(
      shouldSkipAfterUnresolvableTrack(
        consecutiveFails: 1,
        maxConsecutiveFails: 1,
        currentIndex: 0,
        nextIndex: 1,
        loopOne: false,
      ),
      isTrue,
    );
  });

  test('does not skip when loop-one is on', () {
    expect(
      shouldSkipAfterUnresolvableTrack(
        consecutiveFails: 1,
        maxConsecutiveFails: 1,
        currentIndex: 0,
        nextIndex: 1,
        loopOne: true,
      ),
      isFalse,
    );
  });

  test('does not skip when next index is the current track', () {
    expect(
      shouldSkipAfterUnresolvableTrack(
        consecutiveFails: 1,
        maxConsecutiveFails: 1,
        currentIndex: 3,
        nextIndex: 3,
        loopOne: false,
      ),
      isFalse,
    );
  });

  test('does not skip after the consecutive fail budget', () {
    expect(
      shouldSkipAfterUnresolvableTrack(
        consecutiveFails: 2,
        maxConsecutiveFails: 1,
        currentIndex: 0,
        nextIndex: 1,
        loopOne: false,
      ),
      isFalse,
    );
  });

  test('previous restarts after 3 seconds, else skips back', () {
    expect(shouldRestartOnPrevious(Duration.zero), isFalse);
    expect(shouldRestartOnPrevious(const Duration(milliseconds: 3000)), isFalse);
    expect(shouldRestartOnPrevious(const Duration(milliseconds: 3001)), isTrue);
    expect(shouldRestartOnPrevious(const Duration(seconds: 5)), isTrue);
  });
}
