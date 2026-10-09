import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/screens/Search/search_result_screen_controller.dart';

import '../fakes/fake_music_services.dart';

/// Counts the listeners added to it.
class _CountingScroll extends ScrollController {
  int added = 0;
  @override
  void addListener(VoidCallback listener) {
    added++;
    super.addListener(listener);
  }
}

void main() {
  late FakeMusicServices music;
  late SearchResultScreenController c;

  setUp(() {
    music = FakeMusicServices();
    Get.put<MusicServices>(music);
    c = SearchResultScreenController();
    c.railItems.assignAll(['Songs', 'Albums']);
    c.scrollControllers['Songs'] = _CountingScroll();
    c.scrollControllers['Albums'] = _CountingScroll();
  });

  tearDown(Get.reset);

  test('a slower load for a tab the user left does not mark the new tab loaded',
      () async {
    final songs = c.onDestinationSelected(1);
    final albums = c.onDestinationSelected(2);

    // Songs answers while Albums is on screen and still loading.
    music.searches['songs']!.single.complete({
      'Songs': ['song'],
      'params': null,
    });
    await songs;
    expect(c.navigationRailCurrentIndex.value, 2);
    expect(c.separatedResultContent['Songs'], ['song']);
    // Was true here: the Albums list (still null) went to the list widget.
    expect(c.isSeparatedResultContentFetced.value, isFalse);
    expect(c.separatedResultContent.containsKey('Albums'), isFalse);

    music.searches['albums']!.single.complete({
      'Albums': ['album'],
      'params': null,
    });
    await albums;
    expect(c.separatedResultContent['Albums'], ['album']);
    expect(c.isSeparatedResultContentFetced.value, isTrue);
  });

  test('going back to a tab that is still loading reuses its request',
      () async {
    final first = c.onDestinationSelected(1);
    await c.onDestinationSelected(0);
    final again = c.onDestinationSelected(1);
    expect(music.searches['songs'], hasLength(1));

    music.searches['songs']!.single.complete({
      'Songs': ['song'],
      'params': null,
    });
    await Future.wait([first, again]);
    expect(c.isSeparatedResultContentFetced.value, isTrue);
    expect((c.scrollControllers['Songs'] as _CountingScroll).added, 1);
  });

  test('reloading a tab whose first page was empty adds no second listener',
      () async {
    final first = c.onDestinationSelected(1);
    music.searches['songs']!.single.complete({'Songs': [], 'params': null});
    await first;

    final again = c.onDestinationSelected(1);
    expect(music.searches['songs'], hasLength(2));
    music.searches['songs']!.last.complete({
      'Songs': ['song'],
      'params': null,
    });
    await again;
    expect(c.separatedResultContent['Songs'], ['song']);
    expect((c.scrollControllers['Songs'] as _CountingScroll).added, 1);
  });

  test('a failed tab load falls back to the overview items', () async {
    c.resultContent['Albums'] = ['overview album'];
    music.error = Exception('offline');
    await c.onDestinationSelected(2);
    expect(c.isSeparatedResultContentFetced.value, isTrue);
    expect(c.separatedResultContent['Albums'], isNotNull);
  });
}
