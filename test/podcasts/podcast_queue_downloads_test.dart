import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/network_kind.dart';
import 'package:harmonymusic/services/podcast_download_service.dart';
import 'package:harmonymusic/services/podcast_library.dart';
import 'package:harmonymusic/services/podcast_queue_downloads.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_library_ui.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

MediaItem _ep(String id, {String url = 'https://a.example/ep.mp3'}) =>
    MediaItem(id: id, title: id, extras: {
      'isPodcast': true,
      'feedUrl': 'https://a.example/feed',
      'url': url,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> downloaded;

  setUp(() async {
    for (final b in [
      'AppPrefs',
      'PodcastQueue',
      'PodcastDownloads',
      PodcastLibrary.showBox,
    ]) {
      await Hive.openBox(b, bytes: Uint8List(0));
    }
    downloaded = [];
    // Downloads as the service would, without the network.
    PodcastQueueDownloads.downloader = (e) async {
      downloaded.add(e.id);
      await Hive.box('PodcastDownloads')
          .put(e.id, {'path': '/downloads/${e.id}.mp3', 'id': e.id});
      return true;
    };
  });

  tearDown(() async {
    PodcastQueueDownloads.downloader = PodcastDownloadService.download;
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(NetworkKind.channel, null);
    Get.reset();
    await Hive.close();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 10));

  test('still to download: from feeds, with a file, not downloaded yet',
      () async {
    await Hive.box('PodcastDownloads')
        .put('podcast_done', {'path': '/downloads/done.mp3'});
    expect(
        PodcastQueueDownloads.pending([
          _ep('podcast_a'),
          _ep('dQw4w9WgXcQ'), // a YouTube episode: no file
          _ep('podcast_nofile', url: ''),
          _ep('podcast_done'),
          _ep('podcast_b'),
        ]).map((e) => e.id),
        ['podcast_a', 'podcast_b']);
  });

  test('Off downloads nothing; Always downloads the queue, then what joins',
      () async {
    final queue = Get.put(PodcastQueueController());
    queue.add(_ep('podcast_1'));
    await settle();
    expect(downloaded, isEmpty);

    await PodcastQueueDownloads.setMode(NewEpisodesDownload.always);
    await settle();
    expect(Hive.box('AppPrefs').get(PodcastQueueDownloads.prefKey), 'always');
    expect(downloaded, ['podcast_1']);

    queue.add(_ep('podcast_2'));
    queue.insertAt(0, _ep('podcast_3'));
    await settle();
    expect(downloaded, ['podcast_1', 'podcast_2', 'podcast_3']);
  });

  test('On Wi-Fi waits while on mobile data', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var metered = true;
    messenger.setMockMethodCallHandler(
        NetworkKind.channel, (call) async => metered);
    final queue = Get.put(PodcastQueueController());
    await PodcastQueueDownloads.setMode(NewEpisodesDownload.wifi);
    queue.add(_ep('podcast_w'));
    await settle();
    expect(downloaded, isEmpty);

    // On Wi-Fi again (the next Inbox refresh, or the app's next start).
    metered = false;
    await PodcastQueueDownloads.run();
    expect(downloaded, ['podcast_w']);
  });

  testWidgets('Podcast settings offer it for the whole library',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(
          body: SingleChildScrollView(child: PodcastLibraryEditor())),
    ));
    expect(find.text('queueDownload'), findsOneWidget);

    await tester.tap(find.text('newEpisodesDownload_wifi'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(PodcastQueueDownloads.mode, NewEpisodesDownload.wifi);
  });
}
