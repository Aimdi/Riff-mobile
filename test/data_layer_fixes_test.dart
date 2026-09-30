import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/continuations.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/video_stream_service.dart';

void main() {
  group('buildRequestContext', () {
    Map<String, dynamic> base() => {
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'hl': 'de',
            },
            'user': {},
          },
        };

    test('hl override does not leak into the shared context', () {
      final shared = base();
      final req = buildRequestContext(shared, hl: 'en');
      expect(req['context']['client']['hl'], 'en');
      expect(shared['context']['client']['hl'], 'de');
    });

    test('mutating the request body leaves the shared context untouched', () {
      final shared = base();
      final req = buildRequestContext(shared);
      req['browseId'] = 'FEmusic_home';
      req['context']['client']['clientName'] = 'X';
      (req['context']['user'] as Map)['k'] = 1;
      expect(shared, base());
      expect(req['context']['client']['hl'], 'de');
    });
  });

  group('parseTrackCount', () {
    test('parses grouped and plain counts', () {
      expect(parseTrackCount('1,234 songs'), 1234);
      expect(parseTrackCount('1.234 Titel'), 1234);
      expect(parseTrackCount('12 tracks'), 12);
      expect(parseTrackCount('1 song'), 1);
    });

    test('"No songs" is zero, unparseable text is null', () {
      expect(parseTrackCount('No songs'), 0);
      expect(parseTrackCount('Keine Titel'), isNull);
      expect(parseTrackCount(''), isNull);
      expect(parseTrackCount(null), isNull);
      expect(parseTrackCount(42), isNull);
    });
  });

  group('getContinuations', () {
    Map<String, dynamic> page(String item, String? next) => {
          'continuationContents': {
            'playlistPanelContinuation': {
              'contents': [item],
              if (next != null)
                'continuations': [
                  {
                    'nextRadioContinuationData': {'continuation': next}
                  }
                ],
            }
          }
        };

    test('seed token is used once; later pages follow the response token',
        () async {
      final requested = <String>[];
      final pages = {
        getContinuationString('seed'): page('a', 't2'),
        getContinuationString('t2'): page('b', 't3'),
        getContinuationString('t3'): page('c', null),
      };
      final res = await getContinuations(
        {},
        'playlistPanelContinuation',
        10,
        (params) async {
          requested.add(params);
          return pages[params]!;
        },
        (dynamic contents) => List.from(contents as List),
        ctokenPath: 'Radio',
        isAdditionparamReturnReq: true,
        additionalParams_: getContinuationString('seed'),
      );
      expect(res[0], ['a', 'b', 'c']);
      expect(requested, [
        getContinuationString('seed'),
        getContinuationString('t2'),
        getContinuationString('t3'),
      ]);
    });
  });

  group('VideoStreamService cache freshness', () {
    final fetched = DateTime.utc(2026, 1, 1, 12);

    test('uses the expire= query parameter when present', () {
      final expire = fetched.add(const Duration(hours: 6));
      final url = 'https://rr1.googlevideo.com/videoplayback?'
          'expire=${expire.millisecondsSinceEpoch ~/ 1000}&itag=18';
      expect(VideoStreamService.urlExpiry(url, fetched), expire);
      expect(
          VideoStreamService.isFresh(
              url, fetched, expire.subtract(const Duration(hours: 1))),
          isTrue);
      // Inside the 30-minute safety margin: treated as stale.
      expect(
          VideoStreamService.isFresh(
              url, fetched, expire.subtract(const Duration(minutes: 10))),
          isFalse);
    });

    test('falls back to an assumed lifetime without expire=', () {
      const url = 'https://example.com/v.mp4';
      expect(VideoStreamService.isFresh(url, fetched, fetched), isTrue);
      expect(
          VideoStreamService.isFresh(
              url, fetched, fetched.add(const Duration(hours: 5))),
          isFalse);
    });
  });
}
