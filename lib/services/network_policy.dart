import 'dart:io';

import 'package:dio/dio.dart';

/// One request attempt against the YouTube Music JSON API.
typedef ApiAttempt = Future<Response> Function();

/// Timeout + retry policy for the YouTube Music JSON API client.
///
/// Kept out of [MusicServices] so the retry ladder can be exercised in a
/// unit test with an injected attempt/sleep instead of a real socket.
class ApiRetryPolicy {
  const ApiRetryPolicy._();

  /// TCP/TLS handshake budget. A phone that cannot complete a handshake in
  /// 10s is on a dead leg or behind a captive portal; a fresh attempt is
  /// cheaper than waiting on a socket that will never answer.
  static const Duration connectTimeout = Duration(seconds: 10);

  /// Budget for pushing the request body out. The browse/next/search bodies
  /// are a few KB, so 15s only trips on a stalled uplink.
  static const Duration sendTimeout = Duration(seconds: 15);

  /// Gap allowed between response bytes. Home and continuation payloads are
  /// the biggest thing we download over this client, hence the most generous
  /// of the three. This is a per-chunk idle timeout, not a total-body cap,
  /// so a slow-but-alive connection still completes.
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Statuses that mean "ask again later", not "your request is wrong".
  static const Set<int> retryableStatusCodes = {
    408, // request timeout
    425, // too early
    429, // rate limited
    500,
    502,
    503,
    504,
  };

  /// Transport failures that a second attempt can plausibly clear.
  static const Set<DioExceptionType> retryableErrorTypes = {
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionError,
  };

  static bool shouldRetryStatus(int? statusCode) =>
      statusCode == null || retryableStatusCodes.contains(statusCode);

  static bool shouldRetryError(Object error) {
    if (error is! DioException) return false;
    if (retryableErrorTypes.contains(error.type)) return true;
    // Some platforms surface a dropped socket as `unknown` wrapping a
    // SocketException rather than `connectionError`.
    return error.type == DioExceptionType.unknown &&
        error.error is SocketException;
  }

  /// Exponential backoff, capped so a retry never costs more than the
  /// request it is retrying. [attemptIndex] is 0 for the first retry.
  static Duration backoff(int attemptIndex) {
    const base = 400; // ms
    const capMs = 2000;
    final ms = base * (1 << attemptIndex.clamp(0, 8));
    return Duration(milliseconds: ms > capMs ? capMs : ms);
  }

  static Future<void> _wait(Duration d) => Future.delayed(d);

  /// Runs [attempt], retrying up to [retries] extra times while the failure
  /// looks transient. Returns the first HTTP 200 response, or null when the
  /// budget is exhausted or the failure is not worth retrying (the caller
  /// turns that into its own error type).
  ///
  /// [sleep] is injectable so tests do not have to wait out the backoff.
  static Future<Response?> run(
    ApiAttempt attempt, {
    int retries = 2,
    void Function(Object error)? onError,
    Future<void> Function(Duration) sleep = _wait,
  }) async {
    var attemptsLeft = retries < 0 ? 0 : retries;
    var attemptIndex = 0;
    while (true) {
      Response? response;
      Object? failure;
      try {
        response = await attempt();
      } on DioException catch (e) {
        failure = e;
      }

      if (failure == null && response!.statusCode == 200) return response;

      final retryable = failure != null
          ? shouldRetryError(failure)
          : shouldRetryStatus(response!.statusCode);
      if (failure != null) onError?.call(failure);

      if (attemptsLeft <= 0 || !retryable) return null;
      attemptsLeft--;
      await sleep(backoff(attemptIndex++));
    }
  }
}
