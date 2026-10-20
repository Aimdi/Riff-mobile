import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/now_playing_bars.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final buttonState = PlayButtonState.paused.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('NowPlayingBarsPainter', () {
    test('still bars keep the equalizer shape', () {
      expect([
        for (var i = 0; i < 3; i++)
          NowPlayingBarsPainter.heightOf(i, 0.3, moving: false)
      ], [
        0.45,
        0.85,
        0.6
      ]);
    });

    test('settling bars go from the bounce to the rest shape', () {
      for (var i = 0; i < 3; i++) {
        expect(NowPlayingBarsPainter.settlingHeightOf(i, 0.3, 0),
            NowPlayingBarsPainter.heightOf(i, 0.3, moving: true));
        expect(NowPlayingBarsPainter.settlingHeightOf(i, 0.3, 1),
            NowPlayingBarsPainter.heightOf(i, 0.3, moving: false));
        final half = NowPlayingBarsPainter.settlingHeightOf(i, 0.3, 0.5);
        final a = NowPlayingBarsPainter.heightOf(i, 0.3, moving: true);
        final b = NowPlayingBarsPainter.heightOf(i, 0.3, moving: false);
        expect(half, closeTo((a + b) / 2, 1e-9));
      }
    });

    test('moving bars stay in the box and loop without a jump', () {
      for (var i = 0; i < 3; i++) {
        for (var t = 0.0; t <= 1.0; t += 0.05) {
          final h = NowPlayingBarsPainter.heightOf(i, t, moving: true);
          expect(h, inInclusiveRange(0.2, 1.0));
        }
        expect(NowPlayingBarsPainter.heightOf(i, 1, moving: true),
            closeTo(NowPlayingBarsPainter.heightOf(i, 0, moving: true), 1e-9));
      }
    });
  });

  group('NowPlayingBars', () {
    late _FakePlayer player;
    NowPlayingBarsPainter painter(WidgetTester tester) => tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(NowPlayingBars),
            matching: find.byType(CustomPaint)))
        .painter! as NowPlayingBarsPainter;

    setUp(() {
      player = _FakePlayer();
      Get.put<PlayerController>(player);
    });
    tearDown(Get.reset);

    Widget host({bool reducedMotion = false}) => MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reducedMotion),
              child: const Scaffold(body: Center(child: NowPlayingBars())),
            ),
          ),
        );

    testWidgets('bounce while playing, still while paused', (tester) async {
      await tester.pumpWidget(host());
      expect(tester.hasRunningAnimations, isFalse);

      player.buttonState.value = PlayButtonState.playing;
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(RiffDurations.select);

      // A pause eases them down to rest, then nothing ticks.
      player.buttonState.value = PlayButtonState.paused;
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(painter(tester).rest, 1);
    });

    testWidgets('a pause settles the bars instead of snapping them',
        (tester) async {
      await tester.pumpWidget(host());
      player.buttonState.value = PlayButtonState.playing;
      await tester.pump();
      await tester.pump(RiffDurations.select);
      expect(painter(tester).rest, 0);

      player.buttonState.value = PlayButtonState.paused;
      await tester.pump();
      await tester.pump(RiffDurations.select ~/ 2);
      final rest = painter(tester).rest;
      expect(rest, greaterThan(0));
      expect(rest, lessThan(1));
    });

    testWidgets('still with reduced motion', (tester) async {
      player.buttonState.value = PlayButtonState.playing;
      await tester.pumpWidget(host(reducedMotion: true));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);

      // Pausing doesn't ease them either.
      player.buttonState.value = PlayButtonState.paused;
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(painter(tester).rest, 1);
    });

    testWidgets('read as "Now playing" (merged into its row)', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host());
      expect(find.semantics.byLabel(RegExp('nowPlaying')), findsOne);
      semantics.dispose();
    });
  });
}
