import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/theme/riff_spacing.dart';
import 'package:harmonymusic/ui/widgets/cover_tap_target.dart';

void main() {
  Widget cover(VoidCallback onTap) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 160,
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: Colors.grey)),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CoverTapTarget(
                      label: 'Play',
                      inset: RiffSpacing.xs,
                      onTap: onTap,
                      child: const SizedBox.square(
                          key: ValueKey('badge'), dimension: 30),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  testWidgets('the badge stays small; a 48 dp square at the corner plays',
      (tester) async {
    var plays = 0;
    await tester.pumpWidget(cover(() => plays++));
    final badge = tester.getRect(find.byKey(const ValueKey('badge')));
    expect(badge.size, const Size(30, 30));
    // Just off the badge, up and to the left, still in the square.
    await tester.tapAt(badge.topLeft - const Offset(6, 6));
    expect(plays, 1);
    expect(tester.getSize(find.byType(CoverTapTarget)),
        const Size.square(RiffSizes.touch));
  });

  testWidgets('reads as one button, and meets the 48 dp guideline',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(cover(() {}));
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
