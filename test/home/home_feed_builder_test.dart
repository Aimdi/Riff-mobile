import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_builder.dart';

HomeItem item(String key, {bool art = true}) => HomeItem(key, key, hasArt: art);

List<HomeItem> items(String prefix, int n) =>
    [for (var i = 0; i < n; i++) item('$prefix$i')];

HomeShelfData shelf(String title, List<HomeItem> list,
        {HomeShelfKind kind = HomeShelfKind.collections}) =>
    HomeShelfData(id: title, title: title, items: list, kind: kind);

List<HomeSection> order(List<HomeSectionModel> s) =>
    [for (final m in s) m.section];

HomeSectionModel section(List<HomeSectionModel> s, HomeSection which) =>
    s.firstWhere((m) => m.section == which);

void main() {
  group('order', () {
    test('full feed: fixed order, top to bottom', () {
      final s = buildHomeSections(HomeFeedInput(
        jumpBackIn: [item('ep:1'), item('session:q')],
        speedDial: items('song:d', 12),
        quickPicks: items('song:q', 6),
        personalized: [shelf('Your mixes', items('mix:', 3))],
        editorial: [
          for (var i = 0; i < 6; i++) shelf('Shelf $i', items('pl$i:', 5))
        ],
        hasWeek: true,
      ));
      expect(order(s), [
        HomeSection.header,
        HomeSection.jumpBackIn,
        HomeSection.speedDial,
        HomeSection.quickPicks,
        HomeSection.personalized,
        HomeSection.yourWeek,
        HomeSection.editorial,
        HomeSection.exploreMore,
      ]);
    });

    test('Riff Wave is not on Home (it lives in the Discover tab)', () {
      expect(
          HomeSection.values.map((s) => s.name), isNot(contains('riffWave')));
      // Speed dial follows Jump back in directly, with nothing between.
      final s = buildHomeSections(HomeFeedInput(
        jumpBackIn: [item('ep:1'), item('session:q')],
        speedDial: items('song:d', 3),
      ));
      expect(order(s), [
        HomeSection.header,
        HomeSection.jumpBackIn,
        HomeSection.speedDial,
      ]);
    });

    test('the feed cannot push the fixed sections down', () {
      // However many editorial shelves come in, and in whatever order,
      // sections 1–3 keep their places.
      final s = buildHomeSections(HomeFeedInput(
        jumpBackIn: [item('ep:1')],
        speedDial: items('song:d', 3),
        quickPicks: items('song:q', 3),
        editorial: [
          for (var i = 0; i < 20; i++) shelf('Shelf $i', items('pl$i:', 5))
        ],
      ));
      expect(order(s).take(4).toList(), [
        HomeSection.header,
        HomeSection.jumpBackIn,
        HomeSection.speedDial,
        HomeSection.quickPicks,
      ]);
    });

    test('no listening history: only the header and the feed', () {
      final s = buildHomeSections(HomeFeedInput(
        editorial: [shelf('Shelf', items('pl:', 5))],
      ));
      expect(order(s), [
        HomeSection.header,
        HomeSection.editorial,
      ]);
    });

    test('hidden sections are left out', () {
      final s = buildHomeSections(HomeFeedInput(
        speedDial: items('song:d', 3),
        hasWeek: true,
        hidden: const {HomeSection.speedDial, HomeSection.yourWeek},
      ));
      expect(order(s), [HomeSection.header]);
    });
  });

  group('each item once', () {
    test('Jump back in beats Speed dial beats Quick picks', () {
      final s = buildHomeSections(HomeFeedInput(
        jumpBackIn: [item('song:a'), item('song:b')],
        speedDial: [item('song:a'), item('song:c'), item('song:d')],
        quickPicks: [item('song:b'), item('song:c'), item('song:e')],
      ));
      expect(section(s, HomeSection.speedDial).items.map((i) => i.key),
          ['song:c', 'song:d']);
      expect(section(s, HomeSection.quickPicks).items.map((i) => i.key),
          ['song:e']);
    });

    test('Quick picks beat Speed dial pages 2 and 3', () {
      final dial = items('song:', 14);
      final s = buildHomeSections(HomeFeedInput(
        speedDial: dial,
        // song:3 is on page 1, song:12 would be on page 2.
        quickPicks: [item('song:3'), item('song:12'), item('song:x')],
      ));
      final dialKeys =
          section(s, HomeSection.speedDial).items.map((i) => i.key);
      expect(dialKeys.take(9), [for (var i = 0; i < 9; i++) 'song:$i']);
      expect(dialKeys, isNot(contains('song:12')));
      expect(section(s, HomeSection.quickPicks).items.map((i) => i.key),
          ['song:12', 'song:x']);
    });

    test('shelves drop what is already shown, then the shelf if too short', () {
      final s = buildHomeSections(HomeFeedInput(
        quickPicks: [item('a'), item('b')],
        editorial: [
          shelf('One', [item('a'), item('b'), item('c'), item('d'), item('e')]),
          shelf('Two', [item('c'), item('f'), item('g'), item('h'), item('i')]),
        ],
      ));
      final ed = section(s, HomeSection.editorial).shelves;
      // "One" keeps c, d, e: below four, so it goes.
      expect(ed.map((e) => e.title), ['Two']);
      expect(ed.single.items.map((i) => i.key), ['c', 'f', 'g', 'h', 'i']);
    });

    test('no key shows twice anywhere', () {
      final s = buildHomeSections(HomeFeedInput(
        jumpBackIn: [item('x1'), item('x2')],
        speedDial: [...items('x', 20)],
        quickPicks: [...items('x', 15)],
        personalized: [shelf('P', items('x', 10))],
        editorial: [
          shelf('E1', items('x', 30)),
          shelf('E2', items('x', 30)),
        ],
      ));
      final all = [
        for (final m in s) ...m.items,
        for (final m in s)
          for (final sh in m.shelves) ...sh.items,
      ].map((i) => i.key).toList();
      expect(all.toSet().length, all.length);
    });
  });

  group('Jump back in', () {
    test('caps at four and evens out odd counts', () {
      expect(jumpBackInTiles([1]), [1]);
      expect(jumpBackInTiles([1, 2]), [1, 2]);
      expect(jumpBackInTiles([1, 2, 3]), [1, 2]);
      expect(jumpBackInTiles([1, 2, 3, 4, 5]), [1, 2, 3, 4]);
    });

    test('a tile dropped to even the grid can show further down', () {
      final s = buildHomeSections(HomeFeedInput(
        jumpBackIn: [item('a'), item('b'), item('c')],
        speedDial: [item('c')],
      ));
      expect(section(s, HomeSection.jumpBackIn).items.length, 2);
      expect(section(s, HomeSection.speedDial).items.single.key, 'c');
    });
  });

  test('speed dial pages: one page and no dots below nine', () {
    expect(speedDialPageCount(0), 0);
    expect(speedDialPageCount(8), 1);
    expect(speedDialPageCount(9), 1);
    expect(speedDialPageCount(10), 2);
    expect(speedDialPageCount(40), 3);
  });

  group('editorial rules', () {
    test('at most four shelves; the rest go behind Explore more', () {
      final s = buildHomeSections(HomeFeedInput(editorial: [
        for (var i = 0; i < 7; i++) shelf('Shelf $i', items('p$i:', 6))
      ]));
      expect(section(s, HomeSection.editorial).shelves.length, 4);
      expect(order(s).last, HomeSection.exploreMore);
    });

    test('no overflow and nothing else to explore: no button', () {
      final s = buildHomeSections(
          HomeFeedInput(editorial: [shelf('Shelf', items('p:', 6))]));
      expect(order(s), isNot(contains(HomeSection.exploreMore)));
    });

    test('charts merge into one shelf, mood shelves into another', () {
      final r = applyEditorialRules([
        shelf("Today's biggest hits", [item('a'), item('b')]),
        shelf('Sunday breakfast', [item('m1'), item('m2')]),
        shelf('Long listening', [item('l')]),
        shelf('100% Hits', [item('b'), item('c')]),
        shelf('Charts', [item('d')]),
        shelf('Push you out of bed', [item('m3')]),
      ]);
      expect(r.editorial.map((e) => e.title),
          ['Charts & hits', 'For your mood', 'Long listening']);
      expect(r.editorial[0].items.map((i) => i.key), ['a', 'b', 'c', 'd']);
      expect(r.editorial[1].items.map((i) => i.key), ['m1', 'm2', 'm3']);
    });

    test('Throwback goes; personal shelves move up to section 5', () {
      final s = buildHomeSections(HomeFeedInput(
        personalized: [shelf('Your mixes', items('mix:', 2))],
        editorial: [
          shelf('Throwback Jams', items('t:', 6)),
          shelf('New releases', items('n:', 6)),
          shelf('Similar to Daft Punk', items('s:', 6)),
          shelf('Mixed for you', items('m:', 6)),
          shelf('Long listening', items('l:', 6)),
        ],
      ));
      expect(section(s, HomeSection.personalized).shelves.map((e) => e.title), [
        'New releases',
        'Similar to Daft Punk',
        'Mixed for you',
        'Your mixes'
      ]);
      expect(section(s, HomeSection.editorial).shelves.map((e) => e.title),
          ['Long listening']);
    });

    test('shelves with mostly missing artwork are hidden', () {
      final s = buildHomeSections(HomeFeedInput(editorial: [
        shelf('Broken', [
          item('a', art: false),
          item('b', art: false),
          item('c', art: false),
          item('d'),
          item('e'),
        ]),
        shelf('Half', [
          item('f', art: false),
          item('g', art: false),
          item('h'),
          item('i'),
        ]),
      ]));
      expect(section(s, HomeSection.editorial).shelves.map((e) => e.title),
          ['Half']);
    });
  });

  group('sentence case', () {
    test('Title Case and ALL CAPS become sentence case', () {
      expect(homeSentenceCase("Today's Biggest Hits"), "Today's biggest hits");
      expect(homeSentenceCase('QUICK PICKS'), 'Quick picks');
      expect(homeSentenceCase('Music Videos For You'), 'Music videos for you');
    });

    test('titles that are already sentence case keep their names', () {
      expect(homeSentenceCase('Similar to Taylor Swift'),
          'Similar to Taylor Swift');
      expect(homeSentenceCase('new releases'), 'New releases');
    });

    test('acronyms keep their capitals', () {
      expect(homeSentenceCase('Feel Good R&B'), 'Feel good R&B');
      expect(homeSentenceCase('Top DJ Mixes'), 'Top DJ mixes');
      expect(homeSentenceCase('100% Hits'), '100% hits');
    });
  });
}
