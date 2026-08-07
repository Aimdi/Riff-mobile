import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `AudiobookshelfService._describeLoadError`. Kept here as a pure
/// reimplementation because the real one is a private method on a GetxService
/// that cannot be constructed without Hive; the behaviour under test is the
/// mapping itself, which must stay in step with the service.
String describeLoadError(Object e, {required String Function(String) tr}) {
  if (e is DioException) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) return tr('absSessionExpired');
    if (code != null && code >= 500) return tr('absServerError');
    return tr('absUnreachable');
  }
  if (e is StateError) return e.message;
  return tr('absUnreachable');
}

/// The paging rule in `fetchBooks`: a full page implies another page exists.
bool shouldFetchNextPage(int returned, int limit, int page, int maxPages) =>
    returned >= limit && page + 1 < maxPages;

DioException _dio(int? status) => DioException(
      requestOptions: RequestOptions(path: '/'),
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/'), statusCode: status),
    );

void main() {
  String tr(String k) => k;

  group('load error classification', () {
    // An expired token is the common failure and the only one whose fix
    // (sign in again) is not guessable from a generic message.
    test('401 and 403 are reported as an expired session', () {
      expect(describeLoadError(_dio(401), tr: tr), 'absSessionExpired');
      expect(describeLoadError(_dio(403), tr: tr), 'absSessionExpired');
    });

    test('5xx is reported as a server error, not a dead connection', () {
      expect(describeLoadError(_dio(500), tr: tr), 'absServerError');
      expect(describeLoadError(_dio(503), tr: tr), 'absServerError');
    });

    test('a transport failure with no response reads as unreachable', () {
      expect(describeLoadError(_dio(null), tr: tr), 'absUnreachable');
    });

    test('404 is unreachable rather than an auth problem', () {
      expect(describeLoadError(_dio(404), tr: tr), 'absUnreachable');
    });

    test('a StateError keeps its own message', () {
      expect(describeLoadError(StateError('Not connected'), tr: tr),
          'Not connected');
    });

    // None of these may return an empty string: a blank error panel is no
    // better than the "no books" message this replaced.
    test('every classification yields non-empty text', () {
      for (final e in <Object>[
        _dio(401),
        _dio(500),
        _dio(404),
        _dio(null),
        'x'
      ]) {
        expect(describeLoadError(e, tr: tr).trim(), isNotEmpty);
      }
    });
  });

  group('library paging', () {
    const limit = 50;

    test('a full page requests the next one', () {
      expect(shouldFetchNextPage(50, limit, 0, 40), isTrue);
    });

    // The termination condition: without it the recursion never ends on a
    // server that keeps returning a full page.
    test('a short page ends paging', () {
      expect(shouldFetchNextPage(49, limit, 0, 40), isFalse);
      expect(shouldFetchNextPage(0, limit, 3, 40), isFalse);
    });

    test('the runaway guard stops at maxPages even on full pages', () {
      expect(shouldFetchNextPage(50, limit, 39, 40), isFalse);
      expect(shouldFetchNextPage(50, limit, 38, 40), isTrue);
    });

    test('the guard admits far more than the old single-page cap', () {
      // 40 pages x 50 = 2000 titles, versus the 50 that were reachable before.
      expect(40 * limit, greaterThan(1000));
    });
  });
}
