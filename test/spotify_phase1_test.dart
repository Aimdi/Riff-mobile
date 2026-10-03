import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/spotify_api_service.dart';
import 'package:harmonymusic/services/spotify_auth_service.dart';
import 'package:harmonymusic/services/spotify_match.dart';
import 'package:harmonymusic/services/spotify_match_store.dart';
import 'package:harmonymusic/services/spotify_playback.dart';
import 'package:harmonymusic/utils/secure_credentials.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

/// Answers requests from a script, recording what was asked.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions o) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancelFuture) {
    requests.add(o);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody res(int status, [Object body = '{}', Map<String, String>? h]) =>
    ResponseBody.fromString(body is String ? body : jsonEncode(body), status,
        headers: {
          for (final e in (h ?? const <String, String>{}).entries)
            e.key: [e.value]
        });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('refresh outcome', () {
    test('invalid_grant and 401 end the session; others may retry', () {
      expect(SpotifyAuthService.classifyRefresh(200, '{}'),
          SpotifyRefreshResult.ok);
      expect(
          SpotifyAuthService.classifyRefresh(
              400, '{"error":"invalid_grant","error_description":"x"}'),
          SpotifyRefreshResult.revoked);
      expect(SpotifyAuthService.classifyRefresh(401, ''),
          SpotifyRefreshResult.revoked);
      expect(
          SpotifyAuthService.classifyRefresh(400, '{"error":"invalid_client"}'),
          SpotifyRefreshResult.failed);
      expect(SpotifyAuthService.classifyRefresh(503, 'down'),
          SpotifyRefreshResult.failed);
    });
  });

  group('auth with storage', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('spotify_auth');
      Hive.init(p.join(tmp.path, 'hive'));
      await Hive.openBox('AppPrefs');
      await SpotifyAuthService.setClientId('client123');
      await SecureCredentials.set(SpotifyAuthService.kAccessToken, 'old');
      await SecureCredentials.set(SpotifyAuthService.kRefreshToken, 'rt');
      SpotifyAuthService.sessionExpired.value = false;
    });
    tearDown(() async {
      await SpotifyAuthService.disconnect();
      await Hive.deleteFromDisk();
      tmp.deleteSync(recursive: true);
    });

    test('concurrent refreshes share one request', () async {
      final gate = Completer<void>();
      final adapter = ScriptedAdapter((o) async {
        await gate.future;
        return res(200, {
          'access_token': 'new',
          'expires_in': 3600,
          'scope': 'user-library-read user-read-recently-played',
        });
      });
      final auth = SpotifyAuthService(dio: Dio()..httpClientAdapter = adapter);
      final a = auth.refresh();
      final b = auth.refresh();
      gate.complete();
      expect(await Future.wait([a, b]), [true, true]);
      expect(adapter.requests.length, 1);
      expect(SpotifyAuthService.accessToken, 'new');
      // The old refresh token is kept when none comes back.
      expect(SpotifyAuthService.refreshToken, 'rt');
      expect(
          SpotifyAuthService.lacksScope('user-read-recently-played'), isFalse);
      expect(SpotifyAuthService.lacksScope('user-top-read'), isTrue);
    });

    test('an expired refresh token signs out and asks to sign in again',
        () async {
      final adapter =
          ScriptedAdapter((o) async => res(400, {'error': 'invalid_grant'}));
      final auth = SpotifyAuthService(dio: Dio()..httpClientAdapter = adapter);
      expect(await auth.refresh(), isFalse);
      expect(SpotifyAuthService.isConnected, isFalse);
      expect(SpotifyAuthService.sessionExpired.value, isTrue);
      // Not retried.
      expect(adapter.requests.length, 1);
    });

    test('a server hiccup keeps the session', () async {
      final adapter = ScriptedAdapter((o) async => res(503, 'busy'));
      final auth = SpotifyAuthService(dio: Dio()..httpClientAdapter = adapter);
      expect(await auth.refresh(), isFalse);
      expect(SpotifyAuthService.isConnected, isTrue);
      expect(SpotifyAuthService.sessionExpired.value, isFalse);
    });
  });

  group('API errors', () {
    test('classification', () {
      expect(classifySpotifyError(401, ''), SpotifyErrorKind.signedOut);
      expect(classifySpotifyError(403, ''), SpotifyErrorKind.forbidden);
      expect(classifySpotifyError(404, ''), SpotifyErrorKind.notFound);
      expect(classifySpotifyError(429, '{"error":{"status":429}}'),
          SpotifyErrorKind.rateLimited);
      expect(
          classifySpotifyError(429,
              '{"error":{"status":429,"message":"Too many requests","reason":"QUOTA_EXCEEDED"}}'),
          SpotifyErrorKind.quotaExceeded);
      expect(classifySpotifyError(502, ''), SpotifyErrorKind.server);
    });

    test('Retry-After and backoff', () {
      expect(parseRetryAfter('7'), const Duration(seconds: 7));
      expect(parseRetryAfter(null), isNull);
      expect(parseRetryAfter('soon'), isNull);
      expect(rateLimitDelay(const Duration(seconds: 3), 0),
          const Duration(seconds: 3));
      expect(rateLimitDelay(null, 0), const Duration(seconds: 1));
      expect(rateLimitDelay(null, 2), const Duration(seconds: 4));
    });

    test('cache freshness', () {
      const ttl = Duration(hours: 6);
      expect(spotifyCacheFresh(1000, 1000 + 60000, ttl), isTrue);
      expect(spotifyCacheFresh(1000, 1000 + ttl.inMilliseconds, ttl), isFalse);
      expect(spotifyCacheFresh(5000, 1000, ttl), isFalse); // clock went back
    });
  });

  group('API client', () {
    late List<Duration> slept;
    var refreshes = 0;
    var token = 't1';

    SpotifyApiService api(ScriptedAdapter adapter, {bool refreshOk = true}) {
      slept = [];
      refreshes = 0;
      token = 't1';
      return SpotifyApiService(
        auth: SpotifyAuthService(),
        dio: Dio()..httpClientAdapter = adapter,
        token: () async => token,
        refresh: () async {
          refreshes++;
          token = 't2';
          return refreshOk;
        },
        sleep: (d) async => slept.add(d),
        useCache: false,
      );
    }

    tearDown(SpotifyApiService.resetCooldown);

    test('a 401 refreshes once and retries with the new token', () async {
      final adapter = ScriptedAdapter((o) async =>
          o.headers['Authorization'] == 'Bearer t2'
              ? res(200, {'id': 'me', 'display_name': 'Me'})
              : res(401));
      final me = await api(adapter).fetchMe();
      expect(me!.name, 'Me');
      expect(refreshes, 1);
      expect(adapter.requests.length, 2);
    });

    test('a 401 after refreshing means signed out', () async {
      final adapter = ScriptedAdapter((o) async => res(401));
      await expectLater(
          api(adapter).fetchMe(),
          throwsA(isA<SpotifyApiException>()
              .having((e) => e.kind, 'kind', SpotifyErrorKind.signedOut)));
      expect(refreshes, 1);
    });

    test('a 429 waits as asked, then succeeds', () async {
      var n = 0;
      final adapter = ScriptedAdapter((o) async => n++ == 0
          ? res(429, '{}', {'retry-after': '2'})
          : res(200, {'id': 'me'}));
      expect((await api(adapter).fetchMe())!.id, 'me');
      expect(slept, [const Duration(seconds: 2)]);
    });

    test('a 429 that persists gives up with rateLimited', () async {
      final adapter =
          ScriptedAdapter((o) async => res(429, '{}', {'retry-after': '1'}));
      await expectLater(
          api(adapter).fetchMe(),
          throwsA(isA<SpotifyApiException>()
              .having((e) => e.kind, 'kind', SpotifyErrorKind.rateLimited)));
      expect(slept.length, 2);
      expect(adapter.requests.length, 3);
    });

    test('a long Retry-After is not waited out in place', () async {
      final adapter =
          ScriptedAdapter((o) async => res(429, '{}', {'retry-after': '120'}));
      await expectLater(
          api(adapter).fetchMe(),
          throwsA(isA<SpotifyApiException>().having(
              (e) => e.retryAfter, 'wait', const Duration(seconds: 120))));
      expect(slept, isEmpty);
    });

    test('QUOTA_EXCEEDED pauses all calls', () async {
      final adapter = ScriptedAdapter((o) async => res(429,
          '{"error":{"status":429,"message":"Too many requests","reason":"QUOTA_EXCEEDED"}}'));
      final client = api(adapter);
      await expectLater(
          client.fetchMe(),
          throwsA(isA<SpotifyApiException>()
              .having((e) => e.kind, 'kind', SpotifyErrorKind.quotaExceeded)));
      await expectLater(
          client.fetchLikedSongs(),
          throwsA(isA<SpotifyApiException>()
              .having((e) => e.kind, 'kind', SpotifyErrorKind.quotaExceeded)));
      expect(adapter.requests.length, 1);
    });

    test('403 is forbidden, not an empty list', () async {
      final adapter = ScriptedAdapter((o) async => res(403));
      await expectLater(
          api(adapter).fetchLikedSongs(),
          throwsA(isA<SpotifyApiException>()
              .having((e) => e.kind, 'kind', SpotifyErrorKind.forbidden)));
    });

    test('playlist contents come from /items, paged', () async {
      final adapter = ScriptedAdapter((o) async {
        final u = o.uri.toString();
        if (u.contains('/items') && !u.contains('offset')) {
          return res(200, {
            'items': [
              {
                'item': {
                  'id': 'a',
                  'name': 'One',
                  'artists': [
                    {'name': 'X'}
                  ],
                  'external_ids': {'isrc': 'usabc1234567'},
                  'album': {
                    'name': 'LP',
                    'images': [
                      {'url': 'https://i/lp.jpg'}
                    ]
                  },
                }
              }
            ],
            'next': 'https://api.spotify.com/v1/playlists/p1/items?offset=50'
          });
        }
        return res(200, {
          'items': [
            {
              'item': {'id': 'b', 'name': 'Two'}
            }
          ],
          'next': null
        });
      });
      final tracks = await api(adapter).fetchPlaylistTracks('p1');
      expect(tracks.map((t) => t.title), ['One', 'Two']);
      expect(tracks.first.isrc, 'USABC1234567');
      expect(tracks.first.album, 'LP');
      expect(tracks.first.artUrl, 'https://i/lp.jpg');
      expect(adapter.requests.first.uri.path, '/v1/playlists/p1/items');
    });

    test('falls back to /tracks where /items is unknown', () async {
      final adapter = ScriptedAdapter((o) async => o.uri.path.endsWith('/items')
          ? res(404)
          : res(200, {
              'items': [
                {
                  'track': {'id': 'a', 'name': 'Old'}
                }
              ]
            }));
      expect(
          (await api(adapter).fetchPlaylistTracks('p1')).single.title, 'Old');
    });

    test('album tracks get the album name and cover', () async {
      final adapter = ScriptedAdapter((o) async => res(200, {
            'id': 'al',
            'name': 'Album',
            'images': [
              {'url': 'https://i/al.jpg'}
            ],
            'tracks': {
              'items': [
                {'id': 't', 'name': 'Track', 'duration_ms': 1000}
              ],
              'next': null
            }
          }));
      final t = (await api(adapter).fetchAlbumTracks('al')).single;
      expect(t.album, 'Album');
      expect(t.artUrl, 'https://i/al.jpg');
    });

    test('search asks for 10 per page', () async {
      final adapter = ScriptedAdapter((o) async => res(200, {
            'tracks': {
              'items': [
                {'id': 't', 'name': 'T'}
              ],
              'next': 'x'
            },
            'albums': {'items': []},
            'artists': {
              'items': [
                {'id': 'ar', 'name': 'Art'}
              ]
            },
          }));
      final page = await api(adapter).search('abc', offset: 10);
      expect(adapter.requests.single.uri.queryParameters['limit'], '10');
      expect(adapter.requests.single.uri.queryParameters['offset'], '10');
      expect(page.tracks.single.title, 'T');
      expect(page.artists.single.name, 'Art');
      expect(page.hasMore, isTrue);
    });

    test('followed artists page under `artists`', () async {
      var n = 0;
      final adapter = ScriptedAdapter((o) async => n++ == 0
          ? res(200, {
              'artists': {
                'items': [
                  {'id': 'a1', 'name': 'One'}
                ],
                'next': 'https://api.spotify.com/v1/me/following?after=a1'
              }
            })
          : res(200, {
              'artists': {
                'items': [
                  {'id': 'a2', 'name': 'Two'}
                ],
                'next': null
              }
            }));
      final list = await api(adapter).fetchFollowedArtists();
      expect(list.map((a) => a.name), ['One', 'Two']);
    });
  });

  group('parsing', () {
    test('playlist summaries: owner, collaboration, item count', () {
      final list = SpotifyApiService.parsePlaylistPage(jsonEncode({
        'items': [
          {
            'id': 'mine',
            'name': 'Mine',
            'owner': {'id': 'me', 'display_name': 'Me'},
            'items': {'total': 12}
          },
          {
            'id': 'collab',
            'name': 'Shared',
            'owner': {'id': 'friend'},
            'collaborative': true
          },
          {
            'id': 'theirs',
            'name': 'Followed',
            'owner': {'id': 'spotify', 'display_name': 'Spotify'}
          },
        ]
      }));
      expect(list[0].trackCount, 12);
      expect(list[0].readableBy('me'), isTrue);
      expect(list[1].readableBy('me'), isTrue);
      expect(list[2].readableBy('me'), isFalse);
      expect(list[2].ownerName, 'Spotify');
      expect(list[0].readableBy(null), isFalse);
    });

    test('saved albums unwrap `album`', () {
      final a = SpotifyApiService.parseAlbum({
        'added_at': 'x',
        'album': {
          'id': 'al',
          'name': 'LP',
          'release_date': '1999-03-01',
          'artists': [
            {'name': 'A'},
            {'name': 'B'}
          ]
        }
      })!;
      expect(a.year, '1999');
      expect(a.artists, 'A, B');
    });
  });

  group('matches', () {
    test('which ids are kept', () {
      expect(cacheableSpotifyId('4uLU6hMCjMI75M1A2tKUQC'), isTrue);
      expect(cacheableSpotifyId('csv_3'), isFalse);
      expect(cacheableSpotifyId(''), isFalse);
    });

    test('a listener\'s pick is never replaced automatically', () {
      expect(mayStoreAutoMatch(null), isTrue);
      expect(mayStoreAutoMatch(const SpotifyMatchEntry(item: {'videoId': 'a'})),
          isTrue);
      expect(
          mayStoreAutoMatch(
              const SpotifyMatchEntry(item: {'videoId': 'a'}, manual: true)),
          isFalse);
    });

    test('store: automatic, then manual, then automatic again', () async {
      final tmp = await Directory.systemTemp.createTemp('spotify_match');
      Hive.init(p.join(tmp.path, 'hive'));
      const id = '4uLU6hMCjMI75M1A2tKUQC';
      const a = MediaItem(id: 'vidA', title: 'A', extras: {});
      const b = MediaItem(id: 'vidB', title: 'B', extras: {});
      await SpotifyMatchStore.putAuto(id, a, 0.8);
      expect(SpotifyMatchStore.get(id)!.videoId, 'vidA');
      await SpotifyMatchStore.putManual(id, b);
      expect(SpotifyMatchStore.get(id)!.manual, isTrue);
      await SpotifyMatchStore.putAuto(id, a, 0.99);
      expect(SpotifyMatchStore.get(id)!.videoId, 'vidB');
      expect(SpotifyMatchStore.itemFor(id)!.id, 'vidB');
      await SpotifyMatchStore.remove(id);
      expect(SpotifyMatchStore.get(id), isNull);
      await Hive.deleteFromDisk();
      tmp.deleteSync(recursive: true);
    });

    test('candidates sort best first, ties keep YouTube Music order', () {
      final sorted = sortCandidates([
        const ScoredCandidate('a', 0.5),
        const ScoredCandidate('b', 0.9),
        const ScoredCandidate('c', 0.5),
      ]);
      expect(sorted.map((c) => c.item), ['b', 'a', 'c']);
    });
  });

  group('play order', () {
    test('from the tapped track to the end', () {
      expect(spotifyPlayOrder(5, 2), [2, 3, 4]);
      expect(spotifyPlayOrder(0, 0), isEmpty);
      expect(spotifyPlayOrder(3, 9), [2]);
    });

    test('shuffle starts with the tapped track and keeps every track', () {
      final order = spotifyPlayOrder(6, 3, shuffle: true);
      expect(order.first, 3);
      expect(order.toSet(), {0, 1, 2, 3, 4, 5});
    });

    test('chunks', () {
      expect(chunked([1, 2, 3, 4, 5], 2), [
        [1, 2],
        [3, 4],
        [5]
      ]);
    });
  });
}
