import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/spotify_api_service.dart';
import 'package:harmonymusic/services/spotify_auth_service.dart';
import 'package:harmonymusic/services/spotify_connect.dart';
import 'package:harmonymusic/services/spotify_connect_models.dart';
import 'package:harmonymusic/services/spotify_import_service.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions o, String body) handler;
  final requests = <(RequestOptions, String)>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body,
      Future<void>? cancelFuture) async {
    final bytes = <int>[];
    if (body != null) {
      await for (final c in body) {
        bytes.addAll(c);
      }
    }
    final text = utf8.decode(bytes);
    requests.add((o, text));
    return handler(o, text);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody res(int status, [Object body = '']) =>
    ResponseBody.fromString(body is String ? body : jsonEncode(body), status);

SpotifyApiService apiWith(ScriptedAdapter a) => SpotifyApiService(
      auth: SpotifyAuthService(),
      dio: Dio()..httpClientAdapter = a,
      token: () async => 'tok',
      refresh: () async => false,
      sleep: (_) async {},
      useCache: false,
    );

const premiumBody =
    '{"error":{"status":403,"message":"Player command failed: Premium required","reason":"PREMIUM_REQUIRED"}}';
const noDeviceBody =
    '{"error":{"status":404,"message":"Player command failed: No active device found","reason":"NO_ACTIVE_DEVICE"}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('errors', () {
    test('Premium and no-device answers get their own kinds', () {
      expect(classifySpotifyError(403, premiumBody),
          SpotifyErrorKind.premiumRequired);
      expect(classifySpotifyError(404, noDeviceBody),
          SpotifyErrorKind.noActiveDevice);
      expect(classifySpotifyError(403, '{}'), SpotifyErrorKind.forbidden);
      expect(classifySpotifyError(404, ''), SpotifyErrorKind.notFound);
      expect(spotifyErrorReason(noDeviceBody), 'NO_ACTIVE_DEVICE');
      expect(spotifyErrorReason('nope'), isNull);
    });
  });

  group('parsing', () {
    test('devices: volume only when it can be set', () {
      final list = parseDevices(jsonEncode({
        'devices': [
          {
            'id': 'phone',
            'name': 'Pixel',
            'type': 'Smartphone',
            'is_active': true,
            'volume_percent': 40,
            'supports_volume': true
          },
          {
            'id': 'tv',
            'name': 'TV',
            'type': 'TV',
            'is_restricted': true,
            'volume_percent': 10,
            'supports_volume': false
          },
          {'name': 'no id'},
        ]
      }));
      expect(list.length, 2);
      expect(list[0].isActive, isTrue);
      expect(list[0].volumePercent, 40);
      expect(list[1].isRestricted, isTrue);
      expect(list[1].volumePercent, isNull);
    });

    test('playback state; nothing playing is null', () {
      final s = parsePlaybackState(
          jsonEncode({
            'is_playing': true,
            'progress_ms': 61000,
            'shuffle_state': true,
            'device': {'id': 'd', 'name': 'Desk'},
            'item': {
              'id': 't',
              'name': 'Song',
              'duration_ms': 200000,
              'artists': [
                {'name': 'A'}
              ]
            }
          }),
          parseTrack: (i) => SpotifyApiService.parseTrackItem(i))!;
      expect(s.isPlaying, isTrue);
      expect(s.progressMs, 61000);
      expect(s.track!.title, 'Song');
      expect(s.device!.name, 'Desk');
      expect(parsePlaybackState('', parseTrack: (_) => null), isNull);
    });
  });

  group('choosing and building', () {
    const a = SpotifyDevice(id: 'a', name: 'A');
    const b = SpotifyDevice(id: 'b', name: 'B', isActive: true);
    const r = SpotifyDevice(id: 'r', name: 'R', isRestricted: true);

    test('device: picked before, else active, else first usable', () {
      expect(pickTargetDevice([a, b], preferredId: 'a')!.id, 'a');
      expect(pickTargetDevice([a, b], preferredId: 'gone')!.id, 'b');
      expect(pickTargetDevice([r, a])!.id, 'a');
      expect(pickTargetDevice([r]), isNull);
      expect(pickTargetDevice([r], preferredId: 'r'), isNull);
    });

    test('a playlist or album plays as itself', () {
      expect(connectPlayBody(contextUri: 'spotify:album:x', start: 3), {
        'context_uri': 'spotify:album:x',
        'offset': {'position': 3}
      });
      expect(connectPlayBody(contextUri: 'spotify:playlist:p'),
          {'context_uri': 'spotify:playlist:p'});
    });

    test('other lists play as track URIs, long ones as a window', () {
      expect(connectPlayBody(trackIds: ['a', 'b'], start: 1), {
        'uris': ['spotify:track:a', 'spotify:track:b'],
        'offset': {'position': 1}
      });
      final ids = [for (var i = 0; i < 300; i++) 't$i'];
      final body = connectPlayBody(trackIds: ids, start: 250);
      final uris = body['uris'] as List;
      expect(uris.length, connectMaxUris);
      final pos = (body['offset'] as Map)['position'] as int;
      expect(uris[pos], 'spotify:track:t250');
      expect(connectPlayBody(trackIds: const []), isEmpty);
    });

    test('rows without a Spotify id are left out, start follows', () {
      final (ids, at) = spotifyIdsFrom(const [
        SpotifyTrackRef(id: 'csv_1', title: 'x', artists: ''),
        SpotifyTrackRef(id: 's1', title: 'a', artists: ''),
        SpotifyTrackRef(id: '', title: 'b', artists: ''),
        SpotifyTrackRef(id: 's2', title: 'c', artists: ''),
      ], 3);
      expect(ids, ['s1', 's2']);
      expect(at, 1);
    });
  });

  group('commands', () {
    tearDown(SpotifyApiService.resetCooldown);

    test('nothing playing answers 204', () async {
      final adapter = ScriptedAdapter((o, b) async => res(204));
      expect(await apiWith(adapter).fetchPlaybackState(), isNull);
    });

    test('play sends JSON to the chosen device', () async {
      final adapter = ScriptedAdapter((o, b) async => res(204));
      await apiWith(adapter).play(
          deviceId: 'dev1',
          body: connectPlayBody(contextUri: 'spotify:album:x'));
      final (o, body) = adapter.requests.single;
      expect(o.method, 'PUT');
      expect(o.uri.path, '/v1/me/player/play');
      expect(o.uri.queryParameters['device_id'], 'dev1');
      expect(jsonDecode(body), {'context_uri': 'spotify:album:x'});
    });

    test('controls hit their endpoints', () async {
      final adapter = ScriptedAdapter((o, b) async => res(204));
      final api = apiWith(adapter);
      await api.pause(deviceId: 'd');
      await api.next();
      await api.previous();
      await api.seek(5000);
      await api.setVolume(150);
      expect([
        for (final r in adapter.requests) '${r.$1.method} ${r.$1.uri.path}'
      ], [
        'PUT /v1/me/player/pause',
        'POST /v1/me/player/next',
        'POST /v1/me/player/previous',
        'PUT /v1/me/player/seek',
        'PUT /v1/me/player/volume',
      ]);
      expect(adapter.requests[3].$1.uri.queryParameters['position_ms'], '5000');
      expect(
          adapter.requests[4].$1.uri.queryParameters['volume_percent'], '100');
    });

    test('Premium needed is reported, not retried', () async {
      final adapter = ScriptedAdapter((o, b) async => res(403, premiumBody));
      await expectLater(
          apiWith(adapter).play(deviceId: 'd'),
          throwsA(isA<SpotifyApiException>().having(
              (e) => e.kind, 'kind', SpotifyErrorKind.premiumRequired)));
      expect(adapter.requests.length, 1);
    });
  });

  group('with storage', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('spotify_connect');
      Hive.init(p.join(tmp.path, 'hive'));
      await Hive.openBox('AppPrefs');
    });
    tearDown(() async {
      await Hive.deleteFromDisk();
      tmp.deleteSync(recursive: true);
    });

    test('playback permissions are asked for only while Connect is on',
        () async {
      expect(SpotifyAuthService.requestedScopes,
          isNot(contains('user-modify-playback-state')));
      await SpotifyConnect.setEnabled(true);
      expect(SpotifyAuthService.requestedScopes,
          containsAll(SpotifyAuthService.playbackScopes));
      await SpotifyConnect.setEnabled(false);
    });

    test('no active device: wake it with a transfer, then play', () async {
      var plays = 0;
      final adapter = ScriptedAdapter((o, b) async {
        if (o.uri.path.endsWith('/play')) {
          return plays++ == 0 ? res(404, noDeviceBody) : res(204);
        }
        return res(204);
      });
      await SpotifyConnect.playTracks('dev9',
          tracks: const [
            SpotifyTrackRef(id: 's1', title: 'a', artists: ''),
            SpotifyTrackRef(id: 's2', title: 'b', artists: ''),
          ],
          start: 1,
          client: apiWith(adapter));
      final calls = [
        for (final r in adapter.requests) '${r.$1.method} ${r.$1.uri.path}'
      ];
      expect(calls, [
        'PUT /v1/me/player/play',
        'PUT /v1/me/player',
        'PUT /v1/me/player/play',
      ]);
      expect(jsonDecode(adapter.requests[1].$2), {
        'device_ids': ['dev9'],
        'play': false
      });
      expect(jsonDecode(adapter.requests[2].$2)['offset'], {'position': 1});
      expect(SpotifyConnect.preferredDeviceId, 'dev9');
    });
  });
}
