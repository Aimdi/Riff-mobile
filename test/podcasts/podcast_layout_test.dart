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

  test('subscriptions grid: 3 columns on phones, 2 when narrow', () {
    expect(podcastSubsColumnCount(360), 2);
    expect(podcastSubsColumnCount(411), 3);
    expect(podcastSubsColumnCount(800), 4);
    expect(podcastSubsColumnCount(1200), 6);
  });
}
