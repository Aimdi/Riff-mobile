import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/artist.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_builder.dart';
import 'package:harmonymusic/ui/screens/Home/home_metrics.dart';
import 'package:harmonymusic/ui/screens/Home/home_shelf_screen.dart';
import 'package:harmonymusic/ui/screens/Home/home_shelves.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

HomeShelfData _shelf(List<Object> values,
        {HomeShelfKind kind = HomeShelfKind.collections,
        String title = 'Shelf'}) =>
    HomeShelfData(
      id: title,
      title: title,
      kind: kind,
      items: [for (final (i, v) in values.indexed) HomeItem('k$i', v)],
    );

GeneratedMix _mix(int i) => GeneratedMix(
    id: 'mix$i',
    title: 'Mix $i',
    reason: 'For you',
    kind: 'daily',
    tracks: const [],
    generatedTs: 0);

Artist _artist(int i) => Artist(
    name: 'Artist $i',
    browseId: 'UC$i',
    thumbnailUrl: '',
    subscribers: '1K subscribers');

void main() {
  // A phone's pane: 411 dp less the 47 dp rail.
  const phone = HomeMetrics(364);

  group('See all shows when the row runs on past a pane and a half', () {
    test('covers', () {
      expect(ShelfCardSize.hasMore(_shelf([_mix(0), _mix(1)]), phone), isFalse);
      expect(
          ShelfCardSize.hasMore(
              _shelf([for (var i = 0; i < 3; i++) _mix(i)]), phone),
          isFalse);
      expect(
          ShelfCardSize.hasMore(
              _shelf([for (var i = 0; i < 4; i++) _mix(i)]), phone),
          isTrue);
    });

    test('artists are narrower, so it takes more of them', () {
      HomeShelfData artists(int n) =>
          _shelf([for (var i = 0; i < n; i++) _artist(i)],
              kind: HomeShelfKind.artists);
      expect(ShelfCardSize.hasMore(artists(4), phone), isFalse);
      expect(ShelfCardSize.hasMore(artists(5), phone), isTrue);
    });

    test('a tablet shows more before it needs it', () {
      final six = _shelf([for (var i = 0; i < 6; i++) _mix(i)]);
      expect(ShelfCardSize.hasMore(six, phone), isTrue);
      expect(ShelfCardSize.hasMore(six, const HomeMetrics(1200)), isFalse);
    });
  });

  group('grid', () {
    test('two columns on a phone, more on a tablet', () {
      final shelf = _shelf([_mix(0)]);
      final p = HomeShelfScreen.grid(shelf, phone.inner);
      expect(p.columns, 2);
      expect(p.card * 2 + RiffSpacing.cardGap, closeTo(phone.inner, 0.01));
      expect(HomeShelfScreen.grid(shelf, 800).columns, 4);
      // Never one lonely column of covers, even on a very small pane.
      expect(HomeShelfScreen.grid(shelf, 200).columns, 2);
    });

    test('videos one per row on a phone', () {
      final videos = _shelf([_mix(0)], kind: HomeShelfKind.videos);
      expect(HomeShelfScreen.grid(videos, phone.inner).columns, 1);
      expect(HomeShelfScreen.grid(videos, 800).columns, 2);
    });
  });

  testWidgets('the page lists every card of the shelf under its title',
      (tester) async {
    tester.view
      ..physicalSize = const Size(364, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shelf = HomeShelfData(
      id: 'riff:mixes',
      title: 'Your Daily Mixes',
      kicker: 'Made for you',
      items: [for (var i = 0; i < 5; i++) HomeItem('k$i', _mix(i))],
    );
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: HomeShelfScreen(shelf: shelf),
    ));
    expect(find.text('Your daily mixes'), findsOneWidget);
    expect(find.text('Made for you'), findsOneWidget);
    expect(find.byType(HomeShelfItem), findsNWidgets(5));
    // Two columns: the second card sits beside the first, the third under.
    Offset at(int i) => tester.getTopLeft(find.byType(HomeShelfItem).at(i));
    expect(at(1).dy, at(0).dy);
    expect(at(1).dx, greaterThan(at(0).dx));
    expect(at(2).dx, at(0).dx);
    expect(at(2).dy, greaterThan(at(0).dy));
  });
}
