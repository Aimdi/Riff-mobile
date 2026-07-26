import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/lrclib_query.dart';

/// Reproduces the old hand-built query string so the regression is explicit.
String _legacyUrl(String artist, String title, String? album, int dur) =>
    'https://lrclib.net/api/get?artist_name=${artist.replaceAll(" ", "+")}'
    '&track_name=${title.replaceAll(" ", "+")}'
    '&album_name=${album?.replaceAll(" ", "+")}'
    '&duration=$dur';

/// What Dio does with `queryParameters`: fold them into the request Uri.
String _resolvedUrl(Map<String, dynamic> params) => Uri.parse(lrclibGetUrl)
    .replace(
        queryParameters:
            params.map((k, v) => MapEntry(k, v.toString())))
    .toString();

void main() {
  group('buildLrclibGetParams', () {
    test('omits album_name entirely when album is null', () {
      final params = buildLrclibGetParams(
        artist: 'Daft Punk',
        title: 'Around the World',
        album: null,
        durationSec: 429,
      );

      expect(params.containsKey('album_name'), isFalse);
      expect(params, {
        'artist_name': 'Daft Punk',
        'track_name': 'Around the World',
        'duration': 429,
      });

      // The literal "null" must never reach the exact-match endpoint.
      final url = _resolvedUrl(params);
      expect(url, isNot(contains('album_name')));
      expect(url.toLowerCase(), isNot(contains('null')));

      // The old builder did exactly the wrong thing.
      expect(_legacyUrl('Daft Punk', 'Around the World', null, 429),
          contains('album_name=null'));
    });

    test('omits album_name when album is empty or whitespace only', () {
      for (final album in ['', '   ', '\t\n']) {
        final params = buildLrclibGetParams(
          artist: 'A',
          title: 'B',
          album: album,
          durationSec: 10,
        );
        expect(params.containsKey('album_name'), isFalse,
            reason: 'album ${album.codeUnits} should be dropped');
      }
    });

    test('includes album_name verbatim when a real album is known', () {
      final params = buildLrclibGetParams(
        artist: 'Pink Floyd',
        title: 'Time',
        album: 'The Dark Side of the Moon',
        durationSec: 413,
      );

      // Raw value, no "+" mangling — Dio percent-encodes it.
      expect(params['album_name'], 'The Dark Side of the Moon');
      expect(_resolvedUrl(params),
          contains('album_name=The+Dark+Side+of+the+Moon'));
    });

    test('special characters are carried as raw values, not injected', () {
      final params = buildLrclibGetParams(
        artist: 'Simon & Garfunkel',
        title: 'Bookends? #1 (50% Live)',
        album: 'Best of & More',
        durationSec: 120,
      );

      expect(params['artist_name'], 'Simon & Garfunkel');
      expect(params['track_name'], 'Bookends? #1 (50% Live)');
      expect(params['album_name'], 'Best of & More');

      final url = _resolvedUrl(params);
      // Encoded, so they cannot terminate or split the query string.
      expect(url, contains('artist_name=Simon+%26+Garfunkel'));
      expect(url, contains('track_name=Bookends%3F+%231+%2850%25+Live%29'));
      expect(url, contains('duration=120'));
      // Exactly four separators: three '&' between four params, plus the '?'.
      expect(Uri.parse(url).queryParameters.keys.toList(),
          ['artist_name', 'track_name', 'album_name', 'duration']);

      // The old builder leaked the raw '&', '?' and '#' into the query,
      // truncating the request at the fragment and inventing parameters.
      final legacy = Uri.parse(
          _legacyUrl('Simon & Garfunkel', 'Bookends? #1 (50% Live)',
              'Best of & More', 120));
      expect(legacy.queryParameters.containsKey('duration'), isFalse);
      expect(legacy.queryParameters['artist_name'], isNot('Simon & Garfunkel'));
    });

    test('trims surrounding whitespace on artist and title', () {
      final params = buildLrclibGetParams(
        artist: '  Radiohead ',
        title: ' Creep  ',
        album: '  Pablo Honey  ',
        durationSec: 238,
      );
      expect(params['artist_name'], 'Radiohead');
      expect(params['track_name'], 'Creep');
      expect(params['album_name'], 'Pablo Honey');
    });

    test('duration is sent as an integer value', () {
      final params = buildLrclibGetParams(
        artist: 'A',
        title: 'B',
        durationSec: 0,
      );
      expect(params['duration'], 0);
    });
  });
}
