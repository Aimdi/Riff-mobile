import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/podcast_download_service.dart';
import 'package:harmonymusic/services/podcast_library.dart';
import 'package:harmonymusic/services/podcast_progress_service.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_inbox_screen.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcasts_library_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

const _feed = 'https://a.example/feed';

MediaItem _ep(String id, String title, int pubMs) => MediaItem(
      id: id,
      title: title,
      artist: 'Show',
      duration: const Duration(minutes: 30),
      extras: {
        'isPodcast': true,
        'feedUrl': _feed,
        'pubDateMs': pubMs,
        'url': 'https://a.example/$id.mp3',
      },
    );

/// An Inbox already loaded: the screen shows it without fetching.
class _FakeLibrary extends GetxController implements LibraryPodcastsController {
  _FakeLibrary(this.inbox);
  final List<MediaItem> inbox;

  @override
  final libraryPodcasts = <Playlist>[].obs;

  @override
  List<MediaItem>? freshInbox(String subsKey) => inbox;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late PodcastQueueController queue;

  setUp(() async {
    for (final b in [
      'PodcastPlayed',
      'PodcastProgress',
      'PodcastQueue',
      'PodcastSubs',
      'PodcastDownloads',
      PodcastLibrary.showBox,
      PodcastLibrary.archiveBox,
    ]) {
      await Hive.openBox(b, bytes: Uint8List(0));
    }
    queue = Get.put(PodcastQueueController());
    Get.put<LibraryPodcastsController>(_FakeLibrary([
      _ep('e2', 'Episode Two', 2000),
      _ep('e1', 'Episode One', 1000),
    ]));
  });

  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  Future<void> pumpInbox(WidgetTester tester) => tester.pumpWidget(
        GetMaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: const Scaffold(body: PodcastInboxScreen()),
        ),
      );

  testWidgets('swipe right queues the episode and the row stays',
      (tester) async {
    await pumpInbox(tester);
    await tester.drag(find.text('Episode One'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(queue.queue.map((e) => e.id), ['e1']);
    expect(find.text('Episode One'), findsOneWidget);
    expect(find.text('addedToQueue'), findsOneWidget);

    // Again: it's already there.
    await tester.drag(find.text('Episode One'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(queue.queue, hasLength(1));
    expect(find.text('alreadyInQueue'), findsOneWidget);
  });

  testWidgets('swipe left marks it played, with Undo', (tester) async {
    queue.add(_ep('e2', 'Episode Two', 2000));
    await pumpInbox(tester);
    await tester.drag(find.text('Episode Two'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(PodcastProgressService.isPlayed('e2'), isTrue);
    expect(find.text('Episode Two'), findsNothing);
    expect(queue.queue, isEmpty);
    expect(find.text('markedAsPlayed'), findsOneWidget);

    await tester.tap(find.text('undo'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(PodcastProgressService.isPlayed('e2'), isFalse);
    expect(find.text('Episode Two'), findsOneWidget);
    expect(queue.queue.map((e) => e.id), ['e2']);
  });

  test("a swipe's mark played leaves the download for Undo", () async {
    await Hive.box(PodcastLibrary.showBox)
        .put(_feed, {'autoDelete': AutoDeletePolicy.immediately.name});
    await Hive.box('PodcastDownloads')
        .put('e1', {'path': '/downloads/e1.mp3', 'id': 'e1'});
    PodcastLibrary.markAllListened([_ep('e1', 'Episode One', 1000)],
        sweep: false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(PodcastDownloadService.isDownloaded('e1'), isTrue);
  });
}
