import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/spotify_api_service.dart';
import 'package:harmonymusic/services/spotify_auth_service.dart';

void main() {
  group('PKCE', () {
    test('verifier length is clamped to the RFC 7636 range', () {
      final r = Random(1);
      expect(
          SpotifyAuthService.generateCodeVerifier(length: 10, random: r).length,
          43);
      expect(
          SpotifyAuthService.generateCodeVerifier(length: 500, random: r)
              .length,
          128);
      expect(
          SpotifyAuthService.generateCodeVerifier(length: 64, random: r).length,
          64);
    });

    test('verifier uses only unreserved characters', () {
      final v = SpotifyAuthService.generateCodeVerifier(random: Random(7));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(v), isTrue);
    });

    test('two verifiers differ', () {
      expect(SpotifyAuthService.generateCodeVerifier(),
          isNot(SpotifyAuthService.generateCodeVerifier()));
    });

    // Spotify rejects a padded challenge, so stripping '=' is load-bearing.
    test('challenge is unpadded base64url of the sha256 digest', () {
      const verifier = 'abc123';
      final expected =
          base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes)
              .replaceAll('=', '');
      final actual = SpotifyAuthService.codeChallengeS256(verifier);
      expect(actual, expected);
      expect(actual.contains('='), isFalse);
      expect(actual.contains('+'), isFalse);
      expect(actual.contains('/'), isFalse);
    });
  });

  group('buildAuthUrl', () {
    final url = SpotifyAuthService.buildAuthUrl(
      clientId: 'CID',
      codeChallenge: 'CHAL',
      state: 'STATE',
    );

    test('targets the documented public authorize endpoint', () {
      expect(url.origin, 'https://accounts.spotify.com');
      expect(url.path, '/authorize');
    });

    test('carries the PKCE parameters and no client secret', () {
      final q = url.queryParameters;
      expect(q['client_id'], 'CID');
      expect(q['response_type'], 'code');
      expect(q['code_challenge_method'], 'S256');
      expect(q['code_challenge'], 'CHAL');
      expect(q['state'], 'STATE');
      expect(q['redirect_uri'], SpotifyAuthService.redirectUri);
      expect(url.toString().contains('client_secret'), isFalse);
    });

    test('requests read-only scopes only', () {
      final scopes = url.queryParameters['scope']!.split(' ');
      expect(scopes, contains('playlist-read-private'));
      expect(scopes, contains('user-library-read'));
      for (final s in scopes) {
        expect(s.contains('modify'), isFalse, reason: '$s can write');
        expect(s.contains('write'), isFalse, reason: '$s can write');
      }
    });
  });

  group('parseRedirect', () {
    test('accepts a matching state and returns the code', () {
      final r = SpotifyAuthService.parseRedirect(
          '${SpotifyAuthService.redirectUri}?code=AC&state=S',
          expectedState: 'S');
      expect(r.ok, isTrue);
      expect(r.code, 'AC');
    });

    // Without this check, a response we did not initiate could inject a code.
    test('rejects a mismatched or missing state', () {
      expect(
        SpotifyAuthService.parseRedirect(
                '${SpotifyAuthService.redirectUri}?code=AC&state=WRONG',
                expectedState: 'S')
            .ok,
        isFalse,
      );
      expect(
        SpotifyAuthService.parseRedirect(
                '${SpotifyAuthService.redirectUri}?code=AC',
                expectedState: 'S')
            .ok,
        isFalse,
      );
    });

    test('reports a cancelled sign-in in plain language', () {
      final r = SpotifyAuthService.parseRedirect(
          '${SpotifyAuthService.redirectUri}?error=access_denied&state=S',
          expectedState: 'S');
      expect(r.ok, isFalse);
      expect(r.error, 'Sign-in cancelled');
    });

    test('a state match with no code is still a failure', () {
      final r = SpotifyAuthService.parseRedirect(
          '${SpotifyAuthService.redirectUri}?state=S',
          expectedState: 'S');
      expect(r.ok, isFalse);
    });
  });

  group('isRedirect', () {
    test('matches only our callback', () {
      expect(
          SpotifyAuthService.isRedirect(
              '${SpotifyAuthService.redirectUri}?code=x'),
          isTrue);
      expect(
          SpotifyAuthService.isRedirect('https://accounts.spotify.com/login'),
          isFalse);
    });
  });

  group('isExpired', () {
    test('expires early by the skew so in-flight requests do not lapse', () {
      const expiry = 1000000;
      expect(SpotifyAuthService.isExpired(expiry, expiry - 120000), isFalse);
      // Inside the 60s skew window.
      expect(SpotifyAuthService.isExpired(expiry, expiry - 30000), isTrue);
      expect(SpotifyAuthService.isExpired(expiry, expiry + 1), isTrue);
    });

    test('an unset expiry counts as expired', () {
      expect(SpotifyAuthService.isExpired(0, 0), isTrue);
    });
  });

  group('SpotifyApiService.parseTrackItem', () {
    test('reads name, joined artists and duration', () {
      final t = SpotifyApiService.parseTrackItem({
        'track': {
          'id': 'abc',
          'name': 'Faded',
          'duration_ms': 212000,
          'artists': [
            {'name': 'Alan Walker'},
            {'name': 'Iselin Solheim'}
          ],
        }
      })!;
      expect(t.title, 'Faded');
      expect(t.artists, 'Alan Walker, Iselin Solheim');
      expect(t.durationMs, 212000);
    });

    test('accepts a bare track object as well as a wrapped item', () {
      final t = SpotifyApiService.parseTrackItem({
        'id': 'x',
        'name': 'Song',
        'artists': [
          {'name': 'A'}
        ],
      });
      expect(t?.title, 'Song');
    });

    // Spotify legitimately returns these inside a playlist; importing them
    // would produce entries that can never resolve to anything playable.
    test('skips removed tracks, local files and podcast episodes', () {
      expect(SpotifyApiService.parseTrackItem({'track': null}), isNull);
      expect(
        SpotifyApiService.parseTrackItem({
          'track': {'name': 'Local', 'is_local': true}
        }),
        isNull,
      );
      expect(
        SpotifyApiService.parseTrackItem({
          'track': {'name': 'Ep 1', 'type': 'episode'}
        }),
        isNull,
      );
      expect(SpotifyApiService.parseTrackItem({'track': {}}), isNull);
      expect(SpotifyApiService.parseTrackItem('nonsense'), isNull);
    });

    test('treats a zero or missing duration as unknown', () {
      final t = SpotifyApiService.parseTrackItem({
        'track': {'name': 'S', 'duration_ms': 0}
      })!;
      expect(t.durationMs, isNull);
    });
  });

  group('SpotifyApiService paging', () {
    test('parses a page and its next link', () {
      const body = '''
      {"items":[{"track":{"id":"1","name":"A","duration_ms":1000,
      "artists":[{"name":"X"}]}}],
      "next":"https://api.spotify.com/v1/me/tracks?offset=50&limit=50"}
      ''';
      expect(SpotifyApiService.parseTrackPage(body).single.title, 'A');
      expect(SpotifyApiService.nextPageUrl(body), contains('offset=50'));
    });

    test('a null next ends paging', () {
      expect(SpotifyApiService.nextPageUrl('{"items":[],"next":null}'), isNull);
    });

    test('malformed bodies yield nothing instead of throwing', () {
      expect(SpotifyApiService.parseTrackPage('not json'), isEmpty);
      expect(SpotifyApiService.nextPageUrl('not json'), isNull);
      expect(SpotifyApiService.parseTrackPage('{"items":"wrong"}'), isEmpty);
    });

    test('parses playlist summaries and tolerates missing art', () {
      const body = '''
      {"items":[
        {"id":"p1","name":"Road Trip","images":[{"url":"http://c/1.jpg"}],
         "tracks":{"total":42}},
        {"id":"p2","name":"No Art","images":[],"tracks":{"total":0}},
        {"id":"","name":"Skipped"}
      ]}
      ''';
      final list = SpotifyApiService.parsePlaylistPage(body);
      expect(list.length, 2);
      expect(list.first.name, 'Road Trip');
      expect(list.first.trackCount, 42);
      expect(list[1].coverUrl, isNull);
    });
  });
}
