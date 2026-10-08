import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/services/playback_hardening.dart';
import 'package:harmonymusic/ui/player/components/animated_play_button.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final buttonState = PlayButtonState.playing.obs;
  @override
  final progressBarStatus = ProgressBarState(
          current: const Duration(seconds: 30),
          buffered: Duration.zero,
          total: const Duration(minutes: 4))
      .obs;

  final seeks = <Duration>[];
  int pauses = 0;

  @override
  void seekBy(Duration offset) => seeks.add(offset);
  @override
  void pause({PlaybackCommandSource source = PlaybackCommandSource.user}) =>
      pauses++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('slide distance', () {
    test('rounds to 5 s steps, about 15 s per 45 dp', () {
      expect(holdSeekSeconds(0), 0);
      expect(holdSeekSeconds(5), 0);
      expect(holdSeekSeconds(45), 15);
      expect(holdSeekSeconds(-60), -20);
      expect(holdSeekSeconds(300), 100);
    });

    test('labels carry a sign and m:ss', () {
      expect(holdSeekLabel(0), '0:00');
      expect(holdSeekLabel(-15), '−0:15');
      expect(holdSeekLabel(65), '+1:05');
    });
  });

  group('hold the play button', () {
    late _FakePlayer player;

    setUp(() {
      Get.reset();
      player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    });
    tearDown(Get.reset);

    Future<TestGesture> holdAndSlide(WidgetTester tester, double dx) async {
      await tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(
          body: Center(child: AnimatedPlayButton(holdToSeek: true)),
        ),
      ));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(InkWell)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(Offset(dx, 0));
      await tester.pump();
      return gesture;
    }

    testWidgets('slide left jumps back, with a bubble while holding',
        (tester) async {
      final gesture = await holdAndSlide(tester, -60);
      expect(find.text('−0:20'), findsOneWidget);

      await gesture.up();
      await tester.pump();
      expect(player.seeks, [const Duration(seconds: -20)]);
      expect(find.text('−0:20'), findsNothing);
      expect(player.pauses, 0);
    });

    testWidgets('slide right jumps forward, never past the end',
        (tester) async {
      final gesture = await holdAndSlide(tester, 2000);
      // 3:30 left in the song.
      expect(find.text('+3:30'), findsOneWidget);
      await gesture.up();
      expect(player.seeks, [const Duration(seconds: 210)]);
    });

    testWidgets('no jump back past the start', (tester) async {
      final gesture = await holdAndSlide(tester, -2000);
      expect(find.text('−0:30'), findsOneWidget);
      await gesture.up();
      expect(player.seeks, [const Duration(seconds: -30)]);
    });

    testWidgets('a hold without a slide does nothing; a tap still pauses',
        (tester) async {
      final gesture = await holdAndSlide(tester, 0);
      await gesture.up();
      expect(player.seeks, isEmpty);

      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(player.pauses, 1);
    });
  });
}
