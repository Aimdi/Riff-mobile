import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/youtube_stream_headers.dart';

void main() {
  test('Android client urls get the YouTube app user agent', () {
    final h = youtubeStreamHeaders(
        'https://rr1---sn-abc.googlevideo.com/videoplayback?expire=1&c=ANDROID&cver=19.09.37&id=x');
    expect(h!['User-Agent'], startsWith('com.google.android.youtube/19.09.37'));
    expect(h.containsKey('Origin'), isFalse);
  });

  test('ANDROID_VR and iOS clients get their own user agents', () {
    expect(
      youtubeStreamHeaders(
          'https://a.googlevideo.com/videoplayback?c=ANDROID_VR&cver=1.65.10')!['User-Agent'],
      startsWith('com.google.android.apps.youtube.vr.oculus/1.65.10'),
    );
    expect(
      youtubeStreamHeaders(
          'https://a.googlevideo.com/videoplayback?c=IOS&cver=19.45.4')!['User-Agent'],
      startsWith('com.google.ios.youtube/19.45.4'),
    );
  });

  test('web clients and unknown clients get a browser agent and origin', () {
    final web = youtubeStreamHeaders(
        'https://a.googlevideo.com/videoplayback?c=WEB&cver=2.20250101')!;
    expect(web['User-Agent'], contains('Mozilla/5.0'));
    expect(web['Origin'], 'https://www.youtube.com');
    expect(web['Referer'], 'https://www.youtube.com/');
    final none = youtubeStreamHeaders('https://a.googlevideo.com/videoplayback?id=1')!;
    expect(none['User-Agent'], contains('Mozilla/5.0'));
    expect(none['Origin'], 'https://www.youtube.com');
  });

  test('other urls get no headers', () {
    expect(youtubeStreamHeaders('https://example.com/ep.mp3'), isNull);
    expect(youtubeStreamHeaders('file:///data/ep.mp3'), isNull);
    expect(youtubeStreamHeaders('http://127.0.0.1:8080/x'), isNull);
    expect(youtubeStreamHeaders('::not a url::'), isNull);
  });
}
