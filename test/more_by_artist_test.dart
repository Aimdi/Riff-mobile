import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/ui/screens/Album/more_by_artist.dart';

Album _album(String id) => Album(
    title: 'Album $id', browseId: id, thumbnailUrl: '', artists: const []);

void main() {
  test("albums, then singles; not the one open, nor twice", () {
    final page = <String, dynamic>{
      'Albums': {
        'content': [_album('a1'), _album('open'), _album('a2')]
      },
      'Singles': {
        'content': [_album('s1'), _album('a1'), _album('')]
      },
    };
    expect(moreByArtistAlbums(page, 'open').map((a) => a.browseId),
        ['a1', 'a2', 's1']);
  });

  test('the album open by another id is still left out, by its title', () {
    final page = <String, dynamic>{
      'Albums': {
        'content': [_album('MPRE1'), _album('MPRE2')]
      },
    };
    expect(
        moreByArtistAlbums(page, 'OLAK5uy_x', currentTitle: ' album mpre1')
            .map((a) => a.browseId),
        ['MPRE2']);
  });

  test('at most a dozen', () {
    final page = <String, dynamic>{
      'Albums': {
        'content': [for (var i = 0; i < 20; i++) _album('a$i')]
      },
    };
    expect(moreByArtistAlbums(page, 'x'), hasLength(12));
    expect(moreByArtistAlbums(page, 'x', max: 3).map((a) => a.browseId),
        ['a0', 'a1', 'a2']);
  });

  test('an artist page without releases: nothing', () {
    expect(moreByArtistAlbums({'Albums': null, 'Singles': null}, 'x'), isEmpty);
    expect(moreByArtistAlbums({}, 'x'), isEmpty);
  });
}
