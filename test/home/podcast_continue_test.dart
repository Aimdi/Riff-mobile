import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Home/podcast_continue.dart';

void main() {
  test('latestPodcastContinue returns the first (newest) row', () {
    expect(latestPodcastContinue(const []), isNull);
    expect(
      latestPodcastContinue([
        {'id': 'ep1', 'title': 'One'},
        {'id': 'ep2', 'title': 'Two'},
      ])?['id'],
      'ep1',
    );
  });

  test('podcastContinueQueue skips blank ids', () {
    final queue = podcastContinueQueue([
      {'id': 'ep1', 'title': 'One'},
      {'id': '', 'title': 'Nope'},
      {'id': 'ep2', 'title': 'Two'},
    ]);
    expect(queue.map((e) => e.id), ['ep1', 'ep2']);
    expect(queue.first.extras?['isPodcast'], isTrue);
  });

  test('podcast continue chip hides when that episode is current', () {
    expect(
      shouldShowPodcastContinueChip(
        hasEpisode: false,
        currentSongId: null,
        continueEpisodeId: 'ep1',
      ),
      isFalse,
    );
    expect(
      shouldShowPodcastContinueChip(
        hasEpisode: true,
        currentSongId: null,
        continueEpisodeId: 'ep1',
      ),
      isTrue,
    );
    expect(
      shouldShowPodcastContinueChip(
        hasEpisode: true,
        currentSongId: 'ep1',
        continueEpisodeId: 'ep1',
      ),
      isFalse,
    );
    expect(
      shouldShowPodcastContinueChip(
        hasEpisode: true,
        currentSongId: 'song',
        continueEpisodeId: 'ep1',
      ),
      isTrue,
    );
    expect(
      shouldShowPodcastContinueChip(
        hasEpisode: true,
        currentSongId: null,
        continueEpisodeId: '  ',
      ),
      isFalse,
    );
  });
}
