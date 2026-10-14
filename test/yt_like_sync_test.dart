import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/yt_like_sync.dart';
import 'package:harmonymusic/utils/secure_credentials.dart';
import 'package:hive/hive.dart';

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id');

void main() {
  late List<String> sent;
  late bool youTubeTakesIt;

  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    await Hive.openBox(YtLikeSync.queueBox, bytes: Uint8List(0));
    await Hive.openBox(YtLikeSync.addedBox, bytes: Uint8List(0));
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

  test('a like goes to YouTube Music; unliked, Riff takes back its own',
      () async {
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
    // Liked in YouTube Music itself: unliking it in Riff leaves it liked.
    await YtLikeSync.onFavorite(_song('songBBBBBBB'), add: false);
    await YtLikeSync.flush();
    expect(sent, ['like/like songAAAAAAA', 'like/removelike songAAAAAAA']);
    expect(Hive.box(YtLikeSync.queueBox).isEmpty, isTrue);
  });

  test('liked and unliked before it went: nothing to send', () async {
    await YtLikeSync.setEnabled(true);
    await YtLikeSync.onFavorite(_song('songAAAAAAA'), add: true);
    await YtLikeSync.onFavorite(_song('songAAAAAAA'), add: false);
    await YtLikeSync.flush();
    expect(sent, isEmpty);
  });

  test("YouTube out of reach: kept, in order, until it's back", () async {
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
    await YtLikeSync.flush();
    await YtLikeSync.forgetAccount();
    expect(Hive.box(YtLikeSync.addedBox).isEmpty, isTrue);
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
}
