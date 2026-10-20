import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/riff_motion.dart';

Widget _app(Widget child, {bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: child),
      ),
    );

double _opacityOf(WidgetTester tester, Finder f) {
  final opacity = find.ancestor(of: f, matching: find.byType(Opacity));
  if (opacity.evaluate().isEmpty) return 1;
  return tester.widget<Opacity>(opacity.first).opacity;
}

void main() {
  testWidgets('RiffFadeIn fades loaded content in, then leaves it alone',
      (tester) async {
    await tester.pumpWidget(_app(const RiffFadeIn(child: Text('content'))));
    expect(_opacityOf(tester, find.text('content')), 0);

    await tester.pump(RiffDurations.content ~/ 2);
    final mid = _opacityOf(tester, find.text('content'));
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));

    await tester.pumpAndSettle();
    // Done: fully shown, in place.
    expect(_opacityOf(tester, find.text('content')), 1);
  });

  testWidgets('RiffFadeIn keeps its child\'s state when the fade ends',
      (tester) async {
    var inits = 0;
    await tester.pumpWidget(_app(RiffFadeIn(child: _Probe(() => inits++))));
    await tester.pumpAndSettle();
    expect(inits, 1);
  });

  testWidgets('RiffFadeIn doesn\'t move content with Remove animations on',
      (tester) async {
    await tester.pumpWidget(
        _app(const RiffFadeIn(child: Text('content')), reduce: true));
    await tester.pump(RiffDurations.content ~/ 2);
    final transform = tester.widget<Transform>(find
        .ancestor(of: find.text('content'), matching: find.byType(Transform))
        .first);
    expect(transform.transform.getTranslation().y, 0);
  });

  testWidgets('RiffSwitcher crossfades to the new child', (tester) async {
    Widget heart(bool liked) => _app(RiffSwitcher(
        pop: true,
        child: Icon(liked ? Icons.favorite : Icons.favorite_border,
            key: ValueKey(liked))));
    await tester.pumpWidget(heart(false));
    await tester.pumpWidget(heart(true));
    await tester.pump(RiffDurations.select ~/ 2);
    // Both while it switches, then only the new one.
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byType(ScaleTransition), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('RiffSwitcher only fades with Remove animations on',
      (tester) async {
    Widget heart(bool liked) => _app(
        RiffSwitcher(
            pop: true,
            child: Icon(liked ? Icons.favorite : Icons.favorite_border,
                key: ValueKey(liked))),
        reduce: true);
    await tester.pumpWidget(heart(false));
    await tester.pumpWidget(heart(true));
    await tester.pump();
    expect(
        find.descendant(
            of: find.byType(RiffSwitcher),
            matching: find.byType(ScaleTransition)),
        findsNothing);
  });

  testWidgets('RiffSwitcher: the child leaving takes no taps', (tester) async {
    var oldTaps = 0;
    Widget button(bool done) => _app(RiffSwitcher(
        child: done
            ? const Text('done', key: ValueKey('done'))
            : TextButton(
                key: const ValueKey('get'),
                onPressed: () => oldTaps++,
                child: const Text('get'))));
    await tester.pumpWidget(button(false));
    await tester.pumpWidget(button(true));
    await tester.pump(RiffDurations.select ~/ 4);
    await tester.tap(find.text('get'), warnIfMissed: false);
    expect(oldTaps, 0);
  });

  testWidgets('RiffSwitcher: a leaving child keeps its state', (tester) async {
    var inits = 0;
    Widget probe(bool next) => _app(RiffSwitcher(
        child: next
            ? const Text('next', key: ValueKey('next'))
            : _Probe(() => inits++, key: const ValueKey('probe'))));
    await tester.pumpWidget(probe(false));
    await tester.pumpWidget(probe(true));
    await tester.pumpAndSettle();
    expect(inits, 1);
  });

  testWidgets('riffFadeInFrame: shown at once when already in memory',
      (tester) async {
    await tester.pumpWidget(_app(Builder(
        builder: (context) =>
            riffFadeInFrame(context, const Text('cover'), null, true))));
    expect(find.byType(AnimatedOpacity), findsNothing);

    await tester.pumpWidget(_app(Builder(
        builder: (context) =>
            riffFadeInFrame(context, const Text('cover'), null, false))));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0);
  });
}

class _Probe extends StatefulWidget {
  const _Probe(this.onInit, {super.key});
  final VoidCallback onInit;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}
