import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/soulseek/soulseek_client.dart';
import 'package:harmonymusic/services/soulseek/soulseek_cover_service.dart';
import 'package:harmonymusic/services/soulseek/soulseek_search.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future? cancelFuture,
  ) async {
    return handler(options);
  }
}

void main() {
  group('CoverLookupHint', () {
    test('does not force bare query title onto every file', () {
      const file = SoulseekFile(
        username: 'u',
        filename: r'@@u\Music\Radiohead\OK Computer\01 - Airbag.flac',
        size: 1,
        hasFreeSlot: true,
        speed: 1,
      );
      final query = SoulseekQuery.parse('hu ta', SoulseekSearchMode.song);
      final hint = CoverLookupHint.fromFile(file, query);
      expect(hint.title, 'Airbag');
      expect(hint.artist, 'Radiohead');
      expect(hint.album, 'OK Computer');
    });

    test('uses Artist - Title query when artist present', () {
      const file = SoulseekFile(
        username: 'u',
        filename: r'@@u\Music\Misc\01 - Creep.flac',
        size: 1,
        hasFreeSlot: true,
        speed: 1,
      );
      final query = SoulseekQuery.parse(
        'Radiohead - Creep',
        SoulseekSearchMode.song,
      );
      final hint = CoverLookupHint.fromFile(file, query);
      expect(hint.artist, 'Radiohead');
      expect(hint.title, 'Creep');
    });

    test('searchTerms prefer artist+title', () {
      const hint = CoverLookupHint(
        artist: 'Radiohead',
        album: 'OK Computer',
        title: 'Airbag',
      );
      expect(hint.searchTerms.first, 'Radiohead Airbag');
      expect(hint.searchTerms, contains('Radiohead OK Computer'));
    });
  });

  test('parses iTunes text/javascript body via plain response', () async {
    final dio = Dio(BaseOptions(responseType: ResponseType.plain));
    dio.httpClientAdapter = _FakeAdapter((options) {
      expect(options.uri.host, 'itunes.apple.com');
      final body = jsonEncode({
        'resultCount': 1,
        'results': [
          {
            'artworkUrl100':
                'https://example.com/art/100x100bb.jpg',
          }
        ],
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: ['text/javascript; charset=utf-8'],
        },
      );
    });

    final svc = SoulseekCoverService(dio: dio);
    final url = await svc.coverForHint(
      const CoverLookupHint(artist: 'Radiohead', title: 'Creep'),
    );
    expect(url, 'https://example.com/art/300x300bb.jpg');
  });

  test('falls back to Deezer when iTunes empty', () async {
    final dio = Dio(BaseOptions(responseType: ResponseType.plain));
    dio.httpClientAdapter = _FakeAdapter((options) {
      if (options.uri.host.contains('itunes')) {
        return ResponseBody.fromString(
          jsonEncode({'resultCount': 0, 'results': []}),
          200,
          headers: {
            Headers.contentTypeHeader: ['text/javascript'],
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode({
          'data': [
            {
              'album': {
                'cover_medium': 'https://cdn.example/cover.jpg',
              }
            }
          ]
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    });

    final svc = SoulseekCoverService(dio: dio);
    final url = await svc.coverForHint(
      const CoverLookupHint(artist: 'Artist', title: 'Song'),
    );
    expect(url, 'https://cdn.example/cover.jpg');
  });
}
