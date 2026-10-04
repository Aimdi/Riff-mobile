import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Home/home_sections.dart';

void main() {
  test('the header and Explore more cannot be switched off', () {
    expect(switchableHomeSections, isNot(contains(HomeSection.header)));
    expect(switchableHomeSections, isNot(contains(HomeSection.exploreMore)));
  });

  test('hidden sections stored by older versions carry over', () {
    expect(
        parseHiddenHomeSections(
            ['resume', 'dailyMixes', 'shelves', 'chips', 'generators']),
        {
          HomeSection.jumpBackIn,
          HomeSection.personalized,
          HomeSection.editorial,
        });
    expect(parseHiddenHomeSections(['speedDial', 'yourWeek', 'bogus']),
        {HomeSection.speedDial, HomeSection.yourWeek});
    expect(parseHiddenHomeSections(null), isEmpty);
    expect(parseHiddenHomeSections('garbage'), isEmpty);
  });

  group('HomeSectionPrefs (no Hive: in memory)', () {
    setUp(HomeSectionPrefs.reset);

    test('hide and show', () {
      HomeSectionPrefs.setHidden(HomeSection.quickPicks, true);
      expect(HomeSectionPrefs.hidden, {HomeSection.quickPicks});
      expect(HomeSectionPrefs.isDefault, isFalse);
      HomeSectionPrefs.setHidden(HomeSection.quickPicks, false);
      expect(HomeSectionPrefs.isDefault, isTrue);
    });
  });
}
