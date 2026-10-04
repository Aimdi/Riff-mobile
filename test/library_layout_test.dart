import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Library/library.dart';

void main() {
  test('library grid: 3 columns on phones, 2 when narrow, more on tablets',
      () {
    expect(libraryGridMetrics(360).columns, 2);
    expect(libraryGridMetrics(411).columns, 3);
    expect(libraryGridMetrics(800).columns, 4);
    expect(libraryGridMetrics(1200).columns, 6);
  });

  test('covers fill the row between the gutters', () {
    final g = libraryGridMetrics(411);
    // 16 gutter each side (restyle §4.2), 12 between three covers.
    expect(g.cover * 3 + 16 * 2 + 12 * 2, closeTo(411, 0.001));
  });
}
