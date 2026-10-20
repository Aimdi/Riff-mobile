import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/riff_equalizer.dart';

Widget _app(bool animate, {bool reduce = false}) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: Scaffold(body: Center(child: RiffEqualizer(animate: animate))),
        ),
      ),
    );

/// The Home equalizer (the speed dial's playing tile) settling to its
/// resting waveform when playback stops, rather than snapping to it.
void main() {
  testWidgets('stopping eases the bars down to rest, then nothing ticks',
      (tester) async {
    await tester.pumpWidget(_app(true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(_app(false));
    await tester.pump(const Duration(milliseconds: 50));
    // Still settling.
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('at rest from the start: nothing to ease', (tester) async {
    await tester.pumpWidget(_app(false));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('with Remove animations, stopping doesn\'t ease either',
      (tester) async {
    await tester.pumpWidget(_app(true, reduce: true));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(_app(false, reduce: true));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
