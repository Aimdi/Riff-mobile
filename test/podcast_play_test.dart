import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/podcast_play.dart';

void main() {
  test('podcast show tiles play on tap', () {
    expect(shouldPlayPodcastShowOnTap(), isTrue);
  });

  test('podcast show starts at the in-progress episode', () {
    expect(
      podcastShowStartIndex(
        episodeIds: ['ep1', 'ep2', 'ep3'],
        inProgressId: 'ep2',
      ),
      1,
    );
    expect(
      podcastShowStartIndex(
        episodeIds: ['ep1', 'ep2'],
        inProgressId: null,
      ),
      0,
    );
    expect(
      podcastShowStartIndex(
        episodeIds: ['ep1'],
        inProgressId: 'missing',
      ),
      0,
    );
  });

  test('podcastEpisodeToMediaItem marks the item as a podcast', () {
    final item = podcastEpisodeToMediaItem(
      {
        'id': 'ep1',
        'title': 'Pilot',
        'url': 'https://example.com/a.mp3',
        'durationSec': 90,
      },
      {'title': 'Show', 'feedUrl': 'https://example.com/feed'},
    );
    expect(item.id, 'ep1');
    expect(item.title, 'Pilot');
    expect(item.artist, 'Show');
    expect(item.duration, const Duration(seconds: 90));
    expect(item.extras?['isPodcast'], isTrue);
    expect(item.extras?['feedUrl'], 'https://example.com/feed');
  });

  test('playFirstPodcastInGenre no-ops on an empty genre', () async {
    expect(await playFirstPodcastInGenre(''), isFalse);
    expect(await playFirstPodcastInGenre('   '), isFalse);
  });

  test('isPodcastCollection matches show and YouTube channel tiles', () {
    expect(isPodcastCollection(kind: 'podcast'), isTrue);
    expect(isPodcastCollection(kind: 'yt_channel'), isTrue);
    expect(isPodcastCollection(id: 'MPSP123'), isTrue);
    expect(isPodcastCollection(id: 'UCabcdefghijklmnopqrstuv'), isTrue);
    expect(isPodcastCollection(kind: 'album', id: 'MPREb_abc'), isFalse);
    expect(isPodcastCollection(id: 'VLPL123'), isFalse);
  });
}
