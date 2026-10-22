import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/podcast_progress_service.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_show_view.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

MediaItem _episode(int n) => MediaItem(
      id: 'podcast_ep$n',
      title: 'Episode $n',
      artist: 'Show',
      duration: const Duration(minutes: 30),
      extras: const {'isPodcast': true},
    );

const _boxes = ['AppPrefs', 'PodcastProgress', 'PodcastPlayed', 'PodcastQueue'];

void main() {
  late PodcastQueueController queue;

  setUp(() async {
    for (final name in _boxes) {
      await Hive.openBox(name, bytes: Uint8List(0));
    }
    queue = Get.put(PodcastQueueController());
  });
  tearDown(() async {
    Get.reset();
    for (final name in _boxes) {
      await Hive.box(name).close();
    }
  });

  Future<List<int>> pumpShow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final played = <int>[];
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: PodcastShowView(
        title: 'Show',
        author: 'Host',
        artUrl: '',
        description: '',
        episodes: [_episode(3), _episode(2), _episode(1)],
        loading: false,
        subscribed: true,
        onToggleSubscribe: () {},
        onPlay: played.add,
        playbackKey: 'feed',
      ),
    ));
    return played;
  }

  Future<void> startSelecting(WidgetTester tester) async {
    await tester.tap(find.byTooltip('moreOptions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('selectEpisodes'));
    await tester.pumpAndSettle();
  }

  /// Taps [tooltip]'s button with real async for what it writes.
  Future<void> act(WidgetTester tester, String tooltip) async {
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip(tooltip));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('pick episodes and queue them, without playing them',
      (tester) async {
    final played = await pumpShow(tester);
    await startSelecting(tester);
    expect(find.text('selectedCount'), findsOneWidget);
    // Nothing picked yet: nothing to do with them.
    final queueButton = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.playlist_add_rounded),
        matching: find.byType(IconButton)));
    expect(queueButton.onPressed, isNull);

    await tester.tap(find.text('Episode 3'));
    await tester.tap(find.text('Episode 1'));
    await tester.pump();
    expect(played, isEmpty);
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));

    await act(tester, 'addToQueue');
    expect(queue.queue.map((e) => e.id), ['podcast_ep3', 'podcast_ep1']);
    // Done: the page is as before, and a tap plays again.
    expect(find.text('selectedCount'), findsNothing);
    await tester.tap(find.text('Episode 2'));
    expect(played, [1]);
  });

  testWidgets('all of them or none, then the picked ones played',
      (tester) async {
    await pumpShow(tester);
    await startSelecting(tester);
    await tester.tap(find.byTooltip('selectAll'));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
    await tester.tap(find.byTooltip('selectAll'));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

    await tester.tap(find.text('Episode 2'));
    await tester.pump();
    await act(tester, 'markAsPlayed');
    expect(PodcastProgressService.isPlayed('podcast_ep2'), isTrue);
    expect(PodcastProgressService.isPlayed('podcast_ep1'), isFalse);
    expect(find.text('markedAllListened'), findsOneWidget);
  });

  testWidgets(
      'a long press picks it and all below it (the older ones), '
      'to mark them played at once', (tester) async {
    await pumpShow(tester);
    await startSelecting(tester);
    await tester.longPress(find.text('Episode 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('selectAllBelow'));
    await tester.pumpAndSettle();
    // Episodes 2 and 1, listed under it; 3 stays as it was.
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));

    await act(tester, 'markAsPlayed');
    expect(PodcastProgressService.isPlayed('podcast_ep2'), isTrue);
    expect(PodcastProgressService.isPlayed('podcast_ep1'), isTrue);
    expect(PodcastProgressService.isPlayed('podcast_ep3'), isFalse);
  });

  testWidgets('or it and all above it, keeping what was picked',
      (tester) async {
    await pumpShow(tester);
    await startSelecting(tester);
    await tester.tap(find.text('Episode 1'));
    await tester.pump();
    await tester.longPress(find.text('Episode 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('selectAllAbove'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));

    await act(tester, 'addToQueue');
    // In the feed's order.
    expect(queue.queue.map((e) => e.id),
        ['podcast_ep3', 'podcast_ep2', 'podcast_ep1']);
  });

  testWidgets('✕ leaves without doing anything', (tester) async {
    await pumpShow(tester);
    await startSelecting(tester);
    await tester.tap(find.text('Episode 1'));
    await tester.tap(find.byTooltip('cancel'));
    // The selection bar crossfades back to the top bar.
    await tester.pumpAndSettle();
    expect(find.text('selectedCount'), findsNothing);
    expect(queue.queue, isEmpty);
    expect(PodcastProgressService.isPlayed('podcast_ep1'), isFalse);
  });

  testWidgets('nothing to download says so', (tester) async {
    await pumpShow(tester);
    await startSelecting(tester);
    // These episodes have no audio address to download from.
    await tester.tap(find.text('Episode 1'));
    await tester.pump();
    await act(tester, 'download');
    expect(find.text('nothingToDownload'), findsOneWidget);
  });
}
