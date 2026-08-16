import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/player_media_ids.dart';

void main() {
  MediaItem song({Map<String, dynamic>? extras}) {
    return MediaItem(
      id: 'vid1',
      title: 'Song',
      artist: 'Artist',
      extras: extras,
    );
  }

  test('songAlbumId reads extras.album.id', () {
    expect(songAlbumId(song()), isNull);
    expect(
      songAlbumId(song(extras: {
        'album': {'name': 'LP', 'id': 'MPREb_abc'}
      })),
      'MPREb_abc',
    );
    expect(
      songAlbumId(song(extras: {
        'album': {'name': 'LP'}
      })),
      isNull,
    );
  });

  test('songArtistId prefers extras.artistId then artists list', () {
    expect(songArtistId(song()), isNull);
    expect(
      songArtistId(song(extras: {'artistId': 'UCabc'})),
      'UCabc',
    );
    expect(
      songArtistId(song(extras: {
        'artists': [
          {'name': 'A', 'id': null},
          {'name': 'B', 'id': 'UCdef'},
        ]
      })),
      'UCdef',
    );
    expect(
      songArtistId(song(extras: {
        'artistId': 'UCdirect',
        'artists': [
          {'name': 'B', 'id': 'UCother'},
        ]
      })),
      'UCdirect',
    );
  });
}
