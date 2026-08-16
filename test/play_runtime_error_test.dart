import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/play_runtime_error.dart';

void main() {
  test('cache connection-closed is replayed, not refreshed', () {
    const err = 'Connection closed while receiving data';
    expect(isCacheConnectionClosedError(err), isTrue);
    expect(shouldRefreshUrlOnRuntimeError(err), isFalse);
    expect(isUnrecoverableDecodeError(err), isFalse);
  });

  test('decode errors skip URL refresh', () {
    expect(isUnrecoverableDecodeError('Unrecognized input format'), isTrue);
    expect(isUnrecoverableDecodeError('Unsupported format: xyz'), isTrue);
    expect(isUnrecoverableDecodeError('Malformed media container'), isTrue);
    expect(isUnrecoverableDecodeError('Failed to instantiate decoder'), isTrue);
    expect(shouldRefreshUrlOnRuntimeError('Unrecognized input format'), isFalse);
  });

  test('403 and source errors refresh the URL', () {
    expect(shouldRefreshUrlOnRuntimeError('Source error: HTTP 403'), isTrue);
    expect(shouldRefreshUrlOnRuntimeError('Failed to load (403 Forbidden)'), isTrue);
    expect(shouldRefreshUrlOnRuntimeError(StateError('socket hang up')), isTrue);
    expect(isCacheConnectionClosedError('HTTP 403'), isFalse);
  });

  test('URL refresh budget resets on a new song and stops at max', () {
    expect(
      canAutoRetryUrlRefresh(
        songId: null,
        budgetSongId: 'a',
        retryCount: 0,
        maxRetries: 2,
      ),
      isFalse,
    );
    expect(
      canAutoRetryUrlRefresh(
        songId: 'a',
        budgetSongId: 'b',
        retryCount: 2,
        maxRetries: 2,
      ),
      isTrue,
    );
    expect(
      canAutoRetryUrlRefresh(
        songId: 'a',
        budgetSongId: 'a',
        retryCount: 0,
        maxRetries: 2,
      ),
      isTrue,
    );
    expect(
      canAutoRetryUrlRefresh(
        songId: 'a',
        budgetSongId: 'a',
        retryCount: 2,
        maxRetries: 2,
      ),
      isFalse,
    );
  });

  test('retry and skip need a live handler and a valid index', () {
    expect(
      canRetryOrSkipPlayback(audioReady: true, queueLength: 3, index: 1),
      isTrue,
    );
    expect(
      canRetryOrSkipPlayback(audioReady: false, queueLength: 3, index: 1),
      isFalse,
    );
    expect(
      canRetryOrSkipPlayback(audioReady: true, queueLength: 0, index: 0),
      isFalse,
    );
    expect(
      canRetryOrSkipPlayback(audioReady: true, queueLength: 2, index: 2),
      isFalse,
    );
  });
}
