import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
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

      player.buttonState.value = PlayButtonState.paused;
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('still with reduced motion', (tester) async {
      player.buttonState.value = PlayButtonState.playing;
      await tester.pumpWidget(host(reducedMotion: true));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('read as "Now playing" (merged into its row)', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host());
      expect(find.semantics.byLabel(RegExp('nowPlaying')), findsOne);
      semantics.dispose();
    });
  });
}
