import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/components/track_crossfade.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';

Widget _cover(String track, {Future<void>? Function(BuildContext)? precache}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox.square(
          dimension: 100,
          child: TrackCrossfade(
            trackKey: track,
            precache: precache,
            child: Text('cover $track'),
          ),
        ),
      ),
    );

/// The opacity [text]'s layer is drawn at (1 when not faded).
double _opacity(WidgetTester tester, String text) {
  final fade = find.ancestor(
      of: find.text(text), matching: find.byType(FadeTransition));
  return tester.widget<FadeTransition>(fade.first).opacity.value;
}

void main() {
  testWidgets('the new cover fades in over the old, which stays whole',
      (tester) async {
    await tester.pumpWidget(_cover('a'));
    expect(_opacity(tester, 'cover a'), 1);

    await tester.pumpWidget(_cover('b'));
    await tester.pump(RiffDurations.trackChange ~/ 2);
    // Mid-change: the old one fully drawn underneath (no dip to the page),
    // the new one part way in on top.
    expect(_opacity(tester, 'cover a'), 1);
    final mid = _opacity(tester, 'cover b');
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));
    final stack = tester.widget<Stack>(find.descendant(
        of: find.byType(TrackCrossfade), matching: find.byType(Stack)));
    expect(stack.children, hasLength(2));

    await tester.pumpAndSettle();
    expect(find.text('cover a'), findsNothing);
    expect(_opacity(tester, 'cover b'), 1);
  });

  testWidgets('waits for the new cover to be decoded, then fades it in',
      (tester) async {
    final decoded = Completer<void>();
    await tester.pumpWidget(_cover('a'));
    await tester.pumpWidget(_cover('b', precache: (_) => decoded.future));
    await tester.pump(RiffDurations.trackChange);
    // Still the old one: the new one would pop in after its fade.
    expect(find.text('cover a'), findsOneWidget);
    expect(find.text('cover b'), findsNothing);

    decoded.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('cover b'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('cover a'), findsNothing);
  });

  testWidgets('decodes the new cover with precacheImage as the song changes',
      (tester) async {
    // A 1×1 PNG.
    final png = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, //
      0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
      0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
      0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
      0x60, 0x00, 0x02, 0x00, 0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB,
      0x3F, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
      0x60, 0x82,
    ]);
    Future<void>? decoding;
    Future<void> decode(BuildContext context) =>
        decoding = precacheImage(MemoryImage(png), context);
    await tester.pumpWidget(_cover('a', precache: decode));
    await tester.runAsync(() async {
      await tester.pumpWidget(_cover('b', precache: decode));
      // Real decoding happens outside the test clock: wait for it, however
      // long a busy machine takes.
      await decoding;
    });
    await tester.pump(RiffDurations.colour);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('cover b'), findsOneWidget);
    expect(find.text('cover a'), findsNothing);
  });

  testWidgets('never holds the old cover longer than maxHold', (tester) async {
    await tester.pumpWidget(_cover('a'));
    await tester.pumpWidget(
        _cover('b', precache: (_) => Completer<void>().future));
    await tester.pump(RiffDurations.colour);
    await tester.pumpAndSettle();
    expect(find.text('cover a'), findsNothing);
    expect(find.text('cover b'), findsOneWidget);
  });

  testWidgets('a skip back before the new cover is ready keeps the old one',
      (tester) async {
    await tester.pumpWidget(_cover('a'));
    await tester.pumpWidget(
        _cover('b', precache: (_) => Completer<void>().future));
    await tester.pumpWidget(_cover('a'));
    await tester.pump(RiffDurations.colour);
    await tester.pumpAndSettle();
    expect(find.text('cover a'), findsOneWidget);
    expect(find.text('cover b'), findsNothing);
  });

  testWidgets('quick skips: the covers underneath stay until the top is in',
      (tester) async {
    await tester.pumpWidget(_cover('a'));
    await tester.pumpWidget(_cover('b'));
    await tester.pump(RiffDurations.trackChange ~/ 3);
    await tester.pumpWidget(_cover('c'));
    // A frame past b's fade (it ends on the frame after its last).
    await tester.pump(RiffDurations.trackChange * 2 ~/ 3);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();
    // b is fully in now, so a can go; c is still on its way.
    expect(find.text('cover a'), findsNothing);
    expect(find.text('cover b'), findsOneWidget);
    expect(_opacity(tester, 'cover c'), lessThan(1));
    await tester.pumpAndSettle();
    expect(find.text('cover b'), findsNothing);
    expect(_opacity(tester, 'cover c'), 1);
  });

  testWidgets('the same track rebuilt updates in place', (tester) async {
    var settled = 0;
    Widget cover(String label) => Directionality(
          textDirection: TextDirection.ltr,
          child: TrackCrossfade(
            trackKey: 'a',
            onSettled: () => settled++,
            child: Text(label),
          ),
        );
    await tester.pumpWidget(cover('one'));
    await tester.pump();
    expect(settled, 1, reason: 'settled after the first build');
    await tester.pumpWidget(cover('two'));
    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsOneWidget);
    expect(find.byType(FadeTransition), findsOneWidget);
  });

  testWidgets('out of sight (animations paused), the new cover takes over',
      (tester) async {
    Widget hidden(String track) =>
        TickerMode(enabled: false, child: _cover(track));
    await tester.pumpWidget(hidden('a'));
    await tester.pumpWidget(hidden('b'));
    expect(find.text('cover a'), findsNothing);
    expect(_opacity(tester, 'cover b'), 1);
  });

  testWidgets('with Remove animations on, the change is near instant',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_cover('a'));
    await tester.pumpWidget(_cover('b'));
    await tester.pump(RiffDurations.trackChange ~/ 10);
    await tester.pump();
    expect(find.text('cover a'), findsNothing);
    expect(_opacity(tester, 'cover b'), 1);
  });
}
