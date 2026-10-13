import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/queue_undo.dart';
import 'package:harmonymusic/ui/widgets/snackbar.dart';

void main() {
  group('restoreQueuePositions', () {
    ({int index, int currentIndex, int shuffleIndex, int currentShuffleIndex})
        restore({
      required int length,
      required int current,
      required int index,
      int shuffleLength = 0,
      int currentShuffle = 0,
      int shuffleIndex = -1,
    }) =>
            restoreQueuePositions(
              queueLength: length,
              currentIndex: current,
              index: index,
              shuffleLength: shuffleLength,
              currentShuffleIndex: currentShuffle,
              shuffleIndex: shuffleIndex,
            );

    test('a song from after the playing one goes back in place', () {
      // [A, B, C*, D, E] minus D → [A, B, C*, E]; undo puts D at 3.
      final r = restore(length: 4, current: 2, index: 3);
      expect(r.index, 3);
      expect(r.currentIndex, 2);
    });

    test('a song from before the playing one pushes it back on', () {
      // [A, B, C*, D] minus A → [B, C*, D] (current 1); undo → current 2.
      final r = restore(length: 3, current: 1, index: 0);
      expect(r.index, 0);
      expect(r.currentIndex, 2);
    });

    test('playback moved on meanwhile: still lands before the playing one', () {
      // Removed B from [A, B, C, D, E], then skipped to D:
      // [A, C, D*, E] (current 2); undo → [A, B, C, D*, E] (current 3).
      final r = restore(length: 4, current: 2, index: 1);
      expect(r.index, 1);
      expect(r.currentIndex, 3);
    });

    test('positions past the end are clamped to the end', () {
      final r = restore(length: 2, current: 0, index: 9);
      expect(r.index, 2);
      expect(r.currentIndex, 0);
    });

    test('shuffle order is restored the same way', () {
      final r = restore(
          length: 4,
          current: 2,
          index: 3,
          shuffleLength: 4,
          currentShuffle: 1,
          shuffleIndex: 0);
      expect(r.shuffleIndex, 0);
      expect(r.currentShuffleIndex, 2);
    });

    test('no shuffle position recorded: appended to the shuffle order', () {
      final r = restore(
          length: 4, current: 2, index: 3, shuffleLength: 4, currentShuffle: 1);
      expect(r.shuffleIndex, 4);
      expect(r.currentShuffleIndex, 1);
    });

    test('an empty queue has no cursor to move', () {
      final r = restore(length: 0, current: 0, index: 0);
      expect(r.index, 0);
      expect(r.currentIndex, 0);
    });
  });

  group('mergeRestoredQueue', () {
    test('brings back the old queue and keeps songs queued since', () {
      final merged = mergeRestoredQueue<String>(
          ['A', 'B', 'C', 'D'], ['C', 'X'], (s) => s);
      expect(merged, ['A', 'B', 'C', 'D', 'X']);
    });

    test('nothing queued since: exactly the old queue', () {
      expect(
          mergeRestoredQueue<String>(['A', 'B'], ['A'], (s) => s), ['A', 'B']);
    });
  });

  group('snackbar', () {
    Future<BuildContext> contextOf(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      return ctx;
    }

    testWidgets('with an action: Undo button, text at the start, 4 s',
        (tester) async {
      final ctx = await contextOf(tester);
      final s = snackbar(ctx, 'Removed from queue',
          actionLabel: 'Undo', onAction: () {});
      expect(s.action?.label, 'Undo');
      expect(s.duration, snackbarActionDuration);
      expect(s.content, isA<Text>());
    });

    testWidgets('without an action: centred, 1 s as before', (tester) async {
      final ctx = await contextOf(tester);
      final s = snackbar(ctx, 'Saved');
      expect(s.action, isNull);
      expect(s.duration, const Duration(seconds: 1));
      expect(s.content, isA<Center>());
    });

    testWidgets('an explicit duration still wins', (tester) async {
      final ctx = await contextOf(tester);
      final s = snackbar(ctx, 'x',
          actionLabel: 'Undo',
          onAction: () {},
          duration: const Duration(seconds: 2));
      expect(s.duration, const Duration(seconds: 2));
    });

    testWidgets('tapping Undo runs the action', (tester) async {
      var undone = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => ScaffoldMessenger.of(c).showSnackBar(snackbar(
                  c, 'Queue cleared',
                  actionLabel: 'Undo', onAction: () => undone++)),
              child: const Text('clear'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, 1);
    });
  });
}
