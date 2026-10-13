import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/song_row_swipe.dart';

void main() {
  late int queued;
  late int playNext;

  Future<void> pump(WidgetTester tester) async {
    queued = 0;
    playNext = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Slidable(
              key: const ValueKey('row'),
              endActionPane: songRowQueuePane(
                background: Colors.green,
                foreground: Colors.black,
                onEnqueue: () => queued++,
                onPlayNext: () => playNext++,
              ),
              child: const SizedBox(
                height: 64,
                width: double.infinity,
                child: Text('Get Lucky'),
              ),
            ),
          ],
        ),
      ),
    ));
  }

  double rowLeft(WidgetTester tester) =>
      tester.getTopLeft(find.text('Get Lucky')).dx;

  testWidgets('a swipe all the way across queues the song and springs back',
      (tester) async {
    await pump(tester);
    final start = rowLeft(tester);
    // A finger moves over many frames; the full-swipe pane is only built
    // once the drag passes the buttons, so pump between the moves.
    final g =
        await tester.startGesture(tester.getCenter(find.text('Get Lucky')));
    await g.moveBy(const Offset(-20, 0));
    await tester.pump();
    await g.moveBy(const Offset(-350, 0));
    await tester.pump();
    await g.moveBy(const Offset(-330, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(queued, 1);
    expect(playNext, 0);
    // Still in the list, back in place.
    expect(find.text('Get Lucky'), findsOneWidget);
    expect(rowLeft(tester), closeTo(start, 0.5));
  });

  testWidgets('a short swipe only opens the buttons', (tester) async {
    await pump(tester);
    await tester.drag(find.text('Get Lucky'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(queued, 0);
    expect(find.byIcon(Icons.merge), findsOneWidget);

    await tester.tap(find.byIcon(Icons.next_plan_outlined));
    await tester.pumpAndSettle();
    expect(playNext, 1);
    expect(queued, 0);
  });
}
