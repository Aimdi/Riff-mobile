import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Stats/stats_screen.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

String _dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  setUp(() async {
    await Hive.openBox('SongStats', bytes: Uint8List(0));
    await Hive.openBox('DailyStats', bytes: Uint8List(0));
    final now = DateTime.now();
    for (var d = 0; d < 7; d++) {
      await Hive.box('DailyStats')
          .put(_dayKey(now.subtract(Duration(days: d))), {'plays': 10 + d});
    }
    await Hive.box('SongStats').put('song0000001', {
      'title': 'A song',
      'artist': 'An artist',
      'plays': 12,
      'seconds': 2400,
    });
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  Future<void> pumpStats(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const StatsScreen(),
    ));
    await tester.pump();
  }

  testWidgets('the stat tiles fit on a small phone at large text',
      (tester) async {
    await pumpStats(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
    // Each pair of tiles is one height.
    final plays = tester.getRect(find
        .ancestor(of: find.text('plays'), matching: find.byType(Container))
        .first);
    final hours = tester.getRect(find
        .ancestor(of: find.text('hours'), matching: find.byType(Container))
        .first);
    expect(plays.height, hours.height);
  });

  testWidgets("the week's bars are labelled by weekday, today's brighter",
      (tester) async {
    await pumpStats(tester);
    final context = tester.element(find.byType(StatsScreen));
    final letters = MaterialLocalizations.of(context).narrowWeekdays;
    final theme = Theme.of(context);
    final now = DateTime.now();
    // Today's letter is the last bar's; it may also name another day
    // ("T", "S"), so look at the last one found.
    final today = find.text(letters[now.weekday % 7]).last;
    expect(
        tester.widget<Text>(today).style?.color, theme.colorScheme.onSurface);
    final yesterday = now.subtract(const Duration(days: 1));
    final label = MaterialLocalizations.of(context).formatFullDate(yesterday);
    expect(find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}: 11 ')),
        findsOneWidget);
  });
}
