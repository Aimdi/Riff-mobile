import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/riff_header_bar.dart';

Widget _title(double width) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: const RiffPageTitle('Podcasts')),
        ),
      ),
    );

void main() {
  testWidgets('a tab title with room is drawn at full size', (tester) async {
    await tester.pumpWidget(_title(600));
    final text = find.text('Podcasts');
    expect(tester.getRect(text).width, tester.getSize(text).width);
  });

  testWidgets('squeezed, it shrinks whole rather than being cut',
      (tester) async {
    await tester.pumpWidget(_title(60));
    final text = find.text('Podcasts');
    final paragraph = tester.renderObject<RenderParagraph>(text);
    expect(paragraph.didExceedMaxLines, isFalse);
    // Laid out at full width, drawn scaled down into the 60 dp.
    expect(tester.getSize(text).width, greaterThan(60));
    expect(tester.getRect(text).width, lessThanOrEqualTo(60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reads as a heading', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_title(600));
    expect(tester.getSemantics(find.text('Podcasts')),
        matchesSemantics(label: 'Podcasts', isHeader: true));
    handle.dispose();
  });
}
