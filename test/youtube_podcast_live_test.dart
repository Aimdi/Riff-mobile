// Live checks for the YouTube Podcasts data layer against the real InnerTube
// WEB API. Uses youtubei.googleapis.com, which accepts the same requests as
// www.youtube.com and is reachable from environments that block the latter.
//
// Tagged `live`: excluded from the per-push suite, run by path when needed.

@Tags(<String>['live'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:harmonymusic/services/youtube_podcast_service.dart';

void main() {
  const timeout = Timeout(Duration(seconds: 60));

  setUpAll(() {
    YoutubePodcastService.baseUrl = 'https://youtubei.googleapis.com';
  });

  late List<YtPodcastShow> popular;

  test('popularShows', () async {
    popular = await YoutubePodcastService.popularShows();
    expect(popular, isNotEmpty);
    expect(popular.first.playlistId, startsWith('PL'));
    expect(popular.first.thumbnailUrl, isNotEmpty);
  }, timeout: timeout);

  test('popularEpisodes', () async {
    final eps = await YoutubePodcastService.popularEpisodes();
    expect(eps, isNotEmpty);
    expect(eps.first.duration!.inSeconds, greaterThan(0));
    expect(eps.first.extras!['podcastSource'], 'yt_podcast');
  }, timeout: timeout);

  test('searchShows', () async {
    final shows = await YoutubePodcastService.searchShows('history podcast');
    expect(shows, isNotEmpty);
  }, timeout: timeout);

  test('channelShows', () async {
    final channelId = popular
        .map((s) => s.authorId)
        .firstWhere((id) => id != null, orElse: () => null);
    expect(channelId, isNotNull);
    final shows = await YoutubePodcastService.channelShows(channelId!);
    expect(shows, isNotEmpty);
  }, timeout: timeout);

  test('showEpisodes with continuation', () async {
    final show = popular.first;
    final page = await YoutubePodcastService.showEpisodes(show.playlistId);
    expect(page.episodes, isNotEmpty);
    expect(page.episodes.first.extras!['podcastPlaylistId'], show.playlistId);
    if (page.continuation != null) {
      final next = await YoutubePodcastService.showEpisodes(show.playlistId,
          continuation: page.continuation);
      expect(next.episodes, isNotEmpty);
      expect(next.episodes.first.id, isNot(page.episodes.first.id));
    }
  }, timeout: timeout);
}
