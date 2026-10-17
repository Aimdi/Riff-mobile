import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/odesli_links.dart';

/// Answers requests from a script, recording what was asked.
class _Scripted implements HttpClientAdapter {
  _Scripted(this.handler);
  final ResponseBody Function(RequestOptions o) handler;
  final asked = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body,
      Future<void>? cancelFuture) async {
    asked.add(o.uri);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _answer({String? ytm, String? yt}) => {
      'entityUniqueId': 'TIDAL_SONG::1',
      'linksByPlatform': {
        'tidal': {'url': 'https://listen.tidal.com/track/1'},
        if (ytm != null) 'youtubeMusic': {'url': ytm},
        if (yt != null) 'youtube': {'url': yt},
      },
    };

void main() {
  test("other music apps' pages, and song.link's", () {
    for (final link in [
      'https://tidal.com/browse/track/12345',
      'https://listen.tidal.com/album/678',
      'https://www.deezer.com/en/track/3135556',
      'https://deezer.page.link/abc',
      'https://music.amazon.co.uk/albums/B0123',
      'https://music.amazon.com/tracks/B0456',
      'https://soundcloud.com/artist/song',
      'https://on.soundcloud.com/xyz',
      'https://song.link/s/4cOdK2wGLETKBW3PvgPWqT',
      'https://album.link/i/1440857781',
      'https://music.yandex.ru/album/1/track/2',
    ]) {
      expect(isMusicServiceLink(link), isTrue, reason: link);
    }
    for (final link in [
      'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT',
      'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://example.com/tidal.com',
      'https://notdeezer.com/track/1',
      'feed://tidal.com/x',
    ]) {
      expect(isMusicServiceLink(link), isFalse, reason: link);
    }
  });

  test("a song.link page for a YouTube video needs no asking", () {
    expect(youtubeLinkInSongLink('https://song.link/y/dQw4w9WgXcQ'),
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(youtubeLinkInSongLink('https://song.link/s/4cOdK2wGLETKBW3PvgPWqT'),
        isNull);
    expect(youtubeLinkInSongLink('https://example.com/y/dQw4w9WgXcQ'), isNull);
  });

  test("Odesli's answer: YouTube Music's link, else YouTube's", () {
    expect(
        youtubeLinkFromOdesli(_answer(
            ytm: 'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
            yt: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ')),
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(
        youtubeLinkFromOdesli(
            _answer(yt: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ')),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(youtubeLinkFromOdesli(_answer()), isNull);
    expect(youtubeLinkFromOdesli('nonsense'), isNull);
  });

  group('asking Odesli', () {
    test('for the link, as written', () async {
      final adapter = _Scripted((o) => ResponseBody.fromString(
          jsonEncode(_answer(
              ytm: 'https://music.youtube.com/playlist?list=OLAK5uy_x')),
          200));
      final yt = await youtubeLinkViaOdesli(
          'https://listen.tidal.com/album/678',
          dio: Dio()..httpClientAdapter = adapter);
      expect(yt, 'https://music.youtube.com/playlist?list=OLAK5uy_x');
      final asked = adapter.asked.single;
      expect(asked.toString(), startsWith(odesliApi));
      expect(
          asked.queryParameters['url'], 'https://listen.tidal.com/album/678');
    });

    test("nothing when it can't say, or a song.link page says itself",
        () async {
      final adapter =
          _Scripted((o) => ResponseBody.fromString('{"code":"x"}', 400));
      final dio = Dio()..httpClientAdapter = adapter;
      expect(
          await youtubeLinkViaOdesli('https://tidal.com/browse/track/1',
              dio: dio),
          isNull);
      adapter.asked.clear();
      expect(
          await youtubeLinkViaOdesli('https://song.link/y/dQw4w9WgXcQ',
              dio: dio),
          'https://music.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(adapter.asked, isEmpty);
    });
  });
}
