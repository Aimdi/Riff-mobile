import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_builder.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_data.dart';
import 'package:harmonymusic/ui/screens/Home/home_metrics.dart';
import 'package:harmonymusic/ui/screens/Home/home_speed_dial.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/letter_art.dart';
import 'package:harmonymusic/utils/get_localization.dart';

void main() {
  group('speed dial looping', () {
    test('the loop starts on the first page for one to three pages', () {
      for (final pages in [1, 2, 3]) {
        expect(speedDialPageAt(speedDialLoopStart, pages), 0);
      }
    });

    test('a swipe right from the first page lands on the last', () {
      expect(speedDialPageAt(speedDialLoopStart - 1, 3), 2);
      expect(speedDialPageAt(speedDialLoopStart - 1, 2), 1);
    });

    test('a swipe left from the last page comes round to the first', () {
      expect(speedDialPageAt(speedDialLoopStart + 3, 3), 0);
    });

    test('no pages is page 0', () {
      expect(speedDialPageAt(42, 0), 0);
    });
  });

  group('speed dial page depth', () {
    test('a settled page is full size and fully visible', () {
      final look = speedDialPageLook(0);
      expect(look.scale, 1);
      expect(look.opacity, 1);
    });

    test('pages shrink and fade as they move away, either way', () {
      final half = speedDialPageLook(0.5);
      final left = speedDialPageLook(-1);
      final right = speedDialPageLook(1);
      expect(half.scale, lessThan(1));
      expect(right.scale, lessThan(half.scale));
      expect(right.opacity, lessThan(half.opacity));
      expect(left.scale, right.scale);
      expect(left.opacity, right.opacity);
    });

    test('never past one page away', () {
      expect(speedDialPageLook(3).scale, speedDialPageLook(1).scale);
      expect(speedDialPageLook(3).opacity, greaterThan(0));
    });
  });

  group('speed dial swipes', () {
    // 20 album pins + the dice = three pages; pins without art draw as
    // letter tiles, so nothing loads from the network.
    final items = [
      for (var i = 1; i <= 20; i++)
        HomeItem('pin$i',
            SpeedDialPin(type: 'album', id: 'a$i', title: 'Pin $i'))
    ];

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(GetMaterialApp(
        translations: Languages(),
        locale: const Locale('en'),
        theme: RiffTheme.dark(Colors.green),
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeSpeedDial(
                items: items, metrics: const HomeMetrics(420 - 47)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    bool onScreen(WidgetTester tester, String title) {
      final f = find.byWidgetPredicate(
          (w) => w is LetterArt && w.title == title);
      if (f.evaluate().isEmpty) return false;
      final r = tester.getRect(f);
      return r.left >= 0 && r.right <= 420;
    }

    testWidgets('a swipe right on the first page slides round to the last',
        (tester) async {
      await pump(tester);
      expect(onScreen(tester, 'Pin 1'), isTrue);

      await tester.fling(
          find.byType(PageView), const Offset(300, 0), 1500);
      await tester.pumpAndSettle();

      // Page 3 holds pins 18–20 (the dice took a slot on page 1).
      expect(onScreen(tester, 'Pin 18'), isTrue);
      expect(onScreen(tester, 'Pin 1'), isFalse);
    });

    testWidgets('mid-swipe the leaving page is smaller and fainter',
        (tester) async {
      await pump(tester);
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(PageView)));
      await gesture.moveBy(const Offset(-40, 0));
      await gesture.moveBy(const Offset(-150, 0));
      await tester.pump();

      final faded = tester
          .widgetList<Opacity>(find.descendant(
              of: find.byType(PageView), matching: find.byType(Opacity)))
          .where((o) => o.opacity < 1);
      expect(faded, isNotEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
