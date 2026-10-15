import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/models/media_item_extras.dart';
import 'package:harmonymusic/services/device_music.dart';
import 'package:harmonymusic/services/song_fade.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart';
import 'package:harmonymusic/utils/helper.dart';

/// A track of a YouTube Music album page ([n] of [total]).
MediaItem _track(String id, int n,
        {int total = 10,
        String album = 'Live',
        String albumId = 'MPREb_live'}) =>
    MediaItem(
      id: id,
      title: 'Track $n',
      artist: 'Band',
      album: album,
      extras: {
        'album': {'name': album, 'id': albumId},
        'trackDetails': '$n/$total',
      },
    );

/// A music file on the phone, as DeviceMusic.kt lists it.
MediaItem _onPhone(String id, int track, {String albumId = '7'}) => deviceSong({
      'id': id,
      'uri': 'content://media/external/audio/media/$id',
      'title': 'Song $id',
      'artist': 'Artist',
      'album': 'Album',
      'albumId': albumId,
      'track': track,
      'durationMs': 215000,
    })!;

List<String> _ids(List songs) => [for (final s in songs) (s as MediaItem).id];

/// An album played in order runs on without the fade between songs, as
/// Apple Music doesn't crossfade a gapless album; sorted by album, an
/// album's tracks come in their order.
void main() {
  group('a song\'s album and number', () {
    test('YouTube Music\'s album page: its id, and n of "n/total"', () {
      final song = _track('a', 3);
      expect(song.albumKey, 'id:MPREb_live');
      expect(song.albumTrackNumber, 3);
    });

    test('the phone\'s: its album, and the disc in thousands', () {
      final song = _onPhone('1', 2003);
      expect(song.albumKey, 'device:7');
      expect(song.albumTrackNumber, 2003);
      // Untagged: no number.
      expect(_onPhone('2', 0).albumTrackNumber, isNull);
    });

    test('your music server\'s: its album id and a bare track number', () {
      // As CloudMusicService.toMediaItem keeps a Subsonic song.
      const song = MediaItem(id: 'cloud_s1', title: 'Song', extras: {
        'album': {'name': 'Album', 'id': 'al-1'},
        'trackDetails': '4',
      });
      expect(song.albumKey, 'id:al-1');
      expect(song.albumTrackNumber, 4);
    });

    test('a name only, or nothing', () {
      expect(
          const MediaItem(id: 'x', title: 'x', album: ' Kind of Blue ')
              .albumKey,
          'name:kind of blue');
      expect(const MediaItem(id: 'y', title: 'y').albumKey, isNull);
      expect(const MediaItem(id: 'y', title: 'y').albumTrackNumber, isNull);
    });
  });

  group('the album\'s next track', () {
    test('follows on, unfaded', () {
      expect(continuesAlbum(_track('a', 3), _track('b', 4)), isTrue);
      expect(continuesAlbum(_onPhone('1', 1003), _onPhone('2', 1004)), isTrue);
    });

    test('anything else fades as before', () {
      // Skipping a track, going back, or on from the last.
      expect(continuesAlbum(_track('a', 3), _track('b', 5)), isFalse);
      expect(continuesAlbum(_track('a', 4), _track('b', 3)), isFalse);
      expect(continuesAlbum(_track('a', 10), _track('b', 1)), isFalse);
      // Another album, even of the same name.
      expect(
          continuesAlbum(
              _track('a', 3), _track('b', 4, albumId: 'MPREb_other')),
          isFalse);
      // The phone's next disc, or another album.
      expect(continuesAlbum(_onPhone('1', 1012), _onPhone('2', 2001)), isFalse);
      expect(continuesAlbum(_onPhone('1', 3), _onPhone('2', 4, albumId: '8')),
          isFalse);
      // Without numbers there's no telling.
      const plain = MediaItem(id: 'p', title: 'p', album: 'Live');
      expect(continuesAlbum(plain, plain), isFalse);
    });
  });

  test('sorted by album: each album\'s tracks in their order', () {
    final songs = [
      _track('L3', 3),
      _track('M2', 2, albumId: 'MPREb_more'),
      const MediaItem(id: 'loose', title: 'Aria', album: 'Live'),
      _track('L1', 1),
      _track('M1', 1, albumId: 'MPREb_more'),
      _track('L2', 2),
      _onPhone('D2', 1002),
      _onPhone('D1', 1001),
    ];
    sortSongsNVideos(songs, SortType.Album, true);
    expect(_ids(songs),
        ['device_D1', 'device_D2', 'L1', 'L2', 'L3', 'M1', 'M2', 'loose']);
  });

  test('the phone\'s songs keep their album through playlists and restarts',
      () {
    MediaItem kept(MediaItem song) =>
        MediaItemBuilder.fromJson(MediaItemBuilder.toJson(song));
    final song = kept(_onPhone('1', 1003));
    expect(song.album, 'Album');
    expect(song.albumKey, 'device:7');
    expect(song.albumTrackNumber, 1003);
    expect(continuesAlbum(song, kept(_onPhone('2', 1004))), isTrue);

    // YouTube Music's, with an id to open it by, as before.
    final json = MediaItemBuilder.toJson(_track('a', 3));
    expect(json.containsKey('albumName'), isFalse);
    expect(json.containsKey('albumId'), isFalse);
    expect(MediaItemBuilder.fromJson(json).albumKey, 'id:MPREb_live');
  });

  test('Library › Albums by artist: each artist\'s albums, oldest first', () {
    Album album(String id, String? artist, String? year) => Album(
          title: 'Album $id',
          browseId: id,
          artists: artist == null
              ? null
              : [
                  {'name': artist}
                ],
          year: year,
          thumbnailUrl: '',
        );
    final albums = [
      album('b2', 'Beta', '2020'),
      album('none', null, '2000'),
      album('a1', 'alpha', '1999'),
      album('b1', 'Beta', '2010'),
      album('b0', 'Beta', null),
    ];
    sortAlbumNSingles(albums, SortType.Artist, true);
    expect(albums.map((a) => a.browseId), ['a1', 'b1', 'b2', 'b0', 'none']);
  });
}
