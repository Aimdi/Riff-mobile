import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/podcast_follow_button.dart';

Widget _app(Widget child) => MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('Follow and Following crossfade, the width easing between',
      (tester) async {
    Widget button(bool following) => _app(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PodcastFollowButton(following: following, onPressed: () {})
          ],
        ));
    await tester.pumpWidget(button(false));
    final followWidth = tester.getSize(find.bySubtype<FilledButton>()).width;
    await tester.pumpWidget(button(true));
    await tester.pumpAndSettle();
    final followingWidth =
        tester.getSize(find.bySubtype<OutlinedButton>()).width;
    expect(followingWidth, isNot(followWidth));

    await tester.pumpWidget(button(false));
    await tester.pump();
    await tester.pump(RiffDurations.select ~/ 2);
    // Both while they switch.
    expect(find.bySubtype<OutlinedButton>(), findsOneWidget);
    expect(find.bySubtype<FilledButton>(), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.bySubtype<OutlinedButton>(), findsNothing);
    expect(tester.getSize(find.byType(PodcastFollowButton)).width,
        moreOrLessEquals(followWidth));
  });

  testWidgets('a pill stretched across its slot stays stretched',
      (tester) async {
    // As Library's podcast grid lays it under each cover.
    Widget button(bool following) => _app(SizedBox(
          width: 200,
          child: PodcastFollowButton(
              compact: true, following: following, onPressed: () {}),
        ));
    await tester.pumpWidget(button(false));
    expect(tester.getSize(find.bySubtype<FilledButton>()).width, 200);

    await tester.pumpWidget(button(true));
    await tester.pump();
    await tester.pump(RiffDurations.select ~/ 2);
    expect(tester.getSize(find.bySubtype<FilledButton>()).width, 200);
    expect(tester.getSize(find.bySubtype<OutlinedButton>()).width, 200);

    await tester.pumpAndSettle();
    expect(tester.getSize(find.bySubtype<OutlinedButton>()).width, 200);
  });
}
