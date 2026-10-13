import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/services/lyrics_timing.dart';
import 'package:harmonymusic/ui/player/components/lyric_line_preview.dart';
import 'package:harmonymusic/ui/player/components/lyrics_timing_sheet.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>(const MediaItem(id: 'a', title: 'A'));
  @override
  RxMap<String, dynamic> lyrics = <String, dynamic>{
    'synced': '[00:01.00]One\n[00:03.00]Two',
    'plainLyrics': '',
  }.obs;
  @override
  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero,
          current: const Duration(milliseconds: 3200),
          total: const Duration(minutes: 3))
      .obs;
  @override
  bool get usesLongFormTransport => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child) => MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: child),
    );

void main() {
  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
  });
  tearDown(() async {
    await Hive.box('AppPrefs').close();
  });

  test('half a second a tap, up to ten seconds either way', () async {
    expect(LyricsTiming.delayMs('a'), 0);
    await LyricsTiming.nudge('a', 1);
    expect(LyricsTiming.delayMs('a'), 500);
    await LyricsTiming.nudge('a', -3);
    expect(LyricsTiming.delayMs('a'), -1000);
    await LyricsTiming.setDelay('a', 60000);
    expect(LyricsTiming.delayMs('a'), LyricsTiming.maxMs);
    // Other songs keep their own timing.
    expect(LyricsTiming.delayMs('b'), 0);
    expect(LyricsTiming.delayMs(null), 0);
  });

  test('back to as timed forgets the song', () async {
    await LyricsTiming.nudge('a', 2);
    await LyricsTiming.setDelay('a', 0);
    expect(LyricsTiming.delayMs('a'), 0);
    expect(Hive.box('AppPrefs').get(LyricsTiming.key), isEmpty);
  });

  test('only the songs changed last are kept', () async {
    for (var i = 0; i <= LyricsTiming.keep; i++) {
      await LyricsTiming.setDelay('s$i', 500);
    }
    expect(LyricsTiming.delayMs('s0'), 0);
    expect(LyricsTiming.delayMs('s1'), 500);
    expect(LyricsTiming.delayMs('s${LyricsTiming.keep}'), 500);
  });

  test('lyric and song positions', () {
    // Lyrics shown half a second later are half a second behind.
    expect(lyricsPositionMs(10000, 500), 9500);
    expect(songPositionForLyricMs(9500, 500), 10000);
    expect(lyricsPositionMs(10000, -500), 10500);
    // Never before the start of the song.
    expect(songPositionForLyricMs(200, -500), 0);
    expect(lyricsDelaySeconds(-1500), '1.5');
    expect(lyricsDelaySeconds(500), '0.5');
  });

  group('with a song playing', () {
    setUp(() => Get.put<PlayerController>(_FakePlayer()));
    tearDown(Get.reset);

    testWidgets('the line under the title follows the timing', (tester) async {
      await tester.pumpWidget(_app(const LyricLinePreview()));
      // 3.2 s into the song: the second line.
      expect(find.text('Two'), findsOneWidget);

      // Shown half a second later, the lyrics are at 2.7 s: still the first.
      await tester.runAsync(() => LyricsTiming.nudge('a', 1));
      await tester.pumpAndSettle();
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsNothing);
    });

    testWidgets('Earlier, Later and Reset in the sheet', (tester) async {
      await tester.pumpWidget(_app(const LyricsTimingSheet(songId: 'a')));
      expect(find.text('lyricsTimingAsIs'), findsOneWidget);
      // Nothing to reset yet.
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'reset'))
              .onPressed,
          isNull);

      await tester.tap(find.text('lyricsLater'));
      await tester.pumpAndSettle();
      expect(LyricsTiming.delayMs('a'), 500);
      expect(find.text('lyricsTimingLater'), findsOneWidget);

      await tester.tap(find.text('lyricsEarlier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('lyricsEarlier'));
      await tester.pumpAndSettle();
      expect(LyricsTiming.delayMs('a'), -500);
      expect(find.text('lyricsTimingEarlier'), findsOneWidget);

      await tester.tap(find.text('reset'));
      await tester.pumpAndSettle();
      expect(LyricsTiming.delayMs('a'), 0);
      expect(find.text('lyricsTimingAsIs'), findsOneWidget);
    });
  });
}
