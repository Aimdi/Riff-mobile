import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_cover_tile.dart';

/// Tapping a followed RSS show (Subscriptions grid, folders) must open its
/// page with the episodes; only the play button on the cover plays.
void main() {
  testWidgets('a tap opens the show, the play button plays', (tester) async {
    final opened = <String>[];
    final played = <String>[];
    const rss = {
      'title': 'Song Exploder',
      'author': 'Hrishikesh Hirway',
      'artwork': '',
      'feedUrl': 'https://feeds.example.com/songexploder',
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 180,
            child: rssPodcastTile(
              Map<String, dynamic>.from(rss),
              onLongPress: () {},
              open: (p) => opened.add('${p['feedUrl']}'),
              play: (p) async => played.add('${p['feedUrl']}'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Song Exploder'));
    await tester.pump();
    expect(opened, [rss['feedUrl']]);
    expect(played, isEmpty);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(played, [rss['feedUrl']]);
    expect(opened, hasLength(1));
  });
}
