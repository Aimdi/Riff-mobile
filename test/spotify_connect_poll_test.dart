import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/spotify_api_service.dart';
import 'package:harmonymusic/services/spotify_auth_service.dart';
import 'package:harmonymusic/services/spotify_connect.dart';

/// Holds every request until the test answers it.
class _StalledAdapter implements HttpClientAdapter {
  final waiting = <Completer<ResponseBody>>[];
  var requests = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) {
    requests++;
    final c = Completer<ResponseBody>();
    waiting.add(c);
    return c.future;
  }

  void answerAll() {
    for (final c in waiting) {
      c.complete(ResponseBody.fromString('{"devices":[]}', 200));
    }
    waiting.clear();
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _StalledAdapter adapter;
  final realApi = SpotifyConnect.api;
  final realForeground = SpotifyConnect.isForeground;

  void useStalledApi() {
    adapter = _StalledAdapter();
    SpotifyConnect.api = SpotifyApiService(
      auth: SpotifyAuthService(),
      dio: Dio()..httpClientAdapter = adapter,
      token: () async => 'tok',
      refresh: () async => false,
      useCache: false,
    );
  }

  /// Answers requests until the running refresh is done.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      adapter.answerAll();
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  tearDown(() {
    SpotifyConnect.api = realApi;
    SpotifyConnect.isForeground = realForeground;
  });

  testWidgets('a slow refresh is not stacked with more polls', (tester) async {
    useStalledApi();
    SpotifyConnect.watch();
    await tester.pump(SpotifyConnect.pollEvery * 5);
    // Only the first refresh's first call: nothing answered yet.
    expect(adapter.requests, 1);

    // Once it is answered (devices, then what's playing), polling
    // carries on.
    await drain(tester);
    expect(adapter.requests, 2);
    await tester.pump(SpotifyConnect.pollEvery);
    expect(adapter.requests, 3);

    SpotifyConnect.unwatch();
    await drain(tester);
  });

  testWidgets('no polling while the app is in the background', (tester) async {
    useStalledApi();
    var foreground = false;
    SpotifyConnect.isForeground = () => foreground;
    SpotifyConnect.watch();
    await tester.pump(SpotifyConnect.pollEvery * 5);
    expect(adapter.requests, 0);

    foreground = true;
    await tester.pump(SpotifyConnect.pollEvery);
    expect(adapter.requests, 1);

    SpotifyConnect.unwatch();
    await drain(tester);
  });
}
