import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/listenbrainz_service.dart';
import 'package:harmonymusic/utils/secure_credentials.dart';
import 'package:hive/hive.dart';

const _song =
    MediaItem(id: 'a', title: 'Song A', artist: 'Artist', album: 'Album');

DioException _offline() => DioException(
    requestOptions: RequestOptions(path: '/'),
    type: DioExceptionType.connectionError);

DioException _status(int code) => DioException(
    requestOptions: RequestOptions(path: '/'),
    response:
        Response(requestOptions: RequestOptions(path: '/'), statusCode: code),
    type: DioExceptionType.badResponse);

DateTime _at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sent = <Map<String, dynamic>>[];
  Object? failWith;

  setUp(() async {
    await Hive.openBox(ListenBrainzService.pendingBox, bytes: Uint8List(0));
    await SecureCredentials.set('listenBrainzToken', 'tok');
    sent.clear();
    failWith = null;
    ListenBrainzService.send = (body) async {
      if (failWith != null) throw failWith!;
      sent.add(body);
    };
  });
  tearDown(() async {
    SecureCredentials.resetForTest();
    await Hive.close();
  });

  Box pending() => Hive.box(ListenBrainzService.pendingBox);
  List<Object?> keptTimes() =>
      [for (final l in pending().values) (l as Map)['listened_at']];

  test('a listen goes on its own: when, and what was played', () async {
    await ListenBrainzService.submitListen(_song, now: _at(1700000000));
    expect(sent.single['listen_type'], 'single');
    final listen = (sent.single['payload'] as List).single as Map;
    expect(listen['listened_at'], 1700000000);
    expect(listen['track_metadata']['track_name'], 'Song A');
    expect(listen['track_metadata']['artist_name'], 'Artist');
    expect(listen['track_metadata']['release_name'], 'Album');
  });

  test('offline: kept, then sent with the next listen that goes', () async {
    failWith = _offline();
    await ListenBrainzService.submitListen(_song, now: _at(1700000000));
    await ListenBrainzService.submitListen(_song, now: _at(1700000300));
    expect(sent, isEmpty);
    expect(keptTimes(), [1700000000, 1700000300]);

    failWith = null;
    await ListenBrainzService.submitListen(_song, now: _at(1700000600));
    expect(sent.map((b) => b['listen_type']), ['single', 'import']);
    expect([
      for (final l in sent.last['payload'] as List) (l as Map)['listened_at']
    ], [
      1700000000,
      1700000300
    ]);
    expect(pending().isEmpty, isTrue);
  });

  test('ListenBrainz down: kept too; turned down (a bad token): not kept',
      () async {
    failWith = _status(503);
    await ListenBrainzService.submitListen(_song, now: _at(1));
    failWith = _status(401);
    await ListenBrainzService.submitListen(_song, now: _at(2));
    expect(keptTimes(), [1]);
  });

  test(
      'playing now: the song without a time, never kept; and what was kept goes',
      () async {
    failWith = _offline();
    await ListenBrainzService.submitListen(_song, now: _at(1));
    await ListenBrainzService.playingNow(_song);
    expect(keptTimes(), [1]);

    failWith = null;
    await ListenBrainzService.playingNow(_song);
    expect(sent.map((b) => b['listen_type']), ['playing_now', 'import']);
    final now = (sent.first['payload'] as List).single as Map;
    expect(now.containsKey('listened_at'), isFalse);
    expect(now['track_metadata']['track_name'], 'Song A');
    expect(pending().isEmpty, isTrue);
  });

  test('without a token nothing is sent or kept', () async {
    SecureCredentials.resetForTest();
    await ListenBrainzService.submitListen(_song);
    await ListenBrainzService.playingNow(_song);
    expect(sent, isEmpty);
    expect(pending().isEmpty, isTrue);
  });

  test('so many kept at most, the oldest go; none without an artist', () async {
    ListenBrainzService.maxKept = 2;
    addTearDown(() => ListenBrainzService.maxKept = 1000);
    failWith = _offline();
    for (var i = 1; i <= 3; i++) {
      await ListenBrainzService.submitListen(_song, now: _at(i));
    }
    await ListenBrainzService.submitListen(
        const MediaItem(id: 'b', title: 'No artist'),
        now: _at(4));
    expect(keptTimes(), [2, 3]);
  });
}
