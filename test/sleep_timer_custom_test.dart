import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/sleep_timer_bottom_sheet.dart';
import 'package:hive/hive.dart';

void main() {
  test('lengths read in hours and minutes', () {
    expect(formatSleepMinutes(20), '20 minShort');
    expect(formatSleepMinutes(60), '1 hourShort');
    expect(formatSleepMinutes(95), '1 hourShort 35 minShort');
  });

  group('CustomSleepTimerDialog', () {
    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    });
    tearDown(() async {
      await Hive.box('AppPrefs').close();
    });

    /// A button that opens the dialog and keeps what it returned.
    Future<List<int?>> pumpOpener(WidgetTester tester) async {
      final results = <int?>[];
      await tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  results.add(await showCustomSleepTimerDialog(context)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('starts at 20 minutes; Start gives the length and keeps it',
        (tester) async {
      final results = await pumpOpener(tester);
      expect(find.text('20 minShort'), findsOneWidget);

      await tester.tap(find.text('startSleepTimer'));
      await tester.pumpAndSettle();
      expect(results, [20]);
      expect(Hive.box('AppPrefs').get(customSleepMinutesKey), 20);
    });

    testWidgets('opens at the length picked last time; the slider moves it',
        (tester) async {
      await Hive.box('AppPrefs').put(customSleepMinutesKey, 90);
      final results = await pumpOpener(tester);
      expect(find.text('1 hourShort 30 minShort'), findsOneWidget);

      // All the way right: four hours.
      await tester.drag(find.byType(Slider), const Offset(1000, 0));
      await tester.pumpAndSettle();
      expect(find.text('4 hourShort'), findsWidgets);

      await tester.tap(find.text('startSleepTimer'));
      await tester.pumpAndSettle();
      expect(results, [240]);
    });

    testWidgets('Cancel gives nothing', (tester) async {
      final results = await pumpOpener(tester);
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(results, [null]);
      expect(Hive.box('AppPrefs').get(customSleepMinutesKey), isNull);
    });
  });
}
