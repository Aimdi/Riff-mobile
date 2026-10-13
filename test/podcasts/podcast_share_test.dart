import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_share.dart';

MediaItem _rss([Map<String, dynamic> extras = const {}]) => MediaItem(
      id: 'podcast_123',
      title: 'The Episode',
      artist: 'The Show',
      extras: {'isPodcast': true, ...extras},
    );

const _at = Duration(minutes: 12, seconds: 34);

void main() {
  test('a YouTube episode: its video, from the moment', () {
    const yt = MediaItem(
        id: 'dQw4w9WgXcQ',
        title: 'Ep',
        artist: 'Show',
        extras: {'isPodcast': true});
    expect(podcastEpisodeShareLink(yt), 'https://youtu.be/dQw4w9WgXcQ');
    expect(podcastEpisodeShareLink(yt, at: _at),
        'https://youtu.be/dQw4w9WgXcQ?t=754');
  });

  test(
      'an RSS episode: its page, else its audio (from the moment), '
      'else the feed', () {
    expect(
        podcastEpisodeShareLink(
            _rss({
              'link': 'https://show.example/ep1',
              'url': 'https://cdn.example/ep1.mp3',
            }),
            at: _at),
        'https://show.example/ep1');
    expect(
        podcastEpisodeShareLink(_rss({'url': 'https://cdn.example/ep1.mp3'}),
            at: _at),
        'https://cdn.example/ep1.mp3#t=754');
    // A downloaded copy's file isn't shared, its web address is.
    expect(
        podcastEpisodeShareLink(_rss({
          'url': 'file:///data/ep1.mp3',
          'remoteUrl': 'https://cdn.example/ep1.mp3',
        })),
        'https://cdn.example/ep1.mp3');
    expect(
        podcastEpisodeShareLink(
            _rss({'feedUrl': 'https://feeds.example/show.xml'})),
        'https://feeds.example/show.xml');
    expect(podcastEpisodeShareLink(_rss({'link': 'not a link'})), isNull);
  });

  test('the text: show, episode, the moment, the link', () {
    final item = _rss({'url': 'https://cdn.example/ep1.mp3'});
    expect(podcastEpisodeShareText(item),
        'The Show, The Episode\nhttps://cdn.example/ep1.mp3');
    expect(podcastEpisodeShareText(item, at: _at),
        'The Show, The Episode @ 12:34\nhttps://cdn.example/ep1.mp3#t=754');
    expect(podcastEpisodeShareText(_rss()), 'The Show, The Episode');
  });
}
