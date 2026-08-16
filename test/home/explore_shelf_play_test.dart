import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/ui/screens/Home/home_explore_section.dart';

void main() {
  test('firstExploreShelfItem reads the first album or playlist', () {
    final album = Album(
      title: 'LP',
      browseId: 'MPREb_1',
      artists: const [
        {'name': 'A'}
      ],
      year: '2024',
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
    );
    expect(
      firstExploreShelfItem(
        AlbumContent(title: 'Charts', albumList: [album]),
      ),
      album,
    );
    expect(
      firstExploreShelfItem(AlbumContent(title: 'Empty', albumList: const [])),
      isNull,
    );
  });
}
