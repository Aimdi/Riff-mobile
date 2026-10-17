import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/audio_output.dart';
import 'package:harmonymusic/services/lyrics_timing.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/songinfo_bottom_sheet.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>(const MediaItem(id: 'a', title: 'A'));
  @override
  RxMap<String, dynamic> lyrics =
      <String, dynamic>{'synced': '', 'plainLyrics': ''}.obs;
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
                // Scrolling, as in the song sheet.
                builder: (_) =>
                    const SingleChildScrollView(child: PlayerToolTiles()),
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

  group('lyrics timing', () {
    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    });
    tearDown(() async {
      await Hive.box('AppPrefs').close();
    });

    testWidgets('only for songs with synced lyrics, with the shift set',
        (tester) async {
      await pumpApp(tester);
      await _open(tester);
      expect(find.text('lyricsTiming'), findsNothing);

      player.lyrics['synced'] = '[00:01.00]One';
      await tester.pump();
      expect(find.text('lyricsTiming'), findsOneWidget);
      // As timed: no subtitle.
      expect(find.text('lyricsTimingLater'), findsNothing);

      await tester.runAsync(() => LyricsTiming.nudge('a', 1));
      await tester.pump();
      expect(find.text('lyricsTimingLater'), findsOneWidget);

      await tester.tap(find.text('lyricsTiming'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerToolTiles), findsNothing);
    });
  });

  group('play on another device', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final asked = <String>[];

    setUp(() {
      asked.clear();
      messenger.setMockMethodCallHandler(AudioOutput.channel, (call) async {
        asked.add(call.method);
        return true;
      });
    });
    tearDown(
        () => messenger.setMockMethodCallHandler(AudioOutput.channel, null));

    testWidgets("opens the phone's output switcher, closing the sheet",
        (tester) async {
      await pumpApp(tester);
      await _open(tester);
      expect(find.byIcon(Icons.speaker_group_rounded), findsOneWidget);

      await tester.tap(find.text('playOn'));
      await tester.pumpAndSettle();
      expect(asked, ['showOutputSwitcher']);
      expect(find.byType(PlayerToolTiles), findsNothing);
    });

    testWidgets('only on Android, which has one', (tester) async {
      await pumpApp(tester);
      await _open(tester);
      expect(find.text('sleepTimer'), findsOneWidget);
      expect(find.text('playOn'), findsNothing);
      expect(await AudioOutput.showSwitcher(), isFalse);
      expect(asked, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}
