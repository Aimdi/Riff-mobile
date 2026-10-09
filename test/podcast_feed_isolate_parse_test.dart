import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_service.dart';

const _feed = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
  xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
  xmlns:podcast="https://podcastindex.org/namespace/1.0">
<channel>
  <title>Show</title>
  <itunes:image href="https://example.com/show.jpg"/>
  <item>
    <title>Ep 3</title>
    <guid>guid-3</guid>
    <pubDate>Mon, 21 Jul 2026 06:00:00 EDT</pubDate>
    <description><![CDATA[<p>Hello &amp;#8217; <b>world</b></p>]]></description>
    <enclosure url="https://example.com/3.mp3" length="1048576" type="audio/mpeg"/>
    <itunes:duration>1:02:03</itunes:duration>
    <podcast:chapters url="https://example.com/3.json" type="application/json+chapters"/>
    <podcast:transcript url="https://example.com/3.html" type="text/html"/>
    <podcast:transcript url="https://example.com/3.srt" type="application/srt"/>
  </item>
  <item>
    <title>No audio</title>
    <guid>guid-x</guid>
  </item>
  <item>
    <title>Ep 2</title>
    <pubDate>20 Jul 2026 10:00 +0000</pubDate>
    <enclosure url="https://example.com/2.mp3"/>
    <itunes:duration>42:10</itunes:duration>
  </item>
  <item>
    <title>Ep 1</title>
    <guid>guid-1</guid>
    <pubDate>Sun, 19 Jul 2026 08:00:00 GMT</pubDate>
    <enclosure url="https://example.com/1.mp3"/>
  </item>
</channel>
</rss>''';

void main() {
  test('parses items into primitive maps', () {
    final eps = parsePodcastFeed(_feed, 'Show', 'https://example.com/fb.jpg');
    expect(eps.map((e) => e['title']), ['Ep 3', 'Ep 2', 'Ep 1']);
    final e3 = eps.first;
    // Episode ids must stay stable: saved progress is keyed on them.
    expect(e3['id'], 'podcast_${'guid-3'.hashCode}');
    // No guid → falls back to the enclosure URL.
    expect(eps[1]['id'], 'podcast_${'https://example.com/2.mp3'.hashCode}');
    expect(e3['url'], 'https://example.com/3.mp3');
    expect(e3['sizeBytes'], 1048576);
    expect(e3['durationSec'], 3723);
    expect(e3['podcast'], 'Show');
    expect(e3['date'], '21 Jul 2026');
    expect(e3['pubDateMs'],
        DateTime.utc(2026, 7, 21, 10).millisecondsSinceEpoch);
    expect(e3['chaptersUrl'], 'https://example.com/3.json');
    expect(e3['transcriptUrl'], 'https://example.com/3.srt');
    expect(e3['transcriptType'], 'application/srt');
    expect(e3['description'], contains('world'));
    expect(e3['description'], isNot(contains('<')));
    expect(eps[1]['pubDateMs'],
        DateTime.utc(2026, 7, 20, 10).millisecondsSinceEpoch);
  });

  test('maxItems limits the built episodes', () {
    final eps = parsePodcastFeed(_feed, 'Show', '', maxItems: 2);
    expect(eps.map((e) => e['title']), ['Ep 3', 'Ep 2']);
    expect(parsePodcastFeed(_feed, 'Show', '').length, 3);
  });

  test('runs on a background isolate with identical output', () async {
    final local = parsePodcastFeed(_feed, 'Show', 'fb');
    final remote =
        await Isolate.run(() => parsePodcastFeed(_feed, 'Show', 'fb'));
    expect(remote, local);
  });

  test('one item with an impossible date does not drop the feed', () {
    // Used to throw a RangeError from the date label, so the show listed
    // no episodes at all.
    const feed = '''<rss><channel><title>S</title>
<item><title>Bad date</title><guid>b</guid><pubDate>2026-13-01</pubDate>
<enclosure url="https://example.com/b.mp3"/></item>
<item><title>Good</title><guid>g</guid><pubDate>2026-07-19T08:00:00Z</pubDate>
<enclosure url="https://example.com/g.mp3"/></item>
</channel></rss>''';
    final eps = parsePodcastFeed(feed, 'S', '');
    expect(eps.map((e) => e['title']), ['Bad date', 'Good']);
    expect(eps[0]['date'], '2026-13-01');
    expect(eps[0]['pubDateMs'], 0);
    expect(eps[1]['date'], '19 Jul 2026');
  });

  test('malformed XML throws', () {
    expect(() => parsePodcastFeed('<rss><channel>', 'S', ''),
        throwsA(anything));
  });
}
