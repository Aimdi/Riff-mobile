import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/ui/player/components/mini_player.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_text_metrics.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/up_next_queue.dart';

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

MediaItem _song(String id) => MediaItem(
    id: id,
    title: 'Song $id gypsy',
    artist: 'Artist',
    extras: const {'length': '3:45'});

/// Whether [text]'s line is shown whole: its box is as tall as the line.
void expectWholeLine(WidgetTester tester, Finder text) {
  final line = tester.renderObject<RenderParagraph>(text);
  expect(line.size.height,
      greaterThanOrEqualTo(line.getMaxIntrinsicHeight(double.infinity) - 0.01),
      reason: 'the line is cut off');
}

/// Larger text, from the phone's font size (Android's Font size).
void main() {
  tearDown(Get.reset);

  group('the font size Riff applies', () {
    test('larger up to Largest (1.3x), never smaller than the default', () {
      double applied(double system) =>
          riffTextScaler(TextScaler.linear(system)).scale(10);
      // Android's Large and Largest are kept; it was 1.1x at most.
      expect(applied(1.15), closeTo(11.5, 1e-9));
      expect(applied(1.3), closeTo(13, 1e-9));
      expect(applied(2), closeTo(13, 1e-9));
      expect(applied(0.85), closeTo(10, 1e-9));
    });

    testWidgets('a fixed line grows only once the text needs it',
        (tester) async {
      late double atDefault;
      late double larger;
      final style =
          RiffTheme.dark(const Color(0xFF1DB954)).textTheme.titleMedium;
      Widget probe(double scale, void Function(double) out) => MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Builder(builder: (context) {
              out(riffLineBox(context, style, RiffComponentSizes.miniLine));
              return const SizedBox();
            }),
          );
      await tester.pumpWidget(probe(1, (h) => atDefault = h));
      await tester.pumpWidget(probe(1.3, (h) => larger = h));
      expect(atDefault, RiffComponentSizes.miniLine);
      expect(larger, greaterThan(RiffComponentSizes.miniLine));
    });
  });

  group('on a phone', () {
    late _FakePlayer player;
    setUp(() {
      player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    });

    Future<void> phone(WidgetTester tester, double scale) async {
      tester.view
        ..physicalSize = const Size(1080, 2220)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    for (final scale in [1.0, kRiffMaxTextScale]) {
      testWidgets('the mini player shows its title whole at ${scale}x',
          (tester) async {
        await phone(tester, scale);
        final song = _song('mini000000a');
        player.currentQueue.assignAll([song]);
        player.currentSong.value = song;
        await tester.pumpWidget(GetMaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: const Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter, child: MiniPlayer())),
        ));
        await tester.pump();

        final title = find.text(song.title);
        expectWholeLine(tester, title);
        final box = find.ancestor(of: title, matching: find.byType(SizedBox));
        if (scale == 1) {
          // As designed at the default size.
          expect(tester.getSize(box.first).height, RiffComponentSizes.miniLine);
        }

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }

    testWidgets('Up Next rows grow with the text, as before by default',
        (tester) async {
      await phone(tester, 1);
      player.currentQueue
          .assignAll([for (var i = 0; i < 4; i++) _song('queue00000$i')]);
      player.currentSongIndex.value = 1;
      Future<void> pumpQueue() async {
        await tester.pumpWidget(GetMaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: const Scaffold(body: UpNextQueue(isQueueInSlidePanel: false)),
        ));
        await tester.pump();
      }

      double rowHeight(String id) =>
          tester.getSize(find.byKey(ValueKey(id), skipOffstage: false)).height;

      await pumpQueue();
      // Played row, then Now playing and Next up with their labels.
      expect(rowHeight('queue000000'), 64);
      expect(rowHeight('queue000001'), 64 + 36);
      expect(rowHeight('queue000002'), 64 + 36);

      // Far past what Riff applies: every line still has its room (an
      // overflow fails the test).
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await pumpQueue();
      expect(rowHeight('queue000000'), greaterThan(64));
      expect(rowHeight('queue000001'), greaterThan(64 + 36));
      expectWholeLine(tester, find.text('Now playing'));
      // (A title too long for its row scrolls by, drawn twice.)
      expectWholeLine(tester, find.text(player.currentQueue[3].title).first);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
