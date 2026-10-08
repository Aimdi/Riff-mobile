import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_builder.dart';
import 'package:harmonymusic/ui/screens/Home/home_sections.dart';
import 'package:hive/hive.dart';

HomeItem _item(String key) => HomeItem(key, key);

/// Prefs saved by 1.7.148 and older, when Riff Wave was a Home section,
/// read back by today's Home (Riff Wave lives in the Discover tab).
/// Its own file: [HomeSectionPrefs] reads AppPrefs once per isolate.
void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('riff_home_prefs_');
    Hive.init(tmp.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('a saved order and hidden list naming riffWave load without a gap',
      () async {
    final prefs = await Hive.openBox('AppPrefs');
    await prefs.put('homeSectionOrder', [
      'jumpBackIn',
      'riffWave',
      'speedDial',
      'quickPicks',
      'personalized',
      'yourWeek',
      'editorial',
    ]);
    await prefs.put(HomeSectionPrefs.hiddenKey, ['riffWave', 'yourWeek']);

    HomeSectionPrefs.ensureLoaded();

    // riffWave is dropped, the rest of the hidden list still applies, and
    // the custom order from older versions is cleared.
    expect(HomeSectionPrefs.hidden, {HomeSection.yourWeek});
    expect(prefs.get('homeSectionOrder'), isNull);

    final sections = buildHomeSections(HomeFeedInput(
      jumpBackIn: [_item('ep:1'), _item('session:q')],
      speedDial: [for (var i = 0; i < 3; i++) _item('song:d$i')],
      quickPicks: [for (var i = 0; i < 3; i++) _item('song:q$i')],
      editorial: [
        HomeShelfData(id: 'shelf', title: 'Shelf', items: [
          for (var i = 0; i < 5; i++) _item('pl:$i'),
        ]),
      ],
      hasWeek: true,
      hidden: HomeSectionPrefs.hidden.toSet(),
    ));
    // Jump back in is followed directly by Speed dial: no empty slot
    // where Riff Wave was.
    expect([
      for (final m in sections) m.section
    ], [
      HomeSection.header,
      HomeSection.jumpBackIn,
      HomeSection.speedDial,
      HomeSection.quickPicks,
      HomeSection.editorial,
    ]);

    // Saving again writes only today's names.
    HomeSectionPrefs.setHidden(HomeSection.quickPicks, true);
    expect(prefs.get(HomeSectionPrefs.hiddenKey),
        unorderedEquals(['yourWeek', 'quickPicks']));
  });
}
