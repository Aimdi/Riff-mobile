import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/services/podcast_segments.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/player/components/player_control.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>(const MediaItem(
      id: 'podcast_ep',
      title: 'Episode',
      duration: Duration(minutes: 10),
      extras: {'isPodcast': true}));
  @override
  final chapters = <PodcastChapter>[
    PodcastChapter(startSec: 0, title: 'Welcome'),
    PodcastChapter(startSec: 60, title: 'A word from our sponsor'),
    PodcastChapter(startSec: 120, title: 'The interview'),
  ].obs;
  @override
  final progressBarStatus = ProgressBarState(
          current: Duration.zero,
          buffered: Duration.zero,
          total: const Duration(minutes: 10))
      .obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await Hive.openBox(PodcastSegmentStore.manualBox, bytes: Uint8List(0));
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  List<bool?> ticks(WidgetTester tester) => tester
      .widgetList<Checkbox>(find.byType(Checkbox))
      .map((c) => c.value)
      .toList();

  Future<void> settleWrites(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }

  // No translations loaded here, so labels show their keys.
  testWidgets('Skip chapters: one unticked is skipped, and ticked back on',
      (tester) async {
    final pc = _FakePlayer();
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: ChapterList(playerController: pc)),
    ));
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.text('skipChapters'));
    await tester.pumpAndSettle();
    expect(ticks(tester), [true, true, true]);

    await tester.tap(find.text('A word from our sponsor'));
    await settleWrites(tester);
    expect(PodcastSegmentStore.skippedChapters('podcast_ep'),
        {chapterSkipKey(60)});
    final skip = PodcastSegmentStore.manual('podcast_ep').single;
    expect((skip.start, skip.end), (60.0, 120.0));
    expect(skip.category, SegmentCategory.chapter);
    expect(ticks(tester), [true, false, true]);

    // Done: the skipped one says so.
    await tester.tap(find.text('done'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('01:00 · chapterSkipped'), findsOneWidget);
    expect(find.byIcon(Icons.redo_rounded), findsOneWidget);

    // Ticked back on, from its box.
    await tester.tap(find.text('skipChapters'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).at(1));
    await settleWrites(tester);
    expect(PodcastSegmentStore.skippedChapters('podcast_ep'), isEmpty);
    expect(ticks(tester), [true, true, true]);
  });
}
