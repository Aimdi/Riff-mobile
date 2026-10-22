import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Audiobooks/audiobook_hero_card.dart';

void main() {
  Widget card({
    VoidCallback? onPlay,
    VoidCallback? onLongPress,
    int? secondsLeft,
    String detail = '',
    double width = 800,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
              child: SizedBox(
            width: width,
            child: AudiobookHeroCard(
              cover: const ColoredBox(color: Color(0xFF336699)),
              title: 'Project Hail Mary',
              author: 'Andy Weir',
              detail: detail,
              progress: 0.4,
              secondsLeft: secondsLeft,
              onPlay: onPlay ?? () {},
              onLongPress: onLongPress,
            ),
          )),
        ),
      );

  testWidgets('shows the book, how far in, and the time left', (tester) async {
    await tester.pumpWidget(card(secondsLeft: 3 * 3600 + 20 * 60));
    expect(find.text('Project Hail Mary'), findsOneWidget);
    expect(find.text('Andy Weir'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0.4);
    expect(find.textContaining('left'), findsOneWidget);
  });

  testWidgets('no time-left line when the length is unknown', (tester) async {
    await tester.pumpWidget(card(detail: 'Chapter 3 of 20'));
    expect(find.text('Chapter 3 of 20'), findsOneWidget);
    expect(find.textContaining('left'), findsNothing);
  });

  testWidgets(
      'the card and its play button pick the book up; long press '
      'opens it', (tester) async {
    var plays = 0;
    var opens = 0;
    await tester
        .pumpWidget(card(onPlay: () => plays++, onLongPress: () => opens++));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    expect(plays, 1);
    await tester.tap(find.text('Project Hail Mary'));
    await tester.pumpAndSettle();
    expect(plays, 2);
    await tester.longPress(find.text('Project Hail Mary'));
    await tester.pumpAndSettle();
    expect(opens, 1);
  });

  testWidgets('reads as one button with the book and time left',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(card(secondsLeft: 600));
    expect(
        find.bySemanticsLabel(
            RegExp(r'^Project Hail Mary, Andy Weir, .*left$')),
        findsOneWidget);
    handle.dispose();
  });

  group('the play button', () {
    final cover = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xFF336699));
    final play = find.byIcon(Icons.play_arrow_rounded);

    testWidgets('on a phone sits on the cover', (tester) async {
      await tester.pumpWidget(card(width: 360));
      expect(tester.getRect(cover).contains(tester.getCenter(play)), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a small phone too, and the card still fits',
        (tester) async {
      await tester.pumpWidget(card(width: 300, detail: 'Chapter 7 of 12'));
      expect(tester.getRect(cover).contains(tester.getCenter(play)), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a wide screen has its own place at the end',
        (tester) async {
      await tester.pumpWidget(card());
      expect(
          tester.getCenter(play).dx, greaterThan(tester.getRect(cover).right));
    });
  });
}
