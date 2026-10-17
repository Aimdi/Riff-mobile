import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/content_filters.dart';

void main() {
  test('a song goes with its song.link; one nobody else can reach, by name',
      () {
    expect(
        SongLinkShare.shareText(const MediaItem(
            id: 'dQw4w9WgXcQ',
            title: 'Never Gonna Give You Up',
            artist: 'Rick Astley')),
        'Never Gonna Give You Up — Rick Astley\n'
        'https://song.link/https://youtube.com/watch?v=dQw4w9WgXcQ');
    // On the phone, from your own server: their addresses aren't shared.
    expect(
        SongLinkShare.shareText(const MediaItem(
            id: 'device_42',
            title: 'Voice memo',
            extras: {'url': 'content://media/external/audio/media/42'})),
        'Voice memo');
    expect(
        SongLinkShare.shareText(const MediaItem(
            id: 'cloud_7',
            title: 'Home song',
            artist: 'Me',
            extras: {
              'url': 'https://music.example.com/rest/stream.view?id=7&u=me'
                  '&t=secret&s=salt'
            })),
        'Home song — Me');
    // A podcast episode, as episodes are shared.
    expect(
        SongLinkShare.shareText(const MediaItem(
            id: 'podcast_abc',
            title: 'Episode 1',
            artist: 'The Show',
            extras: {'link': 'https://show.example.com/1'})),
        'The Show, Episode 1\nhttps://show.example.com/1');
  });

  test("one of your playlists: its name and YouTube's link to 50 of its songs",
      () {
    final songs = [
      const MediaItem(id: 'device_1', title: 'Memo'),
      for (var i = 0; i < 60; i++)
        MediaItem(id: 'song${'$i'.padLeft(7, '0')}', title: 'Song $i'),
    ];
    final text = SongLinkShare.playlistText('Road trip', songs);
    final lines = text.split('\n');
    expect(lines.first, 'Road trip');
    final link = Uri.parse(lines.last);
    expect(link.toString(),
        startsWith('https://www.youtube.com/watch_videos?video_ids='));
    final ids = link.queryParameters['video_ids']!.split(',');
    expect(ids, hasLength(50));
    expect(ids.first, 'song0000000');
    expect(ids.last, 'song0000049');
    // None from YouTube: just its name.
    expect(SongLinkShare.playlistText('Memos', songs.take(1)), 'Memos');
  });
}
