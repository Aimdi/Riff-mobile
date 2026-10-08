import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/songinfo_bottom_sheet.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final showLyricsflag = false.obs;
  @override
  final isSleepTimerActive = false.obs;
  @override
  final timerDurationLeft = 0.obs;
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();

  int lyricsToggles = 0;

  @override
  Future<void> showLyrics() async {
    lyricsToggles++;
    showLyricsflag.toggle();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Opens the tiles in a bottom sheet, the way the player's ⋮ does.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  late _FakePlayer player;

  setUp(() {
    Get.reset();
    player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
  });
  tearDown(Get.reset);

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet(
                context: context,
                builder: (_) => const PlayerToolTiles(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));

  testWidgets('lyrics toggle closes the sheet and flips its label',
      (tester) async {
    await pumpApp(tester);
    await _open(tester);
    // No translations loaded here, so labels show their keys.
    expect(find.text('showLyrics'), findsOneWidget);
    expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);

    await tester.tap(find.text('showLyrics'));
    await tester.pumpAndSettle();
    expect(player.lyricsToggles, 1);
    expect(find.byType(PlayerToolTiles), findsNothing);

    await _open(tester);
    expect(find.text('hideLyrics'), findsOneWidget);
    expect(find.byIcon(Icons.lyrics), findsOneWidget);
  });

  testWidgets('sleep timer shows the time left while it runs', (tester) async {
    await pumpApp(tester);
    await _open(tester);
    expect(find.text('sleepTimer'), findsOneWidget);
    expect(find.textContaining('left'), findsNothing);

    player.isSleepTimerActive.value = true;
    player.timerDurationLeft.value = 1500;
    await tester.pump();
    expect(find.text('25m left'), findsOneWidget);
    expect(find.byIcon(Icons.bedtime), findsOneWidget);
  });
}
