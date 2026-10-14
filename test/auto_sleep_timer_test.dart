import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/auto_sleep_timer.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/sleep_timer_bottom_sheet.dart';
import 'package:hive/hive.dart';

class _FakeMusic extends GetxService implements MusicServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHandler extends BaseAudioHandler {}

DateTime _at(int hour, [int minute = 0, int day = 14]) =>
    DateTime(2026, 10, day, hour, minute);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    AutoSleepTimer.reload();
  });
  tearDown(() async {
    Get.reset();
    await Hive.box('AppPrefs').close();
    AutoSleepTimer.reload();
  });

  group('its hours', () {
    test('22:00 to 06:00 runs past midnight', () {
      expect(AutoSleepTimer.inHours(_at(22), 22, 6), isTrue);
      expect(AutoSleepTimer.inHours(_at(23, 59), 22, 6), isTrue);
      expect(AutoSleepTimer.inHours(_at(0), 22, 6), isTrue);
      expect(AutoSleepTimer.inHours(_at(5, 59), 22, 6), isTrue);
      expect(AutoSleepTimer.inHours(_at(6), 22, 6), isFalse);
      expect(AutoSleepTimer.inHours(_at(21, 59), 22, 6), isFalse);
    });

    test('within a day, and all day when they start and end alike', () {
      expect(AutoSleepTimer.inHours(_at(13), 13, 15), isTrue);
      expect(AutoSleepTimer.inHours(_at(15), 13, 15), isFalse);
      expect(AutoSleepTimer.inHours(_at(12), 13, 15), isFalse);
      expect(AutoSleepTimer.inHours(_at(3), 9, 9), isTrue);
    });

    test('are over at their end, the next morning when past midnight', () {
      expect(AutoSleepTimer.hoursEnd(_at(23), 22, 6), _at(6, 0, 15));
      expect(AutoSleepTimer.hoursEnd(_at(2), 22, 6), _at(6));
      expect(AutoSleepTimer.hoursEnd(_at(14), 13, 15), _at(15));
      // All day: until the hour comes round again.
      expect(AutoSleepTimer.hoursEnd(_at(10), 9, 9), _at(9, 0, 15));
    });
  });

  group('starting', () {
    test('only when on, within its hours, with no timer running', () async {
      expect(AutoSleepTimer.startsAt(_at(23), timerRunning: false), isFalse);
      await AutoSleepTimer.setEnabled(true);
      expect(AutoSleepTimer.startsAt(_at(23), timerRunning: false), isTrue);
      expect(AutoSleepTimer.startsAt(_at(23), timerRunning: true), isFalse);
      expect(AutoSleepTimer.startsAt(_at(12), timerRunning: false), isFalse);
    });

    test('turned off at night, not again until the morning', () async {
      await AutoSleepTimer.setEnabled(true);
      AutoSleepTimer.decline(_at(23));
      expect(
          AutoSleepTimer.startsAt(_at(23, 30), timerRunning: false), isFalse);
      expect(AutoSleepTimer.startsAt(_at(5, 59, 15), timerRunning: false),
          isFalse);
      // The next night it starts again.
      expect(
          AutoSleepTimer.startsAt(_at(22, 0, 15), timerRunning: false), isTrue);
    });

    test('turned off by day: the night is untouched', () async {
      await AutoSleepTimer.setEnabled(true);
      AutoSleepTimer.decline(_at(12));
      expect(AutoSleepTimer.startsAt(_at(23), timerRunning: false), isTrue);
    });
  });

  test('settings are kept; ones that make no sense are left aside', () async {
    expect(AutoSleepTimer.from.value, 22);
    expect(AutoSleepTimer.to.value, 6);
    expect(AutoSleepTimer.minutes, 30);
    await AutoSleepTimer.setEnabled(true);
    await AutoSleepTimer.setHours(fromHour: 21, toHour: 7);
    await AutoSleepTimer.rememberMinutes(45);
    AutoSleepTimer.reload();
    expect(AutoSleepTimer.enabled.value, isTrue);
    expect(AutoSleepTimer.from.value, 21);
    expect(AutoSleepTimer.to.value, 7);
    expect(AutoSleepTimer.minutes, 45);

    await Hive.box('AppPrefs').putAll({
      AutoSleepTimer.fromKey: 24,
      AutoSleepTimer.toKey: 'x',
      AutoSleepTimer.minutesKey: 0,
    });
    AutoSleepTimer.reload();
    expect(AutoSleepTimer.from.value, 22);
    expect(AutoSleepTimer.to.value, 6);
    expect(AutoSleepTimer.minutes, 30);
  });

  group('the player', () {
    late PlayerController player;

    setUp(() async {
      Get.put<MusicServices>(_FakeMusic());
      player = Get.put(PlayerController());
      // The hours: all day, so whenever the test runs.
      await AutoSleepTimer.setHours(fromHour: 3, toHour: 3);
      await AutoSleepTimer.rememberMinutes(45);
    });
    tearDown(() async {
      Get.delete<PlayerController>();
      // End the controller's wait for the audio handler.
      Get.put<AudioHandler>(_FakeHandler());
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test('playing starts the sleep timer for the length picked last', () async {
      player.buttonState.value = PlayButtonState.playing;
      expect(player.isSleepTimerActive.isTrue, isFalse, reason: 'it is off');

      player.buttonState.value = PlayButtonState.paused;
      await AutoSleepTimer.setEnabled(true);
      player.buttonState.value = PlayButtonState.playing;
      expect(player.isSleepTimerActive.isTrue, isTrue);
      expect(player.timerDuration, 45 * 60);
    });

    test('one running is left as it is', () async {
      await AutoSleepTimer.setEnabled(true);
      expect(player.startSleepTimer(10), isTrue);
      player.autoSleep();
      expect(player.timerDuration, 10 * 60);
    });

    test('turned off, playing again leaves it off for now', () async {
      await AutoSleepTimer.setEnabled(true);
      player.autoSleep();
      expect(player.isSleepTimerActive.isTrue, isTrue);
      player.turnOffSleepTimer();
      expect(player.isSleepTimerActive.isTrue, isFalse);

      player.buttonState.value = PlayButtonState.paused;
      player.buttonState.value = PlayButtonState.playing;
      expect(player.isSleepTimerActive.isTrue, isFalse);
    });
  });

  testWidgets('the sheet switches it on and sets its hours', (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(body: AutoSleepTimerTile()),
    ));
    expect(find.text('autoSleepTimer'), findsOneWidget);
    expect(find.text('autoSleepTimerDes'), findsOneWidget);
    // Off: no hours to set.
    expect(find.text('10:00 PM'), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.text('autoSleepTimer'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(AutoSleepTimer.enabled.value, isTrue);
    expect(Hive.box('AppPrefs').get(AutoSleepTimer.key), isTrue);
    expect(find.text('autoSleepTimerFrom'), findsOneWidget);
    expect(find.text('10:00 PM'), findsOneWidget);
    expect(find.text('6:00 AM'), findsOneWidget);

    await tester.tap(find.text('10:00 PM'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('9:00 PM').last);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(AutoSleepTimer.from.value, 21);
    expect(Hive.box('AppPrefs').get(AutoSleepTimer.fromKey), 21);
    expect(find.text('9:00 PM'), findsOneWidget);

    // The same hour twice: all day.
    await tester.runAsync(() => AutoSleepTimer.setHours(toHour: 21));
    await tester.pump();
    expect(find.text('autoSleepTimerAllDay'), findsOneWidget);
  });
}
