import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_builder.dart';
import 'package:harmonymusic/ui/screens/Home/home_metrics.dart';
import 'package:harmonymusic/ui/screens/Home/shelf_header_art.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

Widget _app(Widget child) => MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: child),
    );

HomeShelfData _shelf({String? art, bool round = false}) => HomeShelfData(
      id: 'yt:Nova Hart',
      title: 'Nova Hart',
      items: const [],
      headerArt: art,
      headerArtRound: round,
    );

void main() {
  testWidgets('a name keeps its capitals under its small line', (tester) async {
    await tester.pumpWidget(_app(const Column(children: [
      RiffSectionHeader('Nova Hart', kicker: 'Similar to', titleIsName: true),
      RiffSectionHeader('Music Videos For You'),
    ])));
    expect(find.text('Similar to'), findsOneWidget);
    expect(find.text('Nova Hart'), findsOneWidget);
    expect(find.text('Music videos for you'), findsOneWidget);
    // A name may wrap rather than lose its end; a heading stays one line.
    expect(tester.widget<Text>(find.text('Nova Hart')).maxLines, 2);
    expect(tester.widget<Text>(find.text('Music videos for you')).maxLines, 1);
  });

  testWidgets('the picture sits before the header and is left to the text',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(RiffSectionHeader(
      'Nova Hart',
      kicker: 'Similar to',
      titleIsName: true,
      art: ShelfHeaderArt.of(
          _shelf(art: 'https://example.com/nova.jpg', round: true)),
    )));
    final art = find.byType(ShelfHeaderArt);
    expect(art, findsOneWidget);
    expect(find.descendant(of: art, matching: find.byType(ClipOval)),
        findsOneWidget);
    expect(tester.getTopLeft(art).dx,
        lessThan(tester.getTopLeft(find.text('Nova Hart')).dx));
    // TalkBack reads one heading, "Similar to, Nova Hart"; the picture
    // adds nothing to it.
    final heading = tester.getSemantics(find.text('Nova Hart'));
    expect(heading.hasFlag(SemanticsFlag.isHeader), isTrue);
    expect(heading.label, contains('Similar to'));
    expect(heading.label, contains('Nova Hart'));
    handle.dispose();
  });

  testWidgets('a song cover is square with rounded corners', (tester) async {
    await tester.pumpWidget(_app(ShelfHeaderArt.of(
        _shelf(art: 'https://example.com/paper-planes.jpg'))!));
    expect(find.byType(ClipOval), findsNothing);
    expect(find.byType(ClipRRect), findsOneWidget);
  });

  test('no picture, no header art', () {
    expect(ShelfHeaderArt.of(_shelf()), isNull);
    expect(ShelfHeaderArt.of(_shelf(art: '')), isNull);
  });

  testWidgets('the title opens the artist when it names one', (tester) async {
    final handle = tester.ensureSemantics();
    var opened = 0, seeAll = 0;
    await tester.pumpWidget(_app(RiffSectionHeader(
      'Nova Hart',
      kicker: 'Similar to',
      titleIsName: true,
      onTitleTap: () => opened++,
      onSeeAll: () => seeAll++,
    )));
    await tester.tap(find.text('Nova Hart'));
    expect((opened, seeAll), (1, 0));
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    expect((opened, seeAll), (1, 1));
    // TalkBack: the heading is a button of its own here.
    final heading = tester.getSemantics(find.text('Nova Hart'));
    expect(heading.hasFlag(SemanticsFlag.isHeader), isTrue);
    expect(heading.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(heading.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('otherwise the title opens See all, and TalkBack has one button',
      (tester) async {
    final handle = tester.ensureSemantics();
    var seeAll = 0;
    await tester.pumpWidget(_app(RiffSectionHeader(
      'New releases for you',
      onSeeAll: () => seeAll++,
    )));
    await tester.tap(find.text('New releases for you'));
    expect(seeAll, 1);
    final heading = tester.getSemantics(find.text('New releases for you'));
    expect(heading.hasFlag(SemanticsFlag.isHeader), isTrue);
    expect(heading.hasFlag(SemanticsFlag.isButton), isFalse);
    expect(heading.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    handle.dispose();
  });

  testWidgets('a header that opens nothing is plain text', (tester) async {
    await tester.pumpWidget(_app(const RiffSectionHeader('Listen again')));
    expect(find.byType(InkWell), findsNothing);
  });
}
