import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/theme/riff_spacing.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/riff_sheet.dart';

const _long = 'Download new episodes automatically, on Wi-Fi only';

Widget _app(Widget child) => MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('a short label: one line, 32 dp tall, as before', (tester) async {
    await tester.pumpWidget(_app(Wrap(children: [
      RiffChoiceChip(label: 'On', icon: Icons.check, onTap: () {}),
    ])));
    expect(tester.getSize(find.byType(RiffChoiceChip)).height,
        RiffSizes.chipHeight);
  });

  testWidgets('a label too long for its line wraps inside the chip',
      (tester) async {
    // An overflow fails the test: the label ran off past the edge.
    await tester.pumpWidget(_app(Center(
      child: SizedBox(
        width: 200,
        child: Wrap(children: [
          RiffChoiceChip(label: _long, icon: Icons.download, onTap: () {}),
        ]),
      ),
    )));
    final chip = tester.getSize(find.byType(RiffChoiceChip));
    expect(chip.width, lessThanOrEqualTo(200));
    expect(chip.height, greaterThan(RiffSizes.chipHeight));
  });

  testWidgets('in a row that scrolls sideways, never wider than the screen',
      (tester) async {
    await tester.pumpWidget(_app(SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        RiffChoiceChip(label: _long * 3, onTap: () {}),
        RiffChoiceChip(label: 'Off', onTap: () {}),
      ]),
    )));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getSize(find.byType(RiffChoiceChip).first).width,
        lessThanOrEqualTo(screen.width));
    expect(find.text('Off'), findsOneWidget);
  });
}
