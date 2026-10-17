import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_service.dart';

const _feed = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
  xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
  xmlns:podcast="https://podcastindex.org/namespace/1.0"
  xmlns:psc="http://podlove.org/simple-chapters">
<channel>
  <title>Show</title>
  <item>
    <title>Podlove</title>
    <enclosure url="https://example.com/1.mp3"/>
    <itunes:duration>3045.04</itunes:duration>
    <psc:chapters version="1.2">
      <psc:chapter start="00:00:00.000" title="Intro"/>
      <psc:chapter start="00:01:02.500" title="News &amp; views" href="https://example.com/news" image="https://example.com/news.jpg"/>
      <psc:chapter start="1:02:03" title="Outro"/>
      <psc:chapter start="soon" title="Not a time"/>
    </psc:chapters>
  </item>
  <item>
    <title>Both</title>
    <enclosure url="https://example.com/2.mp3"/>
    <podcast:chapters url="https://example.com/2.json" type="application/json+chapters"/>
    <psc:chapters><psc:chapter start="0" title="Intro"/></psc:chapters>
  </item>
  <item>
    <title>Other prefix</title>
    <enclosure url="https://example.com/3.mp3"/>
    <sc:chapters xmlns:sc="http://podlove.org/simple-chapters"><sc:chapter start="5" title="Start"/></sc:chapters>
  </item>
</channel>
</rss>''';

void main() {
  test('times as feeds write them', () {
    expect(parseFeedTime('1:02:03'), 3723);
    expect(parseFeedTime('02:03'), 123);
    expect(parseFeedTime(' 3045 '), 3045);
    expect(parseFeedTime('3045.04'), 3045.04);
    expect(parseFeedTime('00:01:02.500'), 62.5);
    for (final notATime in ['', 'soon', '1:2:3:4', '-5', '1.5:30', '1e3']) {
      expect(parseFeedTime(notATime), isNull, reason: notATime);
    }
    expect(parseFeedTime(null), isNull);
  });

  test('a fractional itunes:duration counts (it read as no length)', () {
    final eps = parsePodcastFeed(_feed, 'Show', '');
    expect(eps[0]['durationSec'], 3045);
  });

  test("Podlove chapters in the feed are the episode's chapters", () async {
    final eps = parsePodcastFeed(_feed, 'Show', '');
    final url = eps[0]['chaptersUrl'] as String;
    expect(url, startsWith('data:application/json'));
    final chapters = await PodcastService.chapters(url);
    expect(chapters.map((c) => c.startSec), [0, 62.5, 3723]);
    expect(chapters.map((c) => c.title), ['Intro', 'News & views', 'Outro']);
    expect(chapters[1].linkUrl, 'https://example.com/news');
    expect(chapters[1].imageUrl, 'https://example.com/news.jpg');

    // A Podcasting 2.0 file wins; any prefix for Podlove's namespace counts.
    expect(eps[1]['chaptersUrl'], 'https://example.com/2.json');
    final other = await PodcastService.chapters(eps[2]['chaptersUrl']);
    expect(other.single.title, 'Start');
  });
}
