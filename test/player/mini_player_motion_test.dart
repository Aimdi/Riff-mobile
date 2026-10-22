import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/ui/player/components/animated_play_button.dart';
import 'package:harmonymusic/ui/player/components/mini_player.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_spacing.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/mini_player_progress_bar.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentQueue = <MediaItem>[].obs;
  @override
  final currentSongIndex = 0.obs;
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final isShuffleModeEnabled = false.obs;
  @override
  final isQueueLoopModeEnabled = false.obs;
  @override
  final isLoopModeEnabled = false.obs;
  @override
  final isCurrentSongFav = false.obs;
  @override
  final playbackError = RxnString();
  @override
  final buttonState = PlayButtonState.paused.obs;
  @override
  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero, current: Duration.zero, total: Duration.zero)
      .obs;
  @override
  final playerPanelMinHeight = 75.0.obs;
  @override
  final isPlayerpanelTopVisible = true.obs;
  @override
  final playerPaneOpacity = 1.0.obs;
  @override
  final playerPanelPosition = ValueNotifier<double>(0);
  @override
  bool get playsOnPastEnd => false;
  @override
  ScrollController scrollController = ScrollController();
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _song(String id) =>
    MediaItem(id: id, title: 'Title $id', artist: 'Artist $id');

void main() {
  late _FakePlayer player;
  setUp(() {
    player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    final song = _song('one');
    player.currentQueue.assignAll([song, _song('two')]);
    player.currentSong.value = song;
  });
  tearDown(Get.reset);

  Future<void> pumpMini(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2220)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: MiniPlayer())),
    ));
    await tester.pump();
  }

  // Lets the artist line's marquee timers (one 5 s pass) run out.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('fades with the player panel every frame, without rebuilding',
      (tester) async {
    await pumpMini(tester);
    final fade = tester.widget<FadeTransition>(find
        .descendant(
            of: find.byType(MiniPlayer), matching: find.byType(FadeTransition))
        .first);
    expect(fade.opacity.value, 1);
    player.playerPanelPosition.value = 0.1;
    expect(fade.opacity.value, closeTo(0.5, 1e-9));
    player.playerPanelPosition.value = 0.3;
    expect(fade.opacity.value, 0);
    await unmount(tester);
  });

  testWidgets('kept, not rebuilt, behind the open player', (tester) async {
    await pumpMini(tester);
    final button = find.byType(AnimatedPlayButton, skipOffstage: false);
    final state = tester.state(button);

    player.isPlayerpanelTopVisible.value = false;
    await tester.pump();
    // Out of sight and its animations paused, but still there…
    expect(find.byType(AnimatedPlayButton), findsNothing);
    expect(button, findsOneWidget);
    expect(TickerMode.of(tester.element(button)), isFalse);
    // …except the progress line, rebuilt with every position tick.
    expect(
        find.byType(MiniPlayerProgressBar, skipOffstage: false), findsNothing);

    player.isPlayerpanelTopVisible.value = true;
    await tester.pump();
    // The same one back: no replayed play / pause morph or marquee.
    expect(tester.state(button), same(state));
    expect(find.byType(MiniPlayerProgressBar), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a new song: art and titles cross-fade together', (tester) async {
    await pumpMini(tester);
    player.currentSong.value = player.currentQueue[1];
    player.currentSongIndex.value = 1;
    await tester.pump();
    await tester.pump(RiffDurations.trackChange ~/ 2);
    // Both songs on screen mid-change.
    expect(find.text('Title one'), findsOneWidget);
    expect(find.text('Title two'), findsOneWidget);
    await tester.pump(RiffDurations.trackChange);
    await tester.pumpAndSettle();
    expect(find.text('Title one'), findsNothing);
    expect(find.text('Title two'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('TalkBack reads the song as one button that opens the player',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpMini(tester);
    final song = find.bySemanticsLabel('Title one, Artist one');
    expect(song, findsOneWidget);
    expect(
        tester.getSemantics(song),
        matchesSemantics(
          label: 'Title one, Artist one',
          isButton: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ));
    // The two lines aren't read again on their own.
    expect(find.bySemanticsLabel('Title one'), findsNothing);
    handle.dispose();
    await unmount(tester);
  });

  testWidgets('the controls take the bar\'s full height to tap',
      (tester) async {
    await pumpMini(tester);
    for (final icon in [
      Icons.skip_previous_rounded,
      Icons.skip_next_rounded,
    ]) {
      final hit = find.ancestor(
          of: find.byIcon(icon).first, matching: find.byType(InkWell));
      expect(tester.getSize(hit.first).height, RiffSizes.touch);
    }
    final queue = find.ancestor(
        of: find.byIcon(Icons.queue_music), matching: find.byType(IconButton));
    expect(tester.getSize(queue.first).height, RiffSizes.touch);
    await unmount(tester);
  });
}
