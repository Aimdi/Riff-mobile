import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/riff_header_bar.dart';

double _hairlineOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.ancestor(
        of: find.byType(Divider), matching: find.byType(AnimatedOpacity)))
    .opacity;

Widget _list() => ListView(
      children: [
        for (var i = 0; i < 60; i++) SizedBox(height: 40, child: Text('$i'))
      ],
    );

void main() {
  testWidgets('pinned header: hairline only while content is scrolled under',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: Column(children: [
          const RiffHeaderBar(child: SizedBox(height: 48)),
          Expanded(child: _list()),
        ]),
      ),
    ));
    expect(_hairlineOpacity(tester), 0);

    await tester.drag(find.text('3'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(_hairlineOpacity(tester), 1);

    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(_hairlineOpacity(tester), 0);
  });

  testWidgets('header that scrolls with the content never shows it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: ListView(children: [
          const RiffHeaderBar(child: SizedBox(height: 48)),
          for (var i = 0; i < 60; i++) SizedBox(height: 40, child: Text('$i')),
        ]),
      ),
    ));
    await tester.drag(find.text('3'), const Offset(0, -30));
    await tester.pumpAndSettle();
    expect(_hairlineOpacity(tester), 0);
  });

  testWidgets('RiffScrollUnder draws it above the content, no layout change',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: Column(children: [
          const SizedBox(height: 48),
          Expanded(child: RiffScrollUnder(child: _list())),
        ]),
      ),
    ));
    final before = tester.getTopLeft(find.text('0'));
    expect(before.dy, 48);
    expect(_hairlineOpacity(tester), 0);
    await tester.drag(find.text('3'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(_hairlineOpacity(tester), 1);
  });
}
