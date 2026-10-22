import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/riff_fast_scroller.dart';

const _extent = 64.0;

Widget _list(int count, {String? Function(int)? labelFor}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: RiffFastScroller(
            itemExtent: _extent,
            labelFor: labelFor,
            builder: (context, controller) => ListView.builder(
              key: const ValueKey('list'),
              controller: controller,
              itemExtent: _extent,
              itemCount: count,
              itemBuilder: (_, i) => Text('row $i'),
            ),
          ),
        ),
      ),
    );

double _thumbOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find
        .ancestor(
            of: find.byType(ExcludeSemantics).last,
            matching: find.byType(AnimatedOpacity))
        .first)
    .opacity;

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
  testWidgets('shows on a long list once it scrolls, then fades away',
      (tester) async {
    await tester.pumpWidget(_list(200));
    expect(_thumbOpacity(tester), 0);

    await tester.drag(
        find.byKey(const ValueKey('list')), const Offset(0, -300));
    await tester.pump();
    expect(_thumbOpacity(tester), 1);
    expect(find.byKey(const ValueKey('fastScrollThumb')), findsOneWidget);

    await tester.pump(RiffFastScroll.linger);
    await tester.pumpAndSettle();
    expect(_thumbOpacity(tester), 0);
  });

  testWidgets('a short list never shows it', (tester) async {
    await tester.pumpWidget(_list(12));
    await tester.drag(
        find.byKey(const ValueKey('list')), const Offset(0, -200));
    await tester.pump();
    expect(_thumbOpacity(tester), 0);
  });

  testWidgets(
      'dragging the thumb moves through the whole list, with the '
      'letter in a bubble', (tester) async {
    await tester.pumpWidget(_list(200, labelFor: (i) => 'L$i'));
    await tester.drag(
        find.byKey(const ValueKey('list')), const Offset(0, -100));
    await tester.pump();

    final thumb =
        tester.getCenter(find.byKey(const ValueKey('fastScrollThumb')));
    final gesture = await tester.startGesture(thumb);
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveTo(Offset(thumb.dx, 599));
    await tester.pump();
    final position = _position(tester);
    expect(position.pixels, position.maxScrollExtent);
    // The bubble names the row at the top.
    expect(find.textContaining('L'), findsWidgets);
    expect(
        find.text('L${(position.pixels / _extent).floor()}'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(find.text('L${(position.pixels / _extent).floor()}'), findsNothing);
    await tester.pumpAndSettle(RiffFastScroll.linger);
  });

  group('songFastScrollLabels', () {
    MediaItem song(String title, [String artist = '']) =>
        MediaItem(id: title, title: title, artist: artist);

    test('by title: its first letter', () {
      final labels = songFastScrollLabels(
          [song('abba'), song('Beatles'), song('zz top')])!;
      expect([labels(0), labels(1), labels(2)], ['A', 'B', 'Z']);
    });

    test('by artist when not by title', () {
      final labels = songFastScrollLabels(
          [song('Z', 'Adele'), song('A', 'Blur'), song('M', 'Coldplay')])!;
      expect([labels(0), labels(1), labels(2)], ['A', 'B', 'C']);
    });

    test('descending works too; digits and symbols read #', () {
      final labels =
          songFastScrollLabels([song('Zebra'), song('apple'), song('1999')])!;
      expect([labels(0), labels(1), labels(2)], ['Z', 'A', '#']);
    });

    test('in no such order (a playlist, by date): no bubble', () {
      expect(
          songFastScrollLabels(
              [song('M', 'Z'), song('A', 'A'), song('Z', 'B')]),
          isNull);
    });
  });
}
