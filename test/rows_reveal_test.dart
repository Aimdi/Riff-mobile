import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/rows_reveal.dart';

/// A tall list of revealed rows; [reveal] hands its RowsReveal out.
class _List extends StatefulWidget {
  const _List({required this.reveal, this.reduce = false});
  final void Function(RowsReveal) reveal;
  final bool reduce;

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> with SingleTickerProviderStateMixin {
  late final _reveal = RowsReveal(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.reveal(_reveal);
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: widget.reduce),
          child: Scaffold(
            body: ListView(children: [
              const SizedBox(height: 100, child: Text('header')),
              for (var i = 0; i < 40; i++)
                _reveal.row(SizedBox(height: 100, child: Text('row $i'))),
            ]),
          ),
        ),
      );
}

double _opacity(WidgetTester tester, String text) {
  final fade =
      find.ancestor(of: find.text(text), matching: find.byType(Opacity));
  return fade.evaluate().isEmpty
      ? 1
      : tester.widget<Opacity>(fade.first).opacity;
}

double _rise(WidgetTester tester, String text) => tester
    .widget<Transform>(find
        .ancestor(of: find.text(text), matching: find.byType(Transform))
        .first)
    .transform
    .getTranslation()
    .y;

void main() {
  testWidgets('rows shown at once until played; then they fade in together',
      (tester) async {
    late RowsReveal reveal;
    await tester.pumpWidget(_List(reveal: (r) => reveal = r));
    expect(_opacity(tester, 'row 0'), 1);
    expect(_opacity(tester, 'header'), 1);

    reveal.play();
    await tester.pump();
    await tester.pump(RiffDurations.content * 0.5);
    expect(_opacity(tester, 'row 0'), inExclusiveRange(0, 1));
    expect(_opacity(tester, 'row 1'), _opacity(tester, 'row 0'));
    expect(_rise(tester, 'row 0'), greaterThan(0));
    expect(_opacity(tester, 'header'), 1);
    await tester.pumpAndSettle();
    expect(_opacity(tester, 'row 0'), 1);
    expect(_rise(tester, 'row 0'), 0);

    // A row the list builds only now, scrolled to, is already in.
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();
    expect(find.text('row 30'), findsOneWidget);
    expect(_opacity(tester, 'row 30'), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('Remove animations: no rise', (tester) async {
    late RowsReveal reveal;
    await tester.pumpWidget(_List(reveal: (r) => reveal = r, reduce: true));
    reveal.play();
    await tester.pump();
    expect(_rise(tester, 'row 0'), 0);
    await tester.pumpAndSettle();
    expect(_opacity(tester, 'row 0'), 1);
  });
}
