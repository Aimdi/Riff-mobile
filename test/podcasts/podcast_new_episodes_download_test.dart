import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/network_kind.dart';
import 'package:harmonymusic/services/podcast_library.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_library_ui.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

const _feedA = 'https://a.example/feed';

final _t0 = DateTime(2026, 10, 1, 12);

int _at(Duration d) => _t0.add(d).millisecondsSinceEpoch;

MediaItem _ep(String id, {int? pub, bool audio = true}) => MediaItem(
      id: id,
      title: id,
      extras: {
        'isPodcast': true,
        'feedUrl': _feedA,
        if (pub != null) 'pubDateMs': pub,
        if (audio) 'url': 'https://a.example/$id.mp3',
      },
    );

List<String> _ids(List<MediaItem> l) => l.map((e) => e.id).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('metered or not', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(NetworkKind.channel, null);
    });

    test('desktop never is', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(await NetworkKind.isMetered(), isFalse);
    });

    test("Android asks; when it can't tell, it is", () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var answer = false;
      messenger.setMockMethodCallHandler(NetworkKind.channel,
          (call) async => call.method == 'isMetered' ? answer : null);
      expect(await NetworkKind.isMetered(), isFalse);
      answer = true;
      expect(await NetworkKind.isMetered(), isTrue);
      messenger.setMockMethodCallHandler(NetworkKind.channel,
          (call) async => throw PlatformException(code: 'denied'));
      expect(await NetworkKind.isMetered(), isTrue);
      // No channel at all.
      messenger.setMockMethodCallHandler(NetworkKind.channel, null);
      expect(await NetworkKind.isMetered(), isTrue);
    });
  });

  group('new episodes download', () {
    setUp(() async {
      for (final b in [
        PodcastLibrary.showBox,
        PodcastLibrary.archiveBox,
        'PodcastPlayed',
        'PodcastProgress',
        'PodcastDownloads',
        'PodcastQueue',
      ]) {
        await Hive.openBox(b, bytes: Uint8List(0));
      }
    });

    tearDown(() async {
      Get.reset();
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(NetworkKind.channel, null);
      await Hive.close();
    });

    final inbox = [
      _ep('a2', pub: _at(const Duration(hours: 2))),
      _ep('a1', pub: _at(const Duration(hours: 1))),
      _ep('old', pub: _at(const Duration(days: -2))),
    ];

    test('on Wi-Fi: they wait out mobile data, then go, once', () async {
      await PodcastLibrary.setShowNewEpisodesDownload(
          _feedA, NewEpisodesDownload.wifi,
          now: _t0);
      expect(PodcastLibrary.takeNewDownloads(inbox, metered: true), isEmpty);
      expect(_ids(PodcastLibrary.takeNewDownloads(inbox, metered: false)),
          ['a1', 'a2']);
      expect(PodcastLibrary.takeNewDownloads(inbox, metered: false), isEmpty);
    });

    test('always: on mobile data too, but not played, had or without audio',
        () async {
      await PodcastLibrary.setShowNewEpisodesDownload(
          _feedA, NewEpisodesDownload.always,
          now: _t0);
      await Hive.box('PodcastPlayed').put('played', 1);
      await Hive.box('PodcastDownloads')
          .put('had', {'path': '/downloads/had.mp3'});
      expect(
          _ids(PodcastLibrary.takeNewDownloads([
            _ep('noAudio', pub: _at(const Duration(hours: 5)), audio: false),
            _ep('had', pub: _at(const Duration(hours: 4))),
            _ep('played', pub: _at(const Duration(hours: 3))),
            ...inbox,
          ], metered: true)),
          ['a1', 'a2']);
    });

    test('the queue and downloads each find the new ones', () async {
      final queue = Get.put(PodcastQueueController());
      await PodcastLibrary.setShowNewEpisodesQueue(_feedA, NewEpisodesQueue.end,
          now: _t0);
      await PodcastLibrary.setShowNewEpisodesDownload(
          _feedA, NewEpisodesDownload.always,
          now: _t0);
      PodcastLibrary.queueNewEpisodes(inbox);
      expect(_ids(queue.queue), ['a1', 'a2']);
      expect(_ids(PodcastLibrary.takeNewDownloads(inbox, metered: false)),
          ['a1', 'a2']);
      // Off forgets the downloads' side only.
      await PodcastLibrary.setShowNewEpisodesDownload(
          _feedA, NewEpisodesDownload.off);
      expect(PodcastLibrary.newEpisodesDownloadFor(_feedA),
          NewEpisodesDownload.off);
      expect(PodcastLibrary.newEpisodesQueueFor(_feedA), NewEpisodesQueue.end);
      expect(PodcastLibrary.takeNewDownloads(inbox, metered: false), isEmpty);
    });

    test("nothing to download doesn't ask about the network", () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var asked = 0;
      messenger.setMockMethodCallHandler(NetworkKind.channel, (call) async {
        asked++;
        return false;
      });
      await PodcastLibrary.downloadNewEpisodes(inbox);
      expect(asked, 0);
    });

    Future<void> pumpEditor(WidgetTester tester, String showKey) =>
        tester.pumpWidget(GetMaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PodcastLibraryEditor(showKey: showKey),
            ),
          ),
        ));

    testWidgets('a feed show sets it in its sheet', (tester) async {
      await pumpEditor(tester, _feedA);
      await tester.ensureVisible(find.text('newEpisodesDownload_wifi'));
      await tester.tap(find.text('newEpisodesDownload_wifi'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(PodcastLibrary.newEpisodesDownloadFor(_feedA),
          NewEpisodesDownload.wifi);
    });

    testWidgets('a YouTube show has nothing to download', (tester) async {
      await pumpEditor(tester, 'yt:PLshow');
      expect(find.text('newEpisodesToQueue'), findsOneWidget);
      expect(find.text('newEpisodesDownload'), findsNothing);
    });
  });
}
