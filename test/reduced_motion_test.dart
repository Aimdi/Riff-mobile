import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/components/cover_palette.dart';
import 'package:harmonymusic/ui/player/components/player_canvas_backdrop.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/riff_equalizer.dart';
import 'package:harmonymusic/ui/widgets/riff_marquee.dart';
import 'package:widget_marquee/widget_marquee.dart';

/// [child] with the phone's Remove animations on ([reduce]) or off.
Widget _app(Widget child, {required bool reduce}) => MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

const _longTitle = 'A song title much too long to fit on its line';

const _title = SizedBox(
  width: 120,
  child: RiffMarquee(
    delay: Duration(milliseconds: 300),
    duration: Duration(seconds: 5),
    child: Text(_longTitle, maxLines: 1),
  ),
);

const _palette = CoverPalette(
    fill: Color(0xFF203040), deep: Color(0xFF101820), glow: Color(0xFF406080));

void main() {
  testWidgets('a long title scrolls by, as before', (tester) async {
    await tester.pumpWidget(_app(_title, reduce: false));
    await tester.pump();
    expect(find.byType(Marquee), findsOneWidget);
    // Scrolling: the title runs twice, one after the other.
    expect(find.text(_longTitle), findsNWidgets(2));
    // Gone, its pending pauses run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('with Remove animations, it holds still and ends in "…"',
      (tester) async {
    await tester.pumpWidget(_app(_title, reduce: true));
    await tester.pumpAndSettle();
    expect(find.byType(Marquee), findsNothing);
    expect(find.text(_longTitle), findsOneWidget);
    final text = tester.widget<RichText>(find.descendant(
        of: find.byType(RiffMarquee), matching: find.byType(RichText)));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.maxLines, 1);
  });

  testWidgets(
      'the player canvas holds still with Remove animations, and drifts '
      'without', (tester) async {
    const canvas =
        SizedBox.square(dimension: 200, child: PlayerCanvasBackdrop());
    await tester.pumpWidget(_app(canvas, reduce: true));
    // Settles: nothing left moving.
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(_app(canvas, reduce: false));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('the cover glow drifts only without Remove animations',
      (tester) async {
    const glow = SizedBox.square(
        dimension: 200, child: CoverBackdrop(palette: _palette, drift: true));
    await tester.pumpWidget(_app(glow, reduce: true));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    // Turned off and on again: it drifts each time, and holds each time.
    for (var i = 0; i < 2; i++) {
      await tester.pumpWidget(_app(glow, reduce: false));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(_app(glow, reduce: true));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    }
  });

  testWidgets('the equalizer bars rest with Remove animations', (tester) async {
    const bars = RiffEqualizer(animate: true);
    await tester.pumpWidget(_app(bars, reduce: true));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(_app(bars, reduce: false));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
  });
}
