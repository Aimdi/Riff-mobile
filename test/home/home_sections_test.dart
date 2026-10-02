import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Home/home_sections.dart';

void main() {
  test('default order: Wave and generators up top, Quick picks far down', () {
    const o = defaultHomeSectionOrder;
    expect(o.indexOf(HomeSection.riffWave),
        lessThan(o.indexOf(HomeSection.speedDial)));
    expect(
        o.indexOf(HomeSection.generators), o.indexOf(HomeSection.riffWave) + 1);
    expect(o.indexOf(HomeSection.quickPicks),
        greaterThan(o.indexOf(HomeSection.shelves)));
  });

  test('default order lists every section once', () {
    expect(defaultHomeSectionOrder.toSet().length, HomeSection.values.length);
    expect(defaultHomeSectionOrder.length, HomeSection.values.length);
  });

  test('stored order wins, unknown names drop, new sections append', () {
    final order = parseHomeSectionOrder(
        ['yourWeek', 'speedDial', 'bogus', 'speedDial', 'quickPicks']);
    expect(order.take(3).toList(),
        [HomeSection.yourWeek, HomeSection.speedDial, HomeSection.quickPicks]);
    expect(order.toSet().length, HomeSection.values.length);
    // Everything the stored list didn't know comes after, in default order.
    final rest = order.skip(3).toList();
    expect(
        rest, defaultHomeSectionOrder.where((s) => !order.take(3).contains(s)));
  });

  test('nothing stored means the default', () {
    expect(parseHomeSectionOrder(null), defaultHomeSectionOrder);
    expect(parseHomeSectionOrder('garbage'), defaultHomeSectionOrder);
    expect(parseHiddenHomeSections(null), isEmpty);
    expect(parseHiddenHomeSections(['chips', 'nope']), {HomeSection.chips});
  });

  group('HomeSectionPrefs (no Hive: in memory)', () {
    setUp(HomeSectionPrefs.reset);

    test('move hops over hidden sections', () {
      // chips, resume, riffWave, …  hide resume, move riffWave up
      HomeSectionPrefs.setHidden(HomeSection.resume, true);
      HomeSectionPrefs.move(HomeSection.riffWave, -1);
      expect(HomeSectionPrefs.visible.first, HomeSection.riffWave);
      expect(HomeSectionPrefs.visible.contains(HomeSection.resume), isFalse);
      expect(HomeSectionPrefs.isDefault, isFalse);
    });

    test('move at the edge is a no-op', () {
      HomeSectionPrefs.move(HomeSection.chips, -1);
      HomeSectionPrefs.move(HomeSection.yourWeek, 1);
      expect(HomeSectionPrefs.isDefault, isTrue);
    });

    test('reorder follows ReorderableListView semantics', () {
      HomeSectionPrefs.reorder(0, 3); // drag chips below riffWave
      expect(HomeSectionPrefs.order.take(3).toList(),
          [HomeSection.resume, HomeSection.riffWave, HomeSection.chips]);
      HomeSectionPrefs.reset();
      expect(HomeSectionPrefs.isDefault, isTrue);
    });
  });
}
