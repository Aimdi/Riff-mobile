import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/last_fm_service.dart';
import 'package:harmonymusic/ui/screens/Settings/last_fm_dialog.dart';
import 'package:harmonymusic/utils/secure_credentials.dart';
import 'package:hive/hive.dart';

/// A YouTube Music song, as Riff keeps it: its artists listed apart.
const _song = MediaItem(
  id: 'v1',
  title: 'Jóga',
  artist: 'Björk, Someone Else',
  album: 'Homogenic',
  duration: Duration(minutes: 5, seconds: 5),
  extras: {
    'artists': [
      {'name': 'Björk', 'id': 'UC1'},
      {'name': 'Someone Else', 'id': 'UC2'},
    ],
  },
);

const _now = 1700000000;

DioException _offline() => DioException(
    requestOptions: RequestOptions(path: '/'),
    type: DioExceptionType.connectionError);

/// Last.fm scrobbling, as Spotify, Metrolist and InnerTune have it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <Map<String, String>>[];
  // What Last.fm answers next (a Map), or throws (an error); else {}.
  final answers = <Object>[];

  Future<dynamic> fakeLastFm(Map<String, String> form) async {
    calls.add(form);
    if (answers.isEmpty) return <String, dynamic>{};
    final answer = answers.removeAt(0);
    if (answer is Exception) throw answer;
    return answer;
  }

  Future<void> connected() async {
    answers.add({
      'session': {'name': 'Me', 'key': 'sess', 'subscriber': 0}
    });
    await LastFmService.connect('me', 'pw', apiKey: 'key', secret: 's3cret');
    // What was kept goes once connected: done before going on.
    await LastFmService.sendKept();
    calls.clear();
  }

  Box pending() => Hive.box(LastFmService.pendingBox);

  setUp(() async {
    // Secure storage answers at once (the widget test's clock is fake).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => null);
    await Hive.openBox(LastFmService.pendingBox, bytes: Uint8List(0));
    calls.clear();
    answers.clear();
    LastFmService.transport = fakeLastFm;
    LastFmService.clock =
        () => DateTime.fromMillisecondsSinceEpoch(_now * 1000);
  });

  tearDown(() async {
    LastFmService.clock = DateTime.now;
    SecureCredentials.resetForTest();
    await Hive.close();
  });

  test('signed as Last.fm asks: names in order, then the secret, as MD5', () {
    expect(
        LastFmService.signature({
          'username': 'me',
          'password': 'pw',
          'method': 'auth.getMobileSession',
          'api_key': 'key',
          // Not signed.
          'format': 'json',
        }, 's3cret'),
        '233cea53c8cf2f60c327ce0ed16bf31c');
    expect(
        LastFmService.signature({
          'track[0]': 'Jóga',
          'artist[0]': 'Björk',
          'timestamp[0]': '1700000000',
          'method': 'track.scrobble',
          'sk': 'sess',
          'api_key': 'key',
        }, 's3cret'),
        'aa067fabcd6c81a480277b50e7769f19');
  });

  test('connecting: the password goes once, only the session is kept',
      () async {
    expect(LastFmService.enabled, isFalse);
    answers.add({
      'session': {'name': 'Me', 'key': 'sess', 'subscriber': 0}
    });
    await LastFmService.connect(' me ', 'pw', apiKey: 'key', secret: 's3cret');
    final form = calls.single;
    expect(form['method'], 'auth.getMobileSession');
    expect(form['username'], 'me');
    expect(form['password'], 'pw');
    expect(form['api_key'], 'key');
    expect(form['format'], 'json');
    expect(form.containsKey('sk'), isFalse);
    expect(form['api_sig'],
        LastFmService.signature(Map.of(form)..remove('api_sig'), 's3cret'));

    expect(LastFmService.enabled, isTrue);
    expect(LastFmService.user, 'Me');
    for (final key in [
      LastFmService.sessionKey,
      LastFmService.userKey,
      LastFmService.apiKeyKey,
      LastFmService.secretKey,
    ]) {
      expect(SecureCredentials.get(key), isNot('pw'));
    }
  });

  test('a wrong password: told so, and not connected', () async {
    answers.add({'error': 4, 'message': 'Authentication Failed'});
    await expectLater(
        LastFmService.connect('me', 'nope', apiKey: 'key', secret: 's3cret'),
        throwsA(
            isA<LastFmError>().having((e) => e.badLogin, 'badLogin', isTrue)));
    expect(LastFmService.enabled, isFalse);
    // A key Last.fm doesn't take.
    expect(const LastFmError(10, '').badKey, isTrue);
    expect(const LastFmError(13, '').badKey, isTrue);
  });

  test('not connected: nothing goes to Last.fm', () async {
    await LastFmService.playingNow(_song);
    await LastFmService.scrobble(_song, listened: const Duration(minutes: 3));
    expect(calls, isEmpty);
    expect(pending().isEmpty, isTrue);
  });

  test('the song playing shows as scrobbling now: its first artist', () async {
    await connected();
    await LastFmService.playingNow(_song);
    final form = calls.single;
    expect(form['method'], 'track.updateNowPlaying');
    expect(form['artist'], 'Björk');
    expect(form['track'], 'Jóga');
    expect(form['album'], 'Homogenic');
    expect(form['duration'], '305');
    expect(form['sk'], 'sess');
    expect(form['api_sig'],
        LastFmService.signature(Map.of(form)..remove('api_sig'), 's3cret'));
  });

  test('a song listened to: scrobbled as of when it started', () async {
    await connected();
    await LastFmService.scrobble(_song, listened: const Duration(minutes: 4));
    final form = calls.single;
    expect(form['method'], 'track.scrobble');
    expect(form['artist[0]'], 'Björk');
    expect(form['track[0]'], 'Jóga');
    expect(form['album[0]'], 'Homogenic');
    expect(form['duration[0]'], '305');
    expect(form['timestamp[0]'], '${_now - 240}');
  });

  test('a YouTube channel for an artist goes by the artist\'s name', () {
    const video =
        MediaItem(id: 'v2', title: 'Song', artist: 'Some Band - Topic');
    expect(LastFmService.trackOf(video)['artist'], 'Some Band');
    expect(LastFmService.trackOf(video).containsKey('album'), isFalse);
  });

  test('offline: kept, then sent with the next scrobble that goes', () async {
    await connected();
    answers.addAll([_offline(), _offline()]);
    await LastFmService.scrobble(_song, listened: const Duration(minutes: 4));
    await LastFmService.scrobble(_song, listened: const Duration(minutes: 1));
    expect(pending().length, 2);

    calls.clear();
    await LastFmService.scrobble(_song, listened: const Duration(seconds: 30));
    expect(calls.length, 2);
    final kept = calls.last;
    expect(kept['timestamp[0]'], '${_now - 240}');
    expect(kept['timestamp[1]'], '${_now - 60}');
    expect(kept['artist[1]'], 'Björk');
    expect(pending().isEmpty, isTrue);
  });

  test('Last.fm busy: kept; turned down: let go', () async {
    await connected();
    answers.add(const LastFmError(16, 'Temporarily unavailable'));
    await LastFmService.scrobble(_song, listened: const Duration(minutes: 4));
    expect(pending().length, 1);
    answers.add(const LastFmError(6, 'Invalid parameters'));
    await LastFmService.scrobble(_song, listened: const Duration(minutes: 4));
    expect(pending().length, 1);
  });

  test('kept a long time: what Last.fm wouldn\'t take is let go; 50 a time',
      () async {
    await connected();
    await pending().add({
      'artist': 'Old',
      'track': 'Song',
      'timestamp': '${_now - const Duration(days: 15).inSeconds}',
    });
    for (var i = 0; i < 60; i++) {
      await pending().add({
        'artist': 'Artist',
        'track': 'Song $i',
        'timestamp': '${_now - 3600 + i}',
      });
    }
    await LastFmService.sendKept();
    expect(calls.length, 2);
    final sent = [
      for (final call in calls)
        for (var i = 0; call.containsKey('track[$i]'); i++) call['track[$i]']
    ];
    expect(sent, [for (var i = 0; i < 60; i++) 'Song $i']);
    expect(calls.every((call) => !call.containsKey('track[50]')), isTrue);
    expect(calls.any((call) => call.containsValue('Old')), isFalse);
    expect(pending().isEmpty, isTrue);
  });

  test('access taken back on last.fm: not connected anymore', () async {
    await connected();
    answers.add(const LastFmError(9, 'Invalid session key'));
    await LastFmService.scrobble(_song, listened: const Duration(minutes: 4));
    expect(LastFmService.enabled, isFalse);
    expect(pending().isEmpty, isTrue);
    // Its name stays, to sign in again.
    expect(LastFmService.lastUser, 'Me');
  });

  test('Disconnect: scrobbling stops, what was kept goes', () async {
    await connected();
    answers.add(_offline());
    await LastFmService.scrobble(_song, listened: const Duration(minutes: 4));
    expect(pending().length, 1);
    await LastFmService.disconnect();
    expect(LastFmService.enabled, isFalse);
    expect(pending().isEmpty, isTrue);
  });

  testWidgets('the Settings dialog connects, and then says to whom',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog(
              context: context, builder: (_) => const LastFmDialog()),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final connect = find.widgetWithText(TextButton, 'lastFmConnect');
    expect(tester.widget<TextButton>(connect).onPressed, isNull);
    final fields = find.byType(TextField);
    // This build has no API key of its own: yours is asked for.
    expect(fields, findsNWidgets(4));
    await tester.enterText(fields.at(0), 'me');
    await tester.enterText(fields.at(1), 'pw');
    await tester.enterText(fields.at(2), 'key');
    await tester.enterText(fields.at(3), 's3cret');
    await tester.pump();
    expect(tester.widget<TextButton>(connect).onPressed, isNotNull);

    // A wrong password first.
    answers.add({'error': 4, 'message': 'Authentication Failed'});
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(find.text('lastFmBadLogin'), findsOneWidget);

    answers.add({
      'session': {'name': 'Me', 'key': 'sess'}
    });
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(LastFmService.user, 'Me');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('disconnect'), findsOneWidget);
    await tester.tap(find.text('disconnect'));
    await tester.pumpAndSettle();
    expect(LastFmService.enabled, isFalse);
  });
}
