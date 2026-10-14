import 'dart:ui' show Locale;

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_layout.dart';
import 'package:harmonymusic/utils/get_localization.dart';

const _feed = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
  <title>Serial</title>
  <item>
    <title>Coming soon</title>
    <enclosure url="https://example.com/t.mp3"/>
    <itunes:episodeType>Trailer</itunes:episodeType>
    <itunes:season>2</itunes:season>
  </item>
  <item>
    <title>Part five</title>
    <enclosure url="https://example.com/5.mp3"/>
    <itunes:episodeType>full</itunes:episodeType>
    <itunes:season>2</itunes:season>
    <itunes:episode>5</itunes:episode>
  </item>
  <item>
    <title>Odd values</title>
    <enclosure url="https://example.com/x.mp3"/>
    <itunes:season>soon</itunes:season>
    <itunes:episode>0</itunes:episode>
  </item>
</channel>
</rss>''';

MediaItem _episode(Map<String, Object> extras) =>
    MediaItem(id: 'podcast_x', title: 'X', extras: extras);

void main() {
  setUp(() {
    Get.addTranslations(Languages().keys);
    Get.locale = const Locale('en');
  });

  test("the feed's seasons, numbers, trailers and bonus episodes", () {
    final eps = parsePodcastFeed(_feed, 'Serial', '');
    expect(episodeNumbering(eps[0]), {'season': 2, 'episodeType': 'trailer'});
    expect(episodeNumbering(eps[1]), {'season': 2, 'episode': 5});
    // Not numbers (or no number): nothing.
    expect(episodeNumbering(eps[2]), isEmpty);
  });

  test('labelled as Apple Podcasts and Pocket Casts label them', () {
    expect(
        episodeNumberLabel(_episode({'episodeType': 'trailer', 'season': 2})),
        'Trailer');
    expect(episodeNumberLabel(_episode({'episodeType': 'bonus'})), 'Bonus');
    expect(episodeNumberLabel(_episode({'season': 2, 'episode': 5})), 'S2 E5');
    expect(episodeNumberLabel(_episode({'episode': 12})), 'Ep. 12');
    expect(episodeNumberLabel(_episode({'season': 3})), 'Season 3');
    expect(episodeNumberLabel(_episode({})), '');
    expect(episodeMetaLine([episodeNumberLabel(_episode({})), '1 Jul 2026']),
        '1 Jul 2026');
  });
}
