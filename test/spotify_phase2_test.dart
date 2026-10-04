import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/spotify_api_service.dart';
import 'package:harmonymusic/services/spotify_auth_service.dart';
import 'package:harmonymusic/services/spotify_import_service.dart';
import 'package:harmonymusic/services/spotify_like_sync.dart';
import 'package:harmonymusic/services/spotify_match_store.dart';
import 'package:harmonymusic/services/spotify_radio.dart';
import 'package:harmonymusic/utils/secure_credentials.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

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

ResponseBody res(int status, [Object body = '{}']) =>
    ResponseBody.fromString(body is String ? body : jsonEncode(body), status);

SpotifyApiService apiWith(ScriptedAdapter a) => SpotifyApiService(
      auth: SpotifyAuthService(),
      dio: Dio()..httpClientAdapter = a,
      token: () async => 'tok',
      refresh: () async => false,
      sleep: (_) async {},
      useCache: false,
    );

SpotifyTrackRef tr(String id, String artist, {String? title}) =>
    SpotifyTrackRef(id: id, title: title ?? 'Song $id', artists: artist);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('like queue', () {
    test('a like and an unlike before sending cancel out', () {
      var q = queueLikeOp({}, 'v1', LikeOp.save);
      expect(q, {'v1': LikeOp.save});
      q = queueLikeOp(q, 'v1', LikeOp.remove);
      expect(q, isEmpty);
      q = queueLikeOp(q, 'v2', LikeOp.remove);
      q = queueLikeOp(q, 'v2', LikeOp.remove);
      expect(q, {'v2': LikeOp.remove});
    });

    test('plan: save new, skip liked, remove only what Riff added', () {
      final plan = planLikeFlush(
        pending: {
          'new': LikeOp.save,
          'alreadyLiked': LikeOp.save,
          'ours': LikeOp.remove,
          'theirs': LikeOp.remove,
          'unknown': LikeOp.save,
          'notOnSpotify': LikeOp.save,
          'dupe': LikeOp.save,
        },
        spotifyIdFor: {
          'new': 's1',
          'alreadyLiked': 's2',
          'ours': 's3',
          'theirs': 's4',
          'notOnSpotify': '',
          'dupe': 's1',
        },
        addedByRiff: {'s3'},
        likedOnSpotify: {'s2', 's4'},
      );
      expect(plan.save, ['s1']);
      expect(plan.remove, ['s3']);
      expect(plan.done,
          unorderedEquals(['alreadyLiked', 'theirs', 'notOnSpotify']));
    });

    test('a Spotify search result must really be the song', () {
      const song = MediaItem(
          id: 'v',
          title: 'Bohemian Rhapsody',
          artist: 'Queen',
          duration: Duration(seconds: 354));
      final hit = pickSpotifyTrackFor(song, [
        const SpotifyTrackRef(
            id: 'x',
            title: 'Radio Ga Ga',
            artists: 'Queen',
            durationMs: 343000),
        const SpotifyTrackRef(
            id: 'y',
            title: 'Bohemian Rhapsody - Remastered 2011',
            artists: 'Queen',
            durationMs: 354000),
      ]);
      expect(hit?.id, 'y');
      expect(
          pickSpotifyTrackFor(song, [
            const SpotifyTrackRef(
                id: 'z', title: 'Something Else', artists: 'Someone')
          ]),
          isNull);
    });
  });

  group('radio', () {
    test('at most 3 songs per artist', () {
      final top = [for (var i = 0; i < 10; i++) tr('a$i', 'Alpha')];
      final radio = buildSpotifyRadio(
          top: top,
          liked: [for (var i = 0; i < 5; i++) tr('b$i', 'Beta')],
          random: Random(1));
      expect(radio.where((t) => t.artists == 'Alpha').length, 3);
      expect(radio.where((t) => t.artists == 'Beta').length, 3);
    });

    test('the same artist twice in a row only when unavoidable', () {
      final spread = spreadArtists([
        tr('1', 'A'),
        tr('2', 'A'),
        tr('3', 'B'),
        tr('4', 'B'),
        tr('5', 'C'),
      ]);
      for (var i = 1; i < spread.length; i++) {
        expect(
            primaryArtistOf(spread[i]), isNot(primaryArtistOf(spread[i - 1])));
      }
    });

    test('duplicates across sources count once', () {
      expect(
          mergeUnique([
            [tr('1', 'A'), tr('2', 'B')],
            [tr('1', 'A')],
          ]).length,
          2);
    });

    test('seeded: the song first, then its artist and genre neighbours', () {
      final seed = tr('seed', 'Radiohead', title: 'Karma Police');
      final radio = buildSpotifyRadio(
        top: [
          tr('pop1', 'Pop Star'),
          tr('rh1', 'Radiohead'),
          tr('alt1', 'Portishead'),
          tr('pop2', 'Pop Star B'),
        ],
        liked: [tr('rh2', 'Radiohead'), tr('alt2', 'Massive Attack')],
        seed: seed,
        genresByArtist: {
          'radiohead': {'alternative rock', 'art rock'},
          'portishead': {'trip hop', 'art rock'},
          'massive attack': {'trip hop'},
          'pop star': {'pop'},
        },
        random: Random(3),
      );
      expect(radio.first.id, 'seed');
      final pos = {for (var i = 0; i < radio.length; i++) radio[i].id: i};
      // Portishead shares a genre with Radiohead; the pop songs don't.
      expect(pos['alt1']!, lessThan(pos['pop1']!));
      expect(pos['alt1']!, lessThan(pos['pop2']!));
      // Radiohead, at most 3 including the seed.
      expect(radio.where((t) => t.artists == 'Radiohead').length, 3);
    });

    test('size limit and empty input', () {
      expect(
          buildSpotifyRadio(
                  top: [for (var i = 0; i < 80; i++) tr('$i', 'Artist $i')],
                  size: 50)
              .length,
          50);
      expect(buildSpotifyRadio(top: const []), isEmpty);
    });
  });

  group('library writes', () {
    tearDown(SpotifyApiService.resetCooldown);

    test('PUT /me/library with track URIs, in batches of 40', () async {
      final adapter = ScriptedAdapter((o) async => res(200, ''));
      await apiWith(adapter).saveTracks([for (var i = 0; i < 41; i++) 'id$i']);
      expect(adapter.requests.length, 2);
      final first = adapter.requests.first;
      expect(first.method, 'PUT');
      expect(first.uri.path, '/v1/me/library');
      final uris = first.uri.queryParameters['uris']!.split(',');
      expect(uris.length, 40);
      expect(uris.first, 'spotify:track:id0');
    });

    test('DELETE removes; 204 is fine', () async {
      final adapter = ScriptedAdapter((o) async => res(204, ''));
      await apiWith(adapter).removeTracks(['a', 'b']);
      expect(adapter.requests.single.method, 'DELETE');
    });

    test('falls back to /me/tracks where /me/library is unknown', () async {
      final adapter = ScriptedAdapter((o) async =>
          o.uri.path.endsWith('/me/library') ? res(404) : res(200, ''));
      await apiWith(adapter).saveTracks(['a', 'b']);
      expect(adapter.requests.last.uri.path, '/v1/me/tracks');
      expect(adapter.requests.last.uri.queryParameters['ids'], 'a,b');
    });

    test('artists carry genres', () {
      final a = SpotifyApiService.parseArtist({
        'id': 'x',
        'name': 'X',
        'genres': ['trip hop', '']
      })!;
      expect(a.genres, ['trip hop']);
    });
  });

  group('like sync with storage', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('spotify_like');
      Hive.init(p.join(tmp.path, 'hive'));
      await Hive.openBox('AppPrefs');
      await SpotifyAuthService.setClientId('cid');
      await SecureCredentials.set(SpotifyAuthService.kAccessToken, 'a');
      await SecureCredentials.set(SpotifyAuthService.kRefreshToken, 'r');
      await Hive.box('AppPrefs')
          .put('spotifyGrantedScopes', 'user-library-read user-library-modify');
    });
    tearDown(() async {
      await SpotifyAuthService.disconnect();
      await Hive.deleteFromDisk();
      tmp.deleteSync(recursive: true);
    });

    test('write access is asked for only while like sync is on', () async {
      expect(SpotifyAuthService.requestedScopes,
          isNot(contains(SpotifyAuthService.libraryWriteScope)));
      await SpotifyLikeSync.setEnabled(true);
      expect(SpotifyAuthService.requestedScopes,
          contains(SpotifyAuthService.libraryWriteScope));
      await SpotifyLikeSync.setEnabled(false);
    });

    test('like, flush, unlike, flush; songs liked on Spotify are left alone',
        () async {
      await SpotifyLikeSync.setEnabled(true);
      const song = MediaItem(id: 'vid1', title: 'One', artist: 'A', extras: {});
      const theirs =
          MediaItem(id: 'vid2', title: 'Two', artist: 'B', extras: {});
      await SpotifyMatchStore.putAuto('sp1', song, 0.9);
      await SpotifyMatchStore.putAuto('sp2', theirs, 0.9);

      final calls = <String>[];
      final adapter = ScriptedAdapter((o) async {
        if (o.method == 'GET') {
          // Liked Songs on Spotify: sp2 only.
          return res(200, {
            'items': [
              {
                'track': {'id': 'sp2', 'name': 'Two'}
              }
            ]
          });
        }
        calls.add('${o.method} ${o.uri.queryParameters['uris']}');
        return res(200, '');
      });
      final api = apiWith(adapter);

      await SpotifyLikeSync.onFavorite(song, add: true);
      await SpotifyLikeSync.onFavorite(theirs, add: true);
      await SpotifyLikeSync.flush(api: api);
      expect(calls, ['PUT spotify:track:sp1']);
      expect(SpotifyLikeSync.pending.value, 0);

      // Unliking in Riff takes out only what Riff put in.
      await SpotifyLikeSync.onFavorite(song, add: false);
      await SpotifyLikeSync.onFavorite(theirs, add: false);
      await SpotifyLikeSync.flush(api: api);
      expect(calls, ['PUT spotify:track:sp1', 'DELETE spotify:track:sp1']);
      expect(SpotifyLikeSync.pending.value, 0);
      await SpotifyLikeSync.setEnabled(false);
    });

    test('nothing is queued while off, or while importing', () async {
      const song = MediaItem(id: 'v', title: 'T');
      await SpotifyLikeSync.onFavorite(song, add: true);
      expect(SpotifyLikeSync.pending.value, 0);
      await SpotifyLikeSync.setEnabled(true);
      await SpotifyLikeSync.quietly(
          () => SpotifyLikeSync.onFavorite(song, add: true));
      expect(SpotifyLikeSync.pending.value, 0);
      await SpotifyLikeSync.setEnabled(false);
    });
  });
}
