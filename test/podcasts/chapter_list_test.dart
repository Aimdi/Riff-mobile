import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/services/playback_hardening.dart';
import 'package:harmonymusic/services/podcast_service.dart';
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
}
