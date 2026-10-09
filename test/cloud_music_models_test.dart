import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/cloud_music_service.dart';

void main() {
  test('Subsonic numbers sent as strings are read, not thrown on', () {
    final song = CloudSong.fromJson({
      'id': 's1',
      'title': 'Song',
      'duration': '215',
      'track': '3',
    })!;
    expect(song.duration, const Duration(seconds: 215));
    expect(song.track, 3);

    final album =
        CloudAlbum.fromJson({'id': 'a1', 'songCount': '12', 'year': '1999'})!;
    expect(album.songCount, 12);
    expect(album.year, 1999);

    final playlist = CloudPlaylist.fromJson(
        {'id': 'p1', 'songCount': 4, 'duration': 'n/a'})!;
    expect(playlist.songCount, 4);
    expect(playlist.duration, isNull);
  });

  test('numeric fields still work as numbers', () {
    final song = CloudSong.fromJson({'id': 7, 'duration': 61.0, 'track': 1})!;
    expect(song.id, '7');
    expect(song.duration, const Duration(seconds: 61));
    expect(song.track, 1);
    expect(CloudSong.fromJson({'title': 'no id'}), isNull);
  });
}
