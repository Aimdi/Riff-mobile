import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Settings/yt_login_screen.dart';

void main() {
  const music = 'https://music.youtube.com/';

  test('two pages finishing at once close the screen only once', () async {
    var captures = 0;
    final capture = YtLoginCapture(capture: () async {
      captures++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return true;
    });
    final results = await Future.wait([
      capture.onPageFinished(music),
      capture.onPageFinished('${music}library'),
    ]);
    expect(results.where((ok) => ok), hasLength(1));
    expect(captures, 2);
    // And never again afterwards.
    expect(await capture.onPageFinished(music), isFalse);
    expect(captures, 2);
  });

  test('only music.youtube.com pages are captured', () async {
    var captures = 0;
    final capture = YtLoginCapture(capture: () async {
      captures++;
      return true;
    });
    expect(
        await capture.onPageFinished('https://accounts.google.com/x'), isFalse);
    expect(captures, 0);
    expect(await capture.onPageFinished(music), isTrue);
  });

  test('a failing cookie read is retried on the next page, not thrown',
      () async {
    var calls = 0;
    final capture = YtLoginCapture(capture: () async {
      if (calls++ == 0) throw PlatformException(code: 'no_cookies');
      return true;
    });
    expect(await capture.onPageFinished(music), isFalse);
    expect(await capture.onPageFinished(music), isTrue);
  });
}
