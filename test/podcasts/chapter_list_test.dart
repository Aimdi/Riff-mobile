import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/services/playback_hardening.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/player/components/long_form_player.dart';
import 'package:harmonymusic/ui/player/components/player_control.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/now_playing_bars.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final chapters = <PodcastChapter>[
    PodcastChapter(startSec: 0, title: 'Intro'),
    PodcastChapter(
        startSec: 60, title: 'Interview', linkUrl: 'https://example.com/guest'),
    PodcastChapter(startSec: 120, title: 'Outro'),
  ].obs;
  @override
  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero,
          current: const Duration(seconds: 70),
          total: const Duration(minutes: 3))
      .obs;
  @override
  final buttonState = PlayButtonState.paused.obs;
  @override
  final currentSong = Rxn<MediaItem>(
      const MediaItem(id: 'podcast_ep', title: 'Episode', artist: 'Show'));

  Duration? sought;

  @override
  void seek(Duration position,
          {PlaybackCommandSource source = PlaybackCommandSource.user}) =>
      sought = position;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePlayer player;

  setUp(() => player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer);
  tearDown(Get.reset);

  Future<void> pumpList(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Scaffold(body: ChapterList(playerController: player)),
      ));

  Finder rowOf(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(ListTile));

  testWidgets('the chapter playing shows the bars, and follows the episode',
      (tester) async {
    await pumpList(tester);
    expect(
        find.descendant(
            of: rowOf('Interview'), matching: find.byType(NowPlayingBars)),
        findsOneWidget);
    expect(find.byType(NowPlayingBars), findsOneWidget);

    player.progressBarStatus.value = ProgressBarState(
        buffered: Duration.zero,
        current: const Duration(seconds: 125),
        total: const Duration(minutes: 3));
    await tester.pump();
    expect(
        find.descendant(
            of: rowOf('Outro'), matching: find.byType(NowPlayingBars)),
        findsOneWidget);
    expect(find.byType(NowPlayingBars), findsOneWidget);
  });

  testWidgets('only chapters with a link get the button', (tester) async {
    await pumpList(tester);
    expect(find.byTooltip('openChapterLink'), findsOneWidget);
    expect(
        find.descendant(
            of: rowOf('Interview'),
            matching: find.byTooltip('openChapterLink')),
        findsOneWidget);
  });

  testWidgets('a tap plays from the chapter', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => openChaptersSheet(player, context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outro'));
    await tester.pumpAndSettle();
    expect(player.sought, const Duration(seconds: 120));
    expect(find.byType(ChapterList), findsNothing);
  });

  group('previous / next chapter in the player', () {
    void at(int sec) => player.progressBarStatus.value = ProgressBarState(
        buffered: Duration.zero,
        current: Duration(seconds: sec),
        total: const Duration(minutes: 3));

    Future<void> pumpLine(WidgetTester tester) => tester.pumpWidget(MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: const Scaffold(body: LongFormChapterLine()),
        ));

    IconButton button(WidgetTester tester, String tooltip) =>
        tester.widget<IconButton>(find.ancestor(
            of: find.byTooltip(tooltip), matching: find.byType(IconButton)));

    test('where they go', () {
      final chapters = player.chapters;
      expect(chapterSkipTarget(chapters, 70, forward: true), 120);
      // 10 s into a chapter: back to its start.
      expect(chapterSkipTarget(chapters, 70, forward: false), 60);
      // In its first seconds: the chapter before.
      expect(chapterSkipTarget(chapters, 61, forward: false), 0);
      expect(chapterSkipTarget(chapters, 130, forward: true), isNull);
      expect(chapterSkipTarget(chapters, 1, forward: false), isNull);
      // Before the first chapter starts.
      final afterIntro = [PodcastChapter(startSec: 30, title: 'One')];
      expect(chapterSkipTarget(afterIntro, 10, forward: true), 30);
      expect(chapterSkipTarget(afterIntro, 10, forward: false), isNull);
      expect(chapterSkipTarget(const [], 10, forward: true), isNull);
    });

    testWidgets('they seek, and stop at the ends', (tester) async {
      await pumpLine(tester);
      expect(find.text('2/3 · Interview'), findsOneWidget);

      await tester.tap(find.byTooltip('nextChapter'));
      expect(player.sought, const Duration(seconds: 120));
      await tester.tap(find.byTooltip('previousChapter'));
      expect(player.sought, const Duration(seconds: 60));

      at(121);
      await tester.pump();
      expect(button(tester, 'nextChapter').onPressed, isNull);
      await tester.tap(find.byTooltip('previousChapter'));
      expect(player.sought, const Duration(seconds: 60));

      at(1);
      await tester.pump();
      expect(button(tester, 'previousChapter').onPressed, isNull);
      expect(button(tester, 'nextChapter').onPressed, isNotNull);
    });

    testWidgets('a single chapter has none', (tester) async {
      player.chapters.assignAll([PodcastChapter(startSec: 0, title: 'All')]);
      await pumpLine(tester);
      expect(find.text('1/1 · All'), findsOneWidget);
      expect(find.byTooltip('nextChapter'), findsNothing);
      expect(find.byTooltip('previousChapter'), findsNothing);
    });
  });
}
