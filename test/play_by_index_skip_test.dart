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
    // The queue was replaced: another song is current now.
    expect(
      isStalePlayByIndex(requestedSongId: 'a', currentSongId: 'c'),
      isTrue,
    );
    expect(
      isStalePlayByIndex(requestedSongId: 'a', currentSongId: null),
      isTrue,
    );
    expect(
      isStalePlayByIndex(requestedSongId: 'b', currentSongId: 'b'),
      isFalse,
    );
  });

  test('a queue edit that only moves the loading song keeps it playing', () {
    // Loading 'c' at index 2; removing 'a' (index 0) while the stream
    // resolves moves it to index 1. The old index check (2 != 1) dropped
    // the load and nothing played.
    final queue = ['a', 'b', 'c', 'd'];
    var current = 2;
    current = indexAfterRemoval(currentIndex: current, removedIndex: 0);
    queue.removeAt(0);
    expect(current, 1);
    expect(
      isStalePlayByIndex(requestedSongId: 'c', currentSongId: queue[current]),
      isFalse,
    );
  });

  test('removing a later item or one already gone keeps the cursor', () {
    expect(indexAfterRemoval(currentIndex: 3, removedIndex: 1), 2);
    expect(indexAfterRemoval(currentIndex: 3, removedIndex: 3), 3);
    expect(indexAfterRemoval(currentIndex: 3, removedIndex: 5), 3);
    // Not in the queue any more (a sheet opened before the queue changed):
    // the old `currentIndex > itemIndex` test moved the cursor to the
    // previous song.
    expect(indexAfterRemoval(currentIndex: 3, removedIndex: -1), 3);
    expect(indexAfterRemoval(currentIndex: 0, removedIndex: -1), 0);
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

  test('playByIndex result is start, hard-fail, or superseded', () {
    expect(playByIndexDidStart(true), isTrue);
    expect(playByIndexDidStart(false), isFalse);
    expect(playByIndexDidStart(null), isFalse);
    expect(playByIndexHardFailed(true), isFalse);
    expect(playByIndexHardFailed(false), isTrue);
    expect(playByIndexHardFailed(null), isFalse);
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
