import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart';
import 'package:harmonymusic/utils/helper.dart';

MediaItem _song(String id, String title,
        {String? artist, String? album, Map<String, String>? albumMap}) =>
    MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      extras: albumMap == null ? null : {'album': albumMap},
    );

List<String> _ids(List songs) => [for (final s in songs) (s as MediaItem).id];

void main() {
  final songs = [
    _song('1', 'Zebra', artist: 'Beta', album: 'Two'),
    _song('2', 'Apple', artist: 'alpha', album: 'Two'),
    _song('3', 'Mango', artist: 'Alpha', album: 'One'),
    _song('4', 'Kiwi'),
    // YouTube's album map wins over the plain field.
    _song('5', 'Banana',
        artist: 'Beta', album: 'Zzz', albumMap: {'name': 'One', 'id': 'x'}),
  ];

  test('by artist: each artist together, by album then title; none last', () {
    final list = [...songs];
    sortSongsNVideos(list, SortType.Artist, true);
    expect(_ids(list), ['3', '2', '5', '1', '4']);
  });

  test('by album: each album together, by artist then title', () {
    final list = [...songs];
    sortSongsNVideos(list, SortType.Album, true);
    expect(_ids(list), ['3', '5', '2', '1', '4']);
  });

  test('descending turns it round', () {
    final list = [...songs];
    sortSongsNVideos(list, SortType.Artist, false);
    expect(_ids(list), ['4', '1', '5', '2', '3']);
  });

  test('song lists offer artist and album', () {
    expect(songOrderSortTypes, {SortType.Artist, SortType.Album});
  });
}
