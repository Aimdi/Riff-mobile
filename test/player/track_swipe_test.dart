import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/components/track_swipe.dart';

void main() {
  group('swipeNeighbours', () {
    ({bool canNext, bool canPrevious, int? next, int? previous}) n({
      int length = 5,
      int index = 2,
      bool shuffle = false,
      bool loop = false,
      bool radio = false,
    }) =>
        swipeNeighbours(
          queueLength: length,
          index: index,
          shuffleOn: shuffle,
          queueLoopOn: loop,
          radioOn: radio,
        );

    test('middle of the queue: both ways, both tracks known', () {
      final r = n();
      expect(r.canNext, isTrue);
      expect(r.canPrevious, isTrue);
      expect(r.next, 3);
      expect(r.previous, 1);
    });

    test('first track: no previous (previous never wraps)', () {
      final r = n(index: 0, loop: true);
      expect(r.canPrevious, isFalse);
      expect(r.previous, isNull);
    });

    test('last track: next only with queue loop or radio', () {
      expect(n(index: 4).canNext, isFalse);
      final looped = n(index: 4, loop: true);
      expect(looped.canNext, isTrue);
      expect(looped.next, 0);
      final radio = n(index: 4, radio: true);
      expect(radio.canNext, isTrue);
      expect(radio.next, isNull, reason: 'radio picks the next track later');
    });

    test('shuffle: both ways, tracks unknown', () {
      final r = n(index: 0, shuffle: true);
      expect(r.canNext, isTrue);
      expect(r.canPrevious, isTrue);
      expect(r.next, isNull);
      expect(r.previous, isNull);
    });

    test('a single looped track has nothing else to peek at', () {
      final r = n(length: 1, index: 0, loop: true);
      expect(r.canNext, isTrue);
      expect(r.next, isNull);
    });

    test('empty queue or stale index: nothing', () {
      expect(n(length: 0, index: 0).canNext, isFalse);
      expect(n(index: 7).canPrevious, isFalse);
      expect(n(index: -1).canNext, isFalse);
    });
  });

  group('blockedDragOffset', () {
    test('follows at first, then stiffens, never past the give', () {
      expect(blockedDragOffset(0, 36), 0);
      expect(blockedDragOffset(-4, 36), closeTo(-3.6, 0.1));
      expect(blockedDragOffset(-200, 36), closeTo(-30.5, 0.2));
      expect(blockedDragOffset(-100000, 36).abs(), lessThan(36));
      expect(blockedDragOffset(50, 36), -blockedDragOffset(-50, 36));
    });
  });

  group('TrackSwipe', () {
    const width = 300.0;
    late int nexts;
    late int previouses;
    late bool skipStarts;
    final key = ValueNotifier<String>('a');

    setUp(() {
      nexts = 0;
      previouses = 0;
      skipStarts = true;
      key.value = 'a';
    });

    Future<void> pump(WidgetTester tester,
        {bool canNext = true, bool canPrevious = true}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 60,
              child: ValueListenableBuilder<String>(
                valueListenable: key,
                builder: (context, k, _) => TrackSwipe(
                  currentKey: k,
                  current: const Text('playing'),
                  peekNext: const Text('next up'),
                  peekPrevious: const Text('before'),
                  canNext: canNext,
                  canPrevious: canPrevious,
                  onNext: () async {
                    nexts++;
                    return skipStarts;
                  },
                  onPrevious: () async {
                    previouses++;
                    return skipStarts;
                  },
                ),
              ),
            ),
          ),
        ),
      ));
    }

    double leftOf(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dx;

    testWidgets('drag left past a third skips to the next track',
        (tester) async {
      await pump(tester);
      final start = leftOf(tester, 'playing');

      final g =
          await tester.startGesture(tester.getCenter(find.byType(TrackSwipe)));
      await g.moveBy(const Offset(-20, 0));
      await g.moveBy(const Offset(-150, 0));
      await tester.pump();
      // Mid-drag: the playing track moved with the finger, the next one
      // is sliding in from the right.
      expect(leftOf(tester, 'playing'), lessThan(start - 140));
      expect(find.text('next up'), findsOneWidget);

      await g.up();
      await tester.pumpAndSettle();
      expect(nexts, 1);
      // Held on the incoming track until the player reports it.
      expect(leftOf(tester, 'next up'), closeTo(start, 1));

      key.value = 'b';
      await tester.pump();
      // The new title cross-fades in off screen, then the block settles.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(leftOf(tester, 'playing'), closeTo(start, 1));
      expect(find.text('next up'), findsNothing);
    });

    testWidgets('a short drag springs back without skipping', (tester) async {
      await pump(tester);
      final start = leftOf(tester, 'playing');
      final g =
          await tester.startGesture(tester.getCenter(find.byType(TrackSwipe)));
      await g.moveBy(const Offset(-20, 0));
      await g.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 500));
      await g.up();
      await tester.pumpAndSettle();
      expect(nexts, 0);
      expect(leftOf(tester, 'playing'), closeTo(start, 0.5));
    });

    testWidgets('a quick fling right goes to the previous track',
        (tester) async {
      await pump(tester);
      await tester.fling(find.byType(TrackSwipe), const Offset(60, 0), 1500);
      await tester.pumpAndSettle();
      expect(previouses, 1);
      expect(nexts, 0);
      await tester.pump(TrackSwipe.settleTimeout);
    });

    testWidgets('with nothing to skip to, the drag only gives a little',
        (tester) async {
      await pump(tester, canNext: false);
      final start = leftOf(tester, 'playing');
      final g =
          await tester.startGesture(tester.getCenter(find.byType(TrackSwipe)));
      // A real finger: many small moves, 220 px in all.
      for (var i = 0; i < 22; i++) {
        await g.moveBy(const Offset(-10, 0));
      }
      await tester.pump();
      final moved = start - leftOf(tester, 'playing');
      const give = width * TrackSwipe.blockedGive;
      expect(moved, lessThan(give));
      // Damped from the total travel, so it gets most of the way to the
      // give (accumulating the damped offset would stall far short of it).
      expect(moved, greaterThan(give * 0.75));
      await g.up();
      await tester.pumpAndSettle();
      expect(nexts, 0);
      expect(leftOf(tester, 'playing'), closeTo(start, 0.5));
    });

    testWidgets('a skip that does not start springs back', (tester) async {
      skipStarts = false;
      await pump(tester);
      final start = leftOf(tester, 'playing');
      await tester.fling(find.byType(TrackSwipe), const Offset(-200, 0), 1500);
      await tester.pumpAndSettle();
      expect(nexts, 1);
      expect(leftOf(tester, 'playing'), closeTo(start, 0.5));
      expect(find.text('next up'), findsNothing);
    });

    testWidgets('settles by itself if the track never changes', (tester) async {
      await pump(tester);
      final start = leftOf(tester, 'playing');
      await tester.fling(find.byType(TrackSwipe), const Offset(-200, 0), 1500);
      await tester.pumpAndSettle();
      expect(leftOf(tester, 'next up'), closeTo(start, 1));
      await tester.pump(TrackSwipe.settleTimeout);
      await tester.pumpAndSettle();
      expect(leftOf(tester, 'playing'), closeTo(start, 0.5));
    });
  });
}
