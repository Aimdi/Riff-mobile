import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/riff_equalizer.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/equalizer_sheet.dart';
import 'package:hive/hive.dart';

/// Most phones: five bands, ±15 dB.
const _phone = EqualizerLayout(
    centersHz: [60, 230, 910, 3600, 14000], minMb: -1500, maxMb: 1500);

class _FakePlayer extends GetxController implements PlayerController {
  EqualizerLayout? layout = _phone;
  int applied = 0;
  int openedPhones = 0;

  @override
  Future<EqualizerLayout?> equalizerLayout() async => layout;

  @override
  void applyAudioFx() => applied++;

  @override
  Future<void> openEqualizer() async => openedPhones++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('presets on the phone\'s bands', () {
    test('five bands where the presets are given: as they are', () {
      expect(equalizerLevelsFor(equalizerPresets['bassBooster']!, _phone),
          [600, 400, 0, 0, 0]);
      expect(equalizerLevelsFor(equalizerPresets['flat']!, _phone),
          [0, 0, 0, 0, 0]);
    });

    test('other bands: the curve between, level past the ends', () {
      const ten = EqualizerLayout(centersHz: [
        31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 //
      ], minMb: -1200, maxMb: 1200);
      final levels =
          equalizerLevelsFor(equalizerPresets['trebleBooster']!, ten);
      expect(levels.first, 0);
      expect(levels.last, 600);
      // Rising towards the treble, never past the ends.
      for (var i = 1; i < levels.length; i++) {
        expect(levels[i], greaterThanOrEqualTo(levels[i - 1]));
      }
      expect(levels[7], inInclusiveRange(400, 600));
    });

    test("kept within the phone's range", () {
      const narrow =
          EqualizerLayout(centersHz: [60, 14000], minMb: -300, maxMb: 300);
      expect(equalizerLevelsFor(equalizerPresets['rock']!, narrow), [300, 300]);
    });

    test('what the phone reports, or nothing', () {
      final l = EqualizerLayout.fromMap({
        'centersHz': [60, 230],
        'minMb': -1500,
        'maxMb': 1500
      })!;
      expect(l.centersHz, [60, 230]);
      expect(EqualizerLayout.fromMap(null), isNull);
      expect(EqualizerLayout.fromMap({'centersHz': [], 'minMb': 0, 'maxMb': 1}),
          isNull);
      expect(
          EqualizerLayout.fromMap({
            'centersHz': [60],
            'minMb': 100,
            'maxMb': -100
          }),
          isNull);
    });
  });

  group('the sheet', () {
    late _FakePlayer player;

    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
      player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    });
    tearDown(() async {
      Get.reset();
      await Hive.box('AppPrefs').close();
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(body: EqualizerSheet()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('off until turned on; a preset sets the bands', (tester) async {
      await open(tester);
      expect(RiffEqualizer.enabled, isFalse);
      expect(find.text('60 Hz'), findsOneWidget);
      expect(find.text('14 kHz'), findsOneWidget);
      // Off: the bands can't be moved.
      expect(
          tester.widget<Slider>(find.byType(Slider).first).onChanged, isNull);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(RiffEqualizer.enabled, isTrue);
      expect(RiffEqualizer.levelsMb, [0, 0, 0, 0, 0]);

      await tester.tap(find.text('eqPresetBassBooster'));
      await tester.pumpAndSettle();
      expect(RiffEqualizer.preset, 'bassBooster');
      expect(RiffEqualizer.levelsMb, [600, 400, 0, 0, 0]);
      expect(find.text('+6.0 dB'), findsOneWidget);
      expect(player.applied, 2);
    });

    testWidgets('a band moved by hand makes it Custom', (tester) async {
      await tester.runAsync(() => RiffEqualizer.save(enabled: true));
      await open(tester);
      await tester.drag(find.byType(Slider).first, const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(RiffEqualizer.preset, RiffEqualizer.custom);
      expect(RiffEqualizer.levelsMb.first, greaterThan(0));
      expect(find.text('eqPresetCustom'), findsOneWidget);

      // Reopened: the bands where they were left.
      final kept = RiffEqualizer.levelsMb;
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(tester.widget<Slider>(find.byType(Slider).first).value,
          kept.first.toDouble());
    });

    testWidgets("a phone without one: say so, and offer the phone's",
        (tester) async {
      player.layout = null;
      await open(tester);
      expect(find.text('equalizerUnavailable'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      await tester.tap(find.text('phoneEqualizer'));
      await tester.pumpAndSettle();
      expect(player.openedPhones, 1);
    });
  });
}
