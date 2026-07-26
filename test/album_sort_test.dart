import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart' show SortType;
import 'package:harmonymusic/utils/helper.dart';

Album album(String title, String? year) => Album(
      title: title,
      browseId: 'id_$title',
      artists: const [
        {'name': 'someone'}
      ],
      year: year,
      thumbnailUrl: '',
    );

List<String> titles(List list) => list.map((e) => e.title as String).toList();

void main() {
  group('sortAlbumNSingles', () {
    test('SortType.Date orders by year, not by title', () {
      // Titles are deliberately in the opposite order of the years, so a
      // title-based comparator (the old inverted behaviour) fails here.
      final albums = [
        album('Alpha', '2020'),
        album('Bravo', '1998'),
        album('Charlie', '2007'),
      ];

      sortAlbumNSingles(albums, SortType.Date, true);

      expect(titles(albums), ['Bravo', 'Charlie', 'Alpha']);
    });

    test('SortType.Date descending reverses the chronological order', () {
      final albums = [
        album('Alpha', '2020'),
        album('Bravo', '1998'),
        album('Charlie', '2007'),
      ];

      sortAlbumNSingles(albums, SortType.Date, false);

      expect(titles(albums), ['Alpha', 'Charlie', 'Bravo']);
    });

    test('SortType.Name orders by title case-insensitively, not by year', () {
      // Years are deliberately in the opposite order of the titles, so a
      // year-based comparator (the old inverted behaviour) fails here.
      final albums = [
        album('charlie', '1998'),
        album('Alpha', '2020'),
        album('bravo', '2007'),
      ];

      sortAlbumNSingles(albums, SortType.Name, true);

      expect(titles(albums), ['Alpha', 'bravo', 'charlie']);
    });

    test('SortType.Name descending reverses the alphabetical order', () {
      final albums = [
        album('charlie', '1998'),
        album('Alpha', '2020'),
        album('bravo', '2007'),
      ];

      sortAlbumNSingles(albums, SortType.Name, false);

      expect(titles(albums), ['charlie', 'bravo', 'Alpha']);
    });

    test('SortType.Name still sorts by title when years are null', () {
      final albums = [
        album('Charlie', null),
        album('Alpha', null),
        album('Bravo', null),
      ];

      sortAlbumNSingles(albums, SortType.Name, true);

      expect(titles(albums), ['Alpha', 'Bravo', 'Charlie']);
    });

    test('SortType.Date treats a null year as equal instead of throwing', () {
      final albums = [
        album('Alpha', null),
        album('Bravo', '1998'),
        album('Charlie', null),
        album('Delta', '2007'),
      ];

      // Must not throw on the null years.
      sortAlbumNSingles(albums, SortType.Date, true);

      expect(albums.length, 4);
      expect(titles(albums).toSet(), {'Alpha', 'Bravo', 'Charlie', 'Delta'});
      // The two dated albums keep their relative chronological order.
      final dated = titles(albums).where((t) => t == 'Bravo' || t == 'Delta');
      expect(dated.toList(), ['Bravo', 'Delta']);
    });
  });
}
