import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_segments.dart';
import 'package:harmonymusic/services/podcast_service.dart';

String _feed(List<(String guid, String url, String date)> items) => '''
<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
<title>Show</title>
${items.map((i) => '''
<item><title>${i.$2}</title><guid>${i.$1}</guid>
<enclosure url="https://a.example/${i.$2}.mp3" type="audio/mpeg"/>
<pubDate>${i.$3}</pubDate></item>''').join()}
</channel></rss>''';

void main() {
  // Parts of words skipped real content, by default.
  test('ad chapters by whole words', () {
    for (final ad in [
      'Sponsor',
      'Sponsored by Acme',
      'Ad break',
      'Ads',
      'Werbung',
      'Advertisement',
    ]) {
      expect(chapterTitleIsAd(ad), isTrue, reason: ad);
    }
    for (final not in [
      'Getting a promotion',
      'Bewerbung und Vorstellungsgespräch',
      'Advertising in the 50s',
      'Shirt sponsorship deals',
      'At the pub',
    ]) {
      expect(chapterTitleIsAd(not), isFalse, reason: not);
    }
  });

  test('a self-promo chapter is self-promo, not a sponsor read', () {
    final segs = segmentsFromChapters([
      PodcastChapter(title: 'Self-promo', startSec: 0, endSec: 30),
      PodcastChapter(title: 'Sponsor', startSec: 30, endSec: 60),
    ], 120);
    expect(segs.map((s) => s.category),
        [SegmentCategory.selfpromo, SegmentCategory.sponsor]);
  });

  test('a feed listed oldest first comes in newest first', () {
    final feed = parsePodcastShow(
        _feed([
          ('g1', 'one', 'Mon, 01 Jan 2024 10:00:00 GMT'),
          ('g2', 'two', 'Mon, 01 Apr 2024 10:00:00 GMT'),
          ('g3', 'three', 'Mon, 01 Jul 2024 10:00:00 GMT'),
        ]),
        'Show',
        '',
        maxItems: 2);
    expect(feed.episodes.map((e) => e['title']), ['three', 'two']);
  });

  test('items sharing one guid are episodes of their own', () {
    final feed = parsePodcastShow(
        _feed([
          ('same', 'b', 'Mon, 01 Jul 2024 10:00:00 GMT'),
          ('same', 'a', 'Mon, 01 Jan 2024 10:00:00 GMT'),
        ]),
        'Show',
        '');
    final ids = feed.episodes.map((e) => e['id']).toSet();
    expect(ids, hasLength(2));
  });
}
