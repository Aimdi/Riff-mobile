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

  test('shuffle miss is -1, never a valid queue index', () {
    expect(
      resolveShuffledQueueIndex(
        queueIds: ['a', 'b', 'c'],
        shuffledId: 'missing',
      ),
      -1,
    );
    expect(
      resolveShuffledQueueIndex(
        queueIds: ['a', 'b', 'c'],
        shuffledId: 'b',
      ),
      1,
    );
    expect(isValidQueueIndex(-1, 3), isFalse);
    expect(isValidQueueIndex(0, 3), isTrue);
    expect(isValidQueueIndex(3, 3), isFalse);
  });

  test('stale playByIndex should drop the loading spinner', () {
    expect(
      shouldClearLoadingOnStalePlayByIndex(
        requestedIndex: 0,
        currentIndex: 2,
      ),
      isTrue,
    );
    expect(
      shouldClearLoadingOnStalePlayByIndex(
        requestedIndex: 1,
        currentIndex: 1,
      ),
      isFalse,
    );
  });

  test('cloud server id strips the cloud_ prefix', () {
    expect(cloudServerSongId('cloud_abc'), 'abc');
    expect(cloudServerSongId('abc'), 'abc');
  });

  test('previous restarts after 3 seconds, else skips back', () {
    expect(shouldRestartOnPrevious(Duration.zero), isFalse);
    expect(shouldRestartOnPrevious(const Duration(milliseconds: 3000)), isFalse);
    expect(shouldRestartOnPrevious(const Duration(milliseconds: 3001)), isTrue);
    expect(shouldRestartOnPrevious(const Duration(seconds: 5)), isTrue);
  });

  test('coercePlayByIndex accepts Hive/JSON nums and strings', () {
    expect(coercePlayByIndex(3), 3);
    expect(coercePlayByIndex(2.0), 2);
    expect(coercePlayByIndex('4'), 4);
    expect(coercePlayByIndex(null), -1);
    expect(coercePlayByIndex('nope'), -1);
  });

  test('EOF advance arms once per track id', () {
    expect(
      shouldArmEofAdvance(currentId: 'a', lastArmedId: null),
      isTrue,
    );
    expect(
      shouldArmEofAdvance(currentId: 'a', lastArmedId: 'a'),
      isFalse,
    );
    expect(
      shouldArmEofAdvance(currentId: 'b', lastArmedId: 'a'),
      isTrue,
    );
    expect(
      shouldArmEofAdvance(currentId: '', lastArmedId: null),
      isFalse,
    );
    expect(
      shouldArmEofAdvance(currentId: null, lastArmedId: null),
      isFalse,
    );
  });
}
