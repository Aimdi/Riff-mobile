import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/youtube_podcast_service.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcasts_library_controller.dart';

void main() {
  test('YouTube show maps to a YouTube Music podcast id', () {
    final pl = ytShowAsPodcast(const YtPodcastShow(
      playlistId: 'PLq9fVK72pJBIzzgr5KQkVJOo4FZrDbCxA',
      title: 'Nightcap',
      author: 'Nightcap',
      thumbnailUrl: 'https://i.ytimg.com/pl_c/x/studio_square_thumbnail.jpg',
      episodeCountText: '831 episodes',
    ));
    expect(pl.playlistId, 'MPSPPLq9fVK72pJBIzzgr5KQkVJOo4FZrDbCxA');
    expect(pl.kind, 'podcast');
    expect(pl.description, 'Nightcap • 831 episodes');
    expect(pl.thumbnailUrl, contains('studio_square'));
  });

  test('already-prefixed ids and missing art', () {
    final pl = ytShowAsPodcast(const YtPodcastShow(
      playlistId: 'MPSPPLabc',
      title: 'Show',
      author: '',
      thumbnailUrl: '',
    ));
    expect(pl.playlistId, 'MPSPPLabc');
    expect(pl.description, 'Podcast');
    expect(pl.thumbnailUrl, isNotEmpty);
  });
}
