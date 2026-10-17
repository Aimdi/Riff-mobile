import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/yt_like_sync.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/yt_like_sync_tile.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/utils/secure_credentials.dart';
import 'package:hive/hive.dart';

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final ytConnected = true.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<String> sent;
  late bool youTubeTakesIt;

  late List<int?> fetched;

  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    await Hive.openBox(YtLikeSync.queueBox, bytes: Uint8List(0));
    await Hive.openBox('LIBFAV', bytes: Uint8List(0));
    fetched = [];
    YtLikeSync.fetchLikes = ({limit}) async {
      fetched.add(limit);
      return [
        _song('songAAAAAAA'),
        _song('songBBBBBBB'),
        const MediaItem(
            id: 'episodeCCCC', title: 'Episode', extras: {'isPodcast': true}),
      ];
    };
    sent = [];
    youTubeTakesIt = true;
    YtLikeSync.connected = () => true;
    YtLikeSync.send = (endpoint, videoId) async {
      if (!youTubeTakesIt) return false;
      sent.add('$endpoint $videoId');
      return true;
    };
  });
  tearDown(() async {
    await YtLikeSync.forgetAccount();
    Get.reset();
    await Hive.close();
  });

  test('off, or without an account: likes stay in Riff', () async {
    await YtLikeSync.onFavorite(_song('songAAAAAAA'), add: true);
    expect(Hive.box(YtLikeSync.queueBox).isEmpty, isTrue);

    await YtLikeSync.setEnabled(true);
    YtLikeSync.connected = () => false;
    await YtLikeSync.onFavorite(_song('songAAAAAAA'), add: true);
    await YtLikeSync.flush();
    expect(Hive.box(YtLikeSync.queueBox).isEmpty, isTrue);
    expect(sent, isEmpty);
  });

  test('a like or an unlike in Riff goes to YouTube Music', () async {
    await YtLikeSync.setEnabled(true);
    await YtLikeSync.onFavorite(_song('songAAAAAAA'), add: true);
    // Episodes, chapters and files on the phone aren't YouTube's to like.
    await YtLikeSync.onFavorite(_song('podcast_1'), add: true);
    await YtLikeSync.onFavorite(_song('device_42'), add: true);
    expect(YtLikeSync.pending.value, 1);
    await YtLikeSync.flush();
    expect(sent, ['like/like songAAAAAAA']);
    expect(YtLikeSync.pending.value, 0);

    await YtLikeSync.onFavorite(_song('songAAAAAAA'), add: false);
    // Liked in YouTube Music itself (it came in from there): unliked too,
    // or it would come back.
    await YtLikeSync.onFavorite(_song('songBBBBBBB'), add: false);
    await YtLikeSync.flush();
    expect(sent, [
      'like/like songAAAAAAA',
      'like/removelike songAAAAAAA',
      'like/removelike songBBBBBBB',
    ]);
    expect(Hive.box(YtLikeSync.queueBox).isEmpty, isTrue);
  });

  test('liked and unliked before it went: the unlike goes', () async {
    await YtLikeSync.setEnabled(true);
    await YtLikeSync.onFavorite(_song('songAAAAAAA'), add: true);
    await YtLikeSync.onFavorite(_song('songAAAAAAA'), add: false);
    expect(YtLikeSync.pending.value, 1);
    await YtLikeSync.flush();
    // It may have been liked in YouTube Music already.
    expect(sent, ['like/removelike songAAAAAAA']);
  });

  test("YouTube out of reach: kept until it's back", () async {
    await YtLikeSync.setEnabled(true);
    await YtLikeSync.onFavorite(_song('songAAAAAAA'), add: true);
    await YtLikeSync.onFavorite(_song('songBBBBBBB'), add: true);
    youTubeTakesIt = false;
    await YtLikeSync.flush();
    expect(YtLikeSync.pending.value, 2);

    youTubeTakesIt = true;
    await YtLikeSync.flush();
    expect(sent, ['like/like songAAAAAAA', 'like/like songBBBBBBB']);
    expect(YtLikeSync.pending.value, 0);
  });

  test('switched off or disconnected: what waited is dropped', () async {
    await YtLikeSync.setEnabled(true);
    await YtLikeSync.onFavorite(_song('songAAAAAAA'), add: true);
    await YtLikeSync.setEnabled(false);
    expect(Hive.box(YtLikeSync.queueBox).isEmpty, isTrue);

    await YtLikeSync.setEnabled(true);
    await YtLikeSync.onFavorite(_song('songAAAAAAA'), add: true);
    await YtLikeSync.importLikes();
    await YtLikeSync.forgetAccount();
    expect(Hive.box(YtLikeSync.queueBox).isEmpty, isTrue);
    expect(Hive.box('AppPrefs').get(YtLikeSync.importedAtKey), isNull);
    expect(sent, isEmpty);
  });

  test("the like is YouTube Music's own like button's request", () async {
    final music = MusicServices();
    expect(await music.rateSong('like/like', 'songAAAAAAA'), isFalse,
        reason: 'no account');

    await SecureCredentials.set('ytAuthCookie', 'SAPISID=abc; HSID=def');
    late RequestOptions asked;
    music.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      asked = o;
      h.resolve(Response(requestOptions: o, statusCode: 200, data: {}));
    }));
    expect(await music.rateSong('like/like', 'songAAAAAAA'), isTrue);
    expect(asked.uri.path, '/youtubei/v1/like/like');
    expect((asked.data as Map)['target'], {'videoId': 'songAAAAAAA'});
    expect(asked.headers['authorization'], startsWith('SAPISIDHASH '));
    SecureCredentials.resetForTest();
  });

  group('your YouTube Music likes into Favorites', () {
    test('the songs not there yet, and nothing sent back', () async {
      await Hive.box('LIBFAV').put('songBBBBBBB', {'videoId': 'songBBBBBBB'});
      await YtLikeSync.setEnabled(true);
      expect(await YtLikeSync.importLikes(), 1);
      expect(Hive.box('LIBFAV').keys,
          unorderedEquals(['songAAAAAAA', 'songBBBBBBB']));
      expect(
          Hive.box('LIBFAV').get('songAAAAAAA')['title'], 'Song songAAAAAAA');
      expect(Hive.box(YtLikeSync.queueBox).isEmpty, isTrue);
      expect(fetched, [null], reason: 'all of them');

      expect(await YtLikeSync.importLikes(), 0);

      YtLikeSync.fetchLikes = ({limit}) => throw Exception('offline');
      expect(await YtLikeSync.importLikes(), isNull);
      YtLikeSync.connected = () => false;
      expect(await YtLikeSync.importLikes(), isNull);
    });

    test('one just unliked in Riff stays out while its unlike is on its way',
        () async {
      await YtLikeSync.setEnabled(true);
      await YtLikeSync.onFavorite(_song('songAAAAAAA'), add: false);
      expect(await YtLikeSync.importLikes(), 1);
      expect(Hive.box('LIBFAV').keys, ['songBBBBBBB']);
      await YtLikeSync.flush();
      expect(sent, ['like/removelike songAAAAAAA']);
    });

    test('in step: the latest ones once a day', () async {
      final day = DateTime(2026, 10, 14, 9);
      await YtLikeSync.importLikesDaily(now: day);
      expect(fetched, isEmpty, reason: 'off');

      await YtLikeSync.setEnabled(true);
      await YtLikeSync.importLikesDaily(now: day);
      expect(fetched, [null], reason: "all: they hadn't come in yet");
      await YtLikeSync.importLikesDaily(
          now: day.add(const Duration(hours: 20)));
      expect(fetched, hasLength(1));
      await YtLikeSync.importLikesDaily(now: day.add(const Duration(days: 1)));
      expect(fetched, [null, YtLikeSync.dailyLimit]);
    });
  });

  testWidgets('Settings: turned on, your likes come in, and it says so',
      (tester) async {
    final settings =
        Get.put<SettingsScreenController>(_FakeSettings()) as _FakeSettings;
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(body: YtLikeSyncTile()),
    ));
    expect(find.text('ytLikeSync'), findsOneWidget);
    settings.ytConnected.value = false;
    await tester.pump();
    expect(find.text('ytLikeSync'), findsNothing, reason: 'no account');

    settings.ytConnected.value = true;
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump();
    expect(YtLikeSync.enabled, isTrue);
    expect(Hive.box('LIBFAV').length, 2);
    expect(find.text('ytLikesImported'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
