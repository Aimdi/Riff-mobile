import 'dart:ui' show Locale;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/download_notice.dart';
import 'package:harmonymusic/services/podcast_download_service.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  final calls = <MethodCall>[];
  var asked = 0;

  setUp(() async {
    Get.addTranslations(Languages().keys);
    Get.locale = const Locale('en');
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    calls.clear();
    asked = 0;
    messenger.setMockMethodCallHandler(DownloadNotice.channel, (call) async {
      calls.add(call);
      return true;
    });
    messenger.setMockMethodCallHandler(permissions, (call) async {
      if (call.method == 'requestPermissions') asked++;
      return {for (final p in call.arguments as List) p: 1};
    });
  });
  tearDown(() async {
    DownloadNotice.resetForTest();
    messenger.setMockMethodCallHandler(DownloadNotice.channel, null);
    messenger.setMockMethodCallHandler(permissions, null);
    await Hive.close();
  });

  Map<Object?, Object?> lastShown() => calls.last.arguments as Map;

  test('songs and episodes downloading show as one: the one going now of all',
      () {
    DownloadNotice.update(DownloadNotice.songs,
        done: 2, total: 10, text: 'Song C');
    expect(calls.single.method, 'show');
    expect(lastShown()['title'], 'Downloading 3 of 10');
    expect(lastShown()['text'], 'Song C');
    expect(lastShown()['done'], 2);
    expect(lastShown()['total'], 10);
    expect(lastShown()['channel'], 'Downloads');

    DownloadNotice.update(DownloadNotice.episodes,
        done: 0, total: 1, text: 'Episode 1');
    expect(lastShown()['title'], 'Downloading 3 of 11');
    expect(lastShown()['text'], 'Episode 1');

    // One kind done: the other stays.
    DownloadNotice.end(DownloadNotice.episodes);
    expect(calls.last.method, 'show');
    expect(lastShown()['total'], 10);
    // All done: it goes, once.
    DownloadNotice.end(DownloadNotice.songs);
    DownloadNotice.end(DownloadNotice.songs);
    expect(calls.map((c) => c.method), ['show', 'show', 'show', 'stop']);
  });

  test('all done but the last: it counts that one', () {
    DownloadNotice.update(DownloadNotice.songs,
        done: 10, total: 10, text: 'Song J');
    expect(lastShown()['title'], 'Downloading 10 of 10');
  });

  test('the notifications permission is asked for once, at the first download',
      () async {
    DownloadNotice.update(DownloadNotice.songs,
        done: 0, total: 2, text: 'Song A');
    DownloadNotice.update(DownloadNotice.songs,
        done: 1, total: 2, text: 'Song B');
    await pumpEventQueue();
    expect(asked, 1);
    expect(Hive.box('AppPrefs').get(DownloadNotice.askedKey), isTrue);
  });

  test('off Android there is no notification', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    DownloadNotice.update(DownloadNotice.songs,
        done: 0, total: 1, text: 'Song A');
    DownloadNotice.end(DownloadNotice.songs);
    expect(calls, isEmpty);
  });

  test('an episode downloading shows, and goes when it ends (here failed)',
      () async {
    const episode = MediaItem(
        id: 'podcast_1',
        title: 'Episode 1',
        extras: {'url': 'https://example.com/1.mp3', 'isPodcast': true});
    // No storage here: the download fails, as it would offline.
    expect(await PodcastDownloadService.download(episode), isFalse);
    expect(calls.map((c) => c.method), ['show', 'stop']);
    final shown = calls.first.arguments as Map;
    expect(shown['text'], 'Episode 1');
    expect(shown['total'], 1);
  });
}
