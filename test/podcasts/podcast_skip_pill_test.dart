import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_segment_ui.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';

Widget _host({required bool inAdChapter, VoidCallback? onSkip}) => MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: Column(children: [
          PodcastSkipPill(
            visible: inAdChapter,
            label: 'Skip ad',
            onPressed: onSkip ?? () {},
          ),
        ]),
      ),
    );

void main() {
  testWidgets('Skip-ad pill appears for an ad chapter and skips on tap',
      (tester) async {
    var skipped = 0;
    await tester.pumpWidget(_host(inAdChapter: false));
    expect(find.byKey(const Key('skipAdPill')), findsNothing);

    await tester.pumpWidget(_host(inAdChapter: true, onSkip: () => skipped++));
    await tester.pumpAndSettle();
    final pill = find.byKey(const Key('skipAdPill'));
    expect(pill, findsOneWidget);
    expect(find.text('Skip ad'), findsOneWidget);
    // The visible pill is 36 tall (its 48 dp tap target is padding).
    final surface =
        find.descendant(of: pill, matching: find.byType(Material)).first;
    expect(tester.getSize(surface).height, RiffComponentSizes.skipPill);

    await tester.tap(pill);
    expect(skipped, 1);

    // Leaving the ad chapter removes it again.
    await tester.pumpWidget(_host(inAdChapter: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skipAdPill')), findsNothing);
  });

  testWidgets('Skip-ad pill is the accent with onAccent text', (tester) async {
    await tester.pumpWidget(_host(inAdChapter: true));
    await tester.pumpAndSettle();
    final theme = RiffTheme.dark(const Color(0xFF1DB954));
    final material = tester.widget<Material>(find.descendant(
        of: find.byKey(const Key('skipAdPill')),
        matching: find.byType(Material)));
    expect(material.color, theme.colorScheme.primary);
    final label = tester.widget<Text>(find.text('Skip ad'));
    expect(label.style?.color, theme.colorScheme.onPrimary);
  });
}
