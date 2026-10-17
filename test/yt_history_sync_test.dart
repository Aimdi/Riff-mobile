import 'dart:math';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/private_session.dart';
import 'package:harmonymusic/services/yt_history_sync.dart';
import 'package:harmonymusic/services/yt_playback_tracking.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/yt_history_sync_tile.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/utils/secure_credentials.dart';
import 'package:hive/hive.dart';

const _tracking = 'https://s.youtube.com/api/stats/playback?cl=7&docid='
    'XFkzRNyygfk&ei=abc&ns=yt&plid=p1&el=detailpage&len=239&of=xyz&vm=v1';

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final ytConnected = true.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What you play in Riff in your YouTube Music history, as YouTube Music's
/// own app (and Metrolist, InnerTune) count plays there.
void main() {
  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
  });
  tearDown(() async {
    await PrivateSession.stop();
    SecureCredentials.resetForTest();
    Get.reset();
    await Hive.close();
  });

  group('the play counted, as YouTube Music\'s web player counts it', () {
    test('a nonce for each playback', () {
      final cpn = ytCpn(Random(7));
      expect(cpn, hasLength(16));
      expect(RegExp(r'^[A-Za-z0-9_-]{16}$').hasMatch(cpn), isTrue);
      expect(ytCpn(), isNot(ytCpn()));
    });

    test('its tracking address on music.youtube.com, with the client', () {
      final url = ytPlaybackUrl(_tracking, cpn: 'NONCE');
      expect(url.scheme, 'https');
      expect(url.host, 'music.youtube.com');
      expect(url.path, '/api/stats/playback');
      expect(url.queryParameters, {
        'cl': '7',
        'docid': 'XFkzRNyygfk',
        'ei': 'abc',
        'ns': 'yt',
        'plid': 'p1',
        'el': 'detailpage',
        'len': '239',
        'of': 'xyz',
        'vm': 'v1',
        'ver': '2',
        'c': 'WEB_REMIX',
        'cpn': 'NONCE',
      });
      // Another host is asked as it is.
      expect(
          ytPlaybackUrl('https://www.youtube.com/api/stats/playback?a=1',
                  cpn: 'x')
              .host,
          'www.youtube.com');
    });

    test('asked with the account: the player, then its tracking address',
        () async {
      final music = MusicServices();
      final asked = <RequestOptions>[];
      var tracking = <String, dynamic>{
        'playbackTracking': {
          'videostatsPlaybackUrl': {'baseUrl': _tracking}
        }
      };
      var counted = 204;
      music.dio.interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) {
        asked.add(options);
        handler.resolve(Response(
            requestOptions: options,
            statusCode: options.method == 'GET' ? counted : 200,
            data: options.method == 'GET' ? '' : tracking));
      }));

      // No account: nothing asked.
      expect(await music.registerPlayback('XFkzRNyygfk'), isFalse);
      expect(asked, isEmpty);

      await SecureCredentials.set('ytAuthCookie', 'SAPISID=abc; HSID=def');
      expect(await music.registerPlayback('XFkzRNyygfk'), isTrue);
      expect(asked, hasLength(2));
      expect(asked[0].uri.path, '/youtubei/v1/player');
      expect((asked[0].data as Map)['videoId'], 'XFkzRNyygfk');
      expect(asked[0].headers['authorization'], startsWith('SAPISIDHASH '));
      final count = asked[1];
      expect(count.method, 'GET');
      expect(count.uri.host, 'music.youtube.com');
      expect(count.uri.path, '/api/stats/playback');
      expect(count.uri.queryParameters['docid'], 'XFkzRNyygfk');
      expect(count.uri.queryParameters['c'], 'WEB_REMIX');
      expect(count.uri.queryParameters['ver'], '2');
      expect(count.uri.queryParameters['cpn'], hasLength(16));
      expect(count.headers['authorization'], startsWith('SAPISIDHASH '));
      expect('${count.headers['cookie']}', contains('SAPISID=abc'));

      // Turned down: not counted.
      counted = 403;
      expect(await music.registerPlayback('XFkzRNyygfk'), isFalse);

      // No tracking address: nothing more asked.
      asked.clear();
      tracking = {
        'playabilityStatus': {'status': 'ERROR'}
      };
      expect(await music.registerPlayback('XFkzRNyygfk'), isFalse);
      expect(asked, hasLength(1));
    });
  });

  group('what plays', () {
    late List<String> sent;
    late bool connected;

    setUp(() {
      sent = [];
      connected = true;
      YtHistorySync.connected = () => connected;
      YtHistorySync.send = (videoId) async {
        sent.add(videoId);
        return true;
      };
    });

    const song = MediaItem(id: 'XFkzRNyygfk', title: 'Creep');

    test('counted while an account is connected, on unless switched off',
        () async {
      expect(YtHistorySync.enabled, isTrue);
      expect(await YtHistorySync.notePlay(song), isTrue);
      expect(sent, ['XFkzRNyygfk']);

      await YtHistorySync.setEnabled(false);
      expect(await YtHistorySync.notePlay(song), isFalse);
      await YtHistorySync.setEnabled(true);
      connected = false;
      expect(await YtHistorySync.notePlay(song), isFalse);
      expect(sent, ['XFkzRNyygfk']);
    });

    test('not in a private session', () async {
      await PrivateSession.start();
      expect(await YtHistorySync.notePlay(song), isFalse);
      await PrivateSession.stop();
      expect(await YtHistorySync.notePlay(song), isTrue);
    });

    test('YouTube\'s songs and videos only', () async {
      for (final id in [
        'device_42',
        // As long as a video's id.
        'device_1234',
        'cloud_17abc',
        'cloud_17',
        'podcast_https://example.com/ep.mp3',
        'abs_li_123',
        'lv_901',
      ]) {
        expect(
            await YtHistorySync.notePlay(MediaItem(id: id, title: id)), isFalse,
            reason: id);
      }
      expect(sent, isEmpty);
    });

    test('YouTube out of reach: nothing thrown', () async {
      YtHistorySync.send = (_) async => throw Exception('offline');
      expect(await YtHistorySync.notePlay(song), isFalse);
    });
  });

  testWidgets('the switch, under the connected account', (tester) async {
    final settings = Get.put<SettingsScreenController>(_FakeSettings());
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(body: YtHistorySyncTile()),
    ));
    expect(find.text('ytHistorySync'), findsOneWidget);
    final on = tester.widget<Switch>(find.byType(Switch));
    expect(on.value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(YtHistorySync.enabled, isFalse);
    expect(Hive.box('AppPrefs').get(YtHistorySync.enabledKey), isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    // No account: no switch.
    settings.ytConnected.value = false;
    await tester.pump();
    expect(find.byType(Switch), findsNothing);
  });
}
