import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/services/podcast_segments.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/services/seek_time_label.dart';
import 'package:harmonymusic/ui/player/components/player_control.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero,
          current: const Duration(seconds: 60),
          total: const Duration(minutes: 3))
      .obs;
  @override
  final chapters = <PodcastChapter>[].obs;
  @override
  final podcastSegments = <PodcastSegment>[].obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('the length, or the time left', () {
    const at = Duration(seconds: 60);
    const total = Duration(minutes: 3);
    expect(seekBarEndLabel(at, total, timeLeft: false), '3:00');
    expect(seekBarEndLabel(at, total, timeLeft: true), '−2:00');
    // Long episodes, and past the end.
    expect(
        seekBarEndLabel(Duration.zero, const Duration(hours: 1, minutes: 5),
            timeLeft: true),
        '−1:05:00');
    expect(seekBarEndLabel(const Duration(minutes: 4), total, timeLeft: true),
        '−0:00');
    // An unknown length is a dash either way.
    expect(seekBarEndLabel(at, Duration.zero, timeLeft: true), '—');
    expect(seekBarEndLabel(at, Duration.zero, timeLeft: false), '—');
  });

  group('on the seek bar', () {
    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
      Get.put<PlayerController>(_FakePlayer());
    });
    tearDown(() async {
      Get.reset();
      SeekTimeLabel.showsTimeLeft.value = false;
      await Hive.box('AppPrefs').close();
    });

    testWidgets('a tap swaps the length for the time left, and back',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(body: PlayerSeekScrubber()),
      ));
      expect(find.text('1:00'), findsOneWidget);
      expect(find.text('3:00'), findsOneWidget);

      await tester.tap(find.text('3:00'));
      await tester.pumpAndSettle();
      expect(find.text('−2:00'), findsOneWidget);
      expect(Hive.box('AppPrefs').get(SeekTimeLabel.key), isTrue);

      await tester.tap(find.text('−2:00'));
      await tester.pumpAndSettle();
      expect(find.text('3:00'), findsOneWidget);
      expect(Hive.box('AppPrefs').get(SeekTimeLabel.key), isFalse);
    });

    testWidgets('TalkBack reads it as a button that says what it does',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(body: PlayerSeekScrubber()),
      ));
      expect(
          tester.getSemantics(find.bySemanticsLabel('3:00')),
          containsSemantics(
            label: '3:00',
            isButton: true,
            hasTapAction: true,
            onTapHint: 'showTimeLeft',
          ));
      semantics.dispose();
    });
  });
}
