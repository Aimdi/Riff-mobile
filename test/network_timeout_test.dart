// Regression tests for the two "a hang is forever" resilience defects:
//
//  * MusicServices._sendRequest had no dio timeouts, so a wedged socket
//    parked the future indefinitely and its retry branch could never run.
//  * StreamProvider._fetchViaNewPipe awaited the riff/newpipe MethodChannel
//    with no timeout, and fetch() gates the whole youtube_explode fallback
//    ladder on that call returning — a NewPipe hang (as opposed to a NewPipe
//    failure) meant the fallbacks were never reached.
//
// The transport-facing code cannot be unit-tested directly (a real socket /
// a real platform channel, and _fetchViaNewPipe early-returns off Android),
// so the decision logic lives in helpers that take an injected call.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/network_policy.dart';
import 'package:harmonymusic/services/stream_service.dart';

Response _resp(int status) =>
    Response(requestOptions: RequestOptions(path: '/'), statusCode: status);

DioException _dioError(DioExceptionType type) =>
    DioException(requestOptions: RequestOptions(path: '/'), type: type);

Future<void> _noSleep(Duration _) async {}

void main() {
  group('StreamProvider.callWithTimeout (NewPipe hang falls through)', () {
    test('a call that never completes yields null once the timeout elapses',
        () async {
      // Injected "hang": a future nothing will ever complete, standing in
      // for a wedged NewPipeExtractor on the platform channel.
      final hung = Completer<String>();
      Object? reported;

      final sw = Stopwatch()..start();
      final res = await StreamProvider.callWithTimeout<String>(
        () => hung.future,
        const Duration(milliseconds: 50),
        onError: (e) => reported = e,
      );
      sw.stop();

      // null is what _fetchViaNewPipe returns on failure, and what makes
      // fetch() continue into the youtube_explode client ladder.
      expect(res, isNull);
      expect(reported, isA<TimeoutException>());
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(hung.isCompleted, isFalse);
    });

    test('a delayed-but-in-time call still returns its value', () async {
      final res = await StreamProvider.callWithTimeout<String>(
        () => Future.delayed(const Duration(milliseconds: 5), () => 'streams'),
        const Duration(seconds: 5),
      );
      expect(res, 'streams');
    });

    test('a thrown failure and a hang are indistinguishable to the caller',
        () async {
      Object? reported;
      final res = await StreamProvider.callWithTimeout<String>(
        () => Future<String>.error(StateError('boom')),
        const Duration(seconds: 5),
        onError: (e) => reported = e,
      );
      expect(res, isNull);
      expect(reported, isA<StateError>());
    });

    test('the NewPipe budget outlasts the native resolver but stays finite',
        () {
      // NewPipeResolver.kt sets connectTimeout=15s and readTimeout=20s on each
      // connection, so a single native request can legitimately take 35s. A
      // Dart timeout below that would cancel work that was about to succeed —
      // turning a slow cold resolve (watch page + ~2MB base.js on a congested
      // link) into a spurious failure. This backstop exists only for a channel
      // that never returns at all, so it must sit ABOVE the native worst case.
      const nativeWorstCase = Duration(seconds: 35);
      expect(StreamProvider.newPipeTimeout, greaterThan(nativeWorstCase));
      expect(StreamProvider.newPipeTimeout,
          lessThanOrEqualTo(const Duration(seconds: 60)));
      // The URL probe is a 2-byte ranged GET with its own 8s connect timeout,
      // so it stays on a short leash.
      expect(StreamProvider.urlProbeTimeout,
          lessThanOrEqualTo(const Duration(seconds: 20)));
    });
  });

  group('ApiRetryPolicy.run (retry path is reachable)', () {
    test('retries a timed-out request and returns the eventual 200', () async {
      var calls = 0;
      final res = await ApiRetryPolicy.run(
        () async {
          calls++;
          if (calls < 3) throw _dioError(DioExceptionType.receiveTimeout);
          return _resp(200);
        },
        retries: 2,
        sleep: _noSleep,
      );
      expect(calls, 3);
      expect(res?.statusCode, 200);
    });

    test('retries a 503 and gives up after the budget', () async {
      var calls = 0;
      final res = await ApiRetryPolicy.run(
        () async {
          calls++;
          return _resp(503);
        },
        retries: 2,
        sleep: _noSleep,
      );
      expect(calls, 3, reason: 'initial attempt + 2 retries');
      expect(res, isNull);
    });

    test('does not retry a request the server rejected outright', () async {
      var calls = 0;
      final res = await ApiRetryPolicy.run(
        () async {
          calls++;
          return _resp(400);
        },
        retries: 2,
        sleep: _noSleep,
      );
      expect(calls, 1);
      expect(res, isNull);
    });

    test('does not retry a non-transient transport error', () async {
      var calls = 0;
      final errors = <Object>[];
      final res = await ApiRetryPolicy.run(
        () async {
          calls++;
          throw _dioError(DioExceptionType.badCertificate);
        },
        retries: 2,
        sleep: _noSleep,
        onError: errors.add,
      );
      expect(calls, 1);
      expect(res, isNull);
      expect(errors, hasLength(1));
    });

    test('backoff grows and stays capped', () {
      expect(ApiRetryPolicy.backoff(0),
          lessThan(ApiRetryPolicy.backoff(1)));
      expect(ApiRetryPolicy.backoff(10),
          lessThanOrEqualTo(const Duration(seconds: 2)));
    });

    test('classifies statuses and transport errors', () {
      expect(ApiRetryPolicy.shouldRetryStatus(429), isTrue);
      expect(ApiRetryPolicy.shouldRetryStatus(500), isTrue);
      expect(ApiRetryPolicy.shouldRetryStatus(404), isFalse);
      expect(
          ApiRetryPolicy.shouldRetryError(
              _dioError(DioExceptionType.connectionTimeout)),
          isTrue);
      expect(ApiRetryPolicy.shouldRetryError(StateError('x')), isFalse);
    });
  });

  group('MusicServices dio client', () {
    test('has send/receive/connect timeouts so a hang becomes an error', () {
      final options = MusicServices().dio.options;
      expect(options.connectTimeout, isNotNull);
      expect(options.sendTimeout, isNotNull);
      expect(options.receiveTimeout, isNotNull);
      expect(options.receiveTimeout,
          lessThanOrEqualTo(const Duration(seconds: 60)));
    });
  });
}
