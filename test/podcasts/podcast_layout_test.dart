import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_cover_tile.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_layout.dart';

void main() {
  test('compactEpisodeLength', () {
    expect(compactEpisodeLength(0), '');
    expect(compactEpisodeLength(-5), '');
    expect(compactEpisodeLength(20), '1m');
    expect(compactEpisodeLength(30 * 60), '30m');
    expect(compactEpisodeLength(60 * 60), '1h');
    expect(compactEpisodeLength(95 * 60 + 12), '1h 36m');
  });

  test('episodeMetaLine drops empty parts', () {
    expect(episodeMetaLine(['Show', '', null, ' 29 Sep ', '30m']),
        'Show · 29 Sep · 30m');
    expect(episodeMetaLine([null, '']), '');
  });

  group('episodeDateLabel', () {
    final now = DateTime(2026, 10, 22, 9);

    test('today, yesterday, then the date; no year for this one', () {
      expect(episodeDateLabel('22 Oct 2026', now), 'today');
      expect(episodeDateLabel('21 Oct 2026', now), 'yesterday');
      expect(episodeDateLabel('3 Jan 2026', now), '3 Jan');
      expect(episodeDateLabel('30 Dec 2025', now), '30 Dec 2025');
    });

    test('yesterday across a month and a year', () {
      expect(
          episodeDateLabel('30 Sep 2026', DateTime(2026, 10, 1)), 'yesterday');
      expect(
          episodeDateLabel('31 Dec 2025', DateTime(2026, 1, 1)), 'yesterday');
    });

    test('dates in other forms stay as they are', () {
      expect(episodeDateLabel('3 days ago', now), '3 days ago');
      expect(episodeDateLabel(null, now), '');
      expect(episodeDateLabel('', now), '');
    });
  });

  testWidgets(
      'an episode row cuts a long show name short, not its date and '
      'length', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        // Wide enough for the test font's square glyphs.
        body: SizedBox(
          width: 600,
          child: PodcastEpisodeTile(
            artUrl: '',
            title: 'Walking the Camino',
            show: 'The Long Way Round: Slow Travel Stories From Everywhere',
            meta: '22 Oct · 18m',
          ),
        ),
      ),
    ));
    final show = tester.renderObject<RenderParagraph>(
        find.text('The Long Way Round: Slow Travel Stories From Everywhere'));
    final tail =
        tester.renderObject<RenderParagraph>(find.text(' · 22 Oct · 18m'));
    expect(show.didExceedMaxLines, isTrue);
    expect(tail.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no show the meta line is one text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PodcastEpisodeTile(
            artUrl: '', title: 'Episode', meta: 'Show · 30m'),
      ),
    ));
    expect(find.text('Show · 30m'), findsOneWidget);
  });

  test('subscriptions grid: 3 columns on phones, 2 when narrow', () {
    // Pane widths: the screen less the 47 dp rail.
    expect(podcastSubsColumnCount(360 - 47), 2);
    expect(podcastSubsColumnCount(411 - 47), 3);
    expect(podcastSubsColumnCount(800), 4);
    expect(podcastSubsColumnCount(1200), 6);
  });
}
