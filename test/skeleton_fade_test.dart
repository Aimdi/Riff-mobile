import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/shimmer_widgets/reveal.dart';
import 'package:harmonymusic/ui/widgets/shimmer_widgets/skeleton_fade.dart';

/// The opacity [text] is painted at (the nearest Opacity above it).
double _opacityOf(WidgetTester tester, String text) => tester
    .widget<Opacity>(find
        .ancestor(of: find.text(text), matching: find.byType(Opacity))
        .first)
    .opacity;

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// A [SkeletonFadeIn] showing 'skeleton' while [loading], then 'content'.
Widget _skeleton(bool loading) => _app(SkeletonFadeIn(
      skeleton: const Text('skeleton'),
      child: loading ? null : const Text('content'),
    ));

void main() {
  group('SkeletonFadeIn', () {
    testWidgets('content arriving after the skeleton fades in', (tester) async {
      await tester.pumpWidget(_skeleton(true));
      expect(find.text('skeleton'), findsOneWidget);
      expect(find.text('content'), findsNothing);

      await tester.pumpWidget(_skeleton(false));
      expect(find.text('skeleton'), findsNothing);
      expect(_opacityOf(tester, 'content'), 0);

      await tester.pump(RiffDurations.content ~/ 2);
      final mid = _opacityOf(tester, 'content');
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1));

      await tester.pumpAndSettle();
      expect(_opacityOf(tester, 'content'), 1);
    });

    testWidgets('content there from the start just shows', (tester) async {
      await tester.pumpWidget(_skeleton(false));
      expect(find.text('content'), findsOneWidget);
      expect(
          find.ancestor(
              of: find.text('content'), matching: find.byType(Opacity)),
          findsNothing);
    });

    testWidgets('loading again fades the new content in too', (tester) async {
      await tester.pumpWidget(_skeleton(false));
      await tester.pumpWidget(_skeleton(true));
      await tester.pumpWidget(_skeleton(false));
      await tester.pump(RiffDurations.content ~/ 2);
      expect(_opacityOf(tester, 'content'), lessThan(1));
      await tester.pumpAndSettle();
      expect(_opacityOf(tester, 'content'), 1);
    });
  });

  group('LoadedRowsFade', () {
    testWidgets(
        'the rows replacing the skeleton fade in; rows scrolled in later '
        'just appear', (tester) async {
      final fade = LoadedRowsFade();
      var loading = true;
      late StateSetter setLoading;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(_app(StatefulBuilder(builder: (context, set) {
        setLoading = set;
        return ListView.builder(
          controller: scroll,
          itemExtent: 100,
          itemCount: loading ? 1 : 50,
          itemBuilder: (context, i) {
            if (loading) {
              fade.skeleton();
              return const Text('skeleton');
            }
            return fade.row(Text('row $i'));
          },
        );
      })));

      setLoading(() => loading = false);
      await tester.pump();
      await tester.pump(RiffDurations.content ~/ 2);
      expect(_opacityOf(tester, 'row 0'), lessThan(1));
      await tester.pumpAndSettle();
      expect(_opacityOf(tester, 'row 0'), 1);

      // Well after the load: a row scrolled into view is there at once.
      scroll.jumpTo(3000);
      await tester.pump();
      expect(find.text('row 35'), findsOneWidget);
      expect(_opacityOf(tester, 'row 35'), 1);
    });

    testWidgets('without a skeleton, no row fades', (tester) async {
      final fade = LoadedRowsFade();
      await tester.pumpWidget(_app(ListView(
        children: [for (var i = 0; i < 3; i++) fade.row(Text('row $i'))],
      )));
      expect(_opacityOf(tester, 'row 0'), 1);
    });
  });

  group('RiffReveal', () {
    Widget reveal(bool open) => _app(Column(children: [
          RiffReveal(
              child:
                  open ? const SizedBox(height: 60, child: Text('row')) : null),
          const Text('below'),
        ]));

    double revealHeight(WidgetTester tester) =>
        tester.getSize(find.byType(RiffReveal)).height;

    testWidgets('grows open, and folds away keeping the row until shut',
        (tester) async {
      await tester.pumpWidget(reveal(false));
      expect(find.text('row'), findsNothing);
      expect(revealHeight(tester), 0);

      await tester.pumpWidget(reveal(true));
      await tester.pump(RiffDurations.select ~/ 2);
      expect(revealHeight(tester), inExclusiveRange(0, 60));
      await tester.pumpAndSettle();
      expect(revealHeight(tester), 60);

      await tester.pumpWidget(reveal(false));
      await tester.pump(RiffDurations.select ~/ 2);
      // Still there while it folds.
      expect(find.text('row'), findsOneWidget);
      expect(revealHeight(tester), inExclusiveRange(0, 60));
      await tester.pumpAndSettle();
      expect(find.text('row'), findsNothing);
      expect(revealHeight(tester), 0);
    });

    testWidgets('a row there from the start takes its size at once',
        (tester) async {
      await tester.pumpWidget(reveal(true));
      expect(revealHeight(tester), 60);
    });
  });

  group('RiffPaneSwitcher', () {
    Widget panes(String pane) => _app(SizedBox(
          width: 300,
          height: 400,
          child: RiffPaneSwitcher(
            child: Align(
              key: ValueKey(pane),
              alignment: Alignment.topLeft,
              child: Text(pane),
            ),
          ),
        ));

    testWidgets('each pane fills the space, and they crossfade',
        (tester) async {
      await tester.pumpWidget(panes('a'));
      expect(tester.getSize(find.byKey(const ValueKey('a'))),
          const Size(300, 400));

      await tester.pumpWidget(panes('b'));
      await tester.pump(RiffDurations.content ~/ 2);
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('b'))),
          const Size(300, 400));

      await tester.pumpAndSettle();
      expect(find.text('a'), findsNothing);
      expect(find.text('b'), findsOneWidget);
    });
  });
}
