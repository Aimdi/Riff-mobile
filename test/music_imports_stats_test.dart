import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/csv_playlist_import.dart';
import 'package:harmonymusic/services/m3u_playlist_import.dart';
import 'package:harmonymusic/services/spotify_match_store.dart';
import 'package:harmonymusic/services/stats_service.dart';

void main() {
  // Exportify's Track URI was kept as the id and sent to Spotify as
  // spotify:track:spotify:track:…, which failed every later like sync.
  test('a Spotify track id from a URI or a link, bare', () {
    const id = '4uLU6hMCjMI75M1A2tKUQC';
    expect(spotifyTrackIdOf(id), id);
    expect(spotifyTrackIdOf('spotify:track:$id'), id);
    expect(spotifyTrackIdOf('https://open.spotify.com/track/$id?si=abc'), id);
    expect(spotifyTrackIdOf('spotify:episode:$id'), isNull);
    expect(spotifyTrackIdOf('csv_3'), isNull);
  });

  test("an Exportify CSV's tracks get bare Spotify ids", () {
    const csv = 'Track URI,Track Name,Artist Name(s),Duration (ms)\n'
        'spotify:track:4uLU6hMCjMI75M1A2tKUQC,Song,Artist,200000\n'
        ',No uri,Artist,100000\n';
    final ids = parsePlaylistCsv(csv).tracks.map((t) => t.id).toList();
    expect(ids.first, '4uLU6hMCjMI75M1A2tKUQC');
    expect(ids.last, startsWith('csv_'));
  });

  test('top songs are songs: no podcast episodes or audiobook chapters', () {
    final top = rankTopSongs({
      'song0000001': {'title': 'Song', 'artist': 'A', 'plays': 5},
      'podcast_123': {'title': 'Episode', 'artist': 'Show', 'plays': 50},
      'lv_book_1': {'title': 'Chapter 2', 'artist': 'Author', 'plays': 40},
      'abc0000001x': {
        'title': 'Tagged',
        'artist': 'Show',
        'plays': 30,
        'kind': 'audiobook'
      },
    });
    expect(top.map((s) => s['id']), ['song0000001']);
  });

  test("a playlist file keeps a phone song's address, not a YouTube link",
      () {
    final m3u = playlistM3u('Mine', [
      const MediaItem(
          id: 'device_1234',
          title: 'Phone song',
          extras: {'url': 'content://media/external/audio/media/1234'}),
      const MediaItem(id: 'dQw4w9WgXcQ', title: 'YouTube song'),
    ]);
    expect(m3u, contains('content://media/external/audio/media/1234'));
    expect(m3u, isNot(contains('watch?v=device_1234')));
    expect(m3u, contains('https://music.youtube.com/watch?v=dQw4w9WgXcQ'));
  });
}
