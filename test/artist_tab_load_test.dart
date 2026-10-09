import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/screens/Artists/artist_screen_controller.dart';

import 'fakes/fake_music_services.dart';

/// Counts the listeners added to it.
class _CountingScroll extends ScrollController {
  int added = 0;
  @override
  void addListener(VoidCallback listener) {
    added++;
    super.addListener(listener);
  }
}

/// The artist controller with a Songs list controller the test can watch.
class _Artist extends ArtistScreenController {
  final songs = _CountingScroll();
  @override
  ScrollController get songScrollController => songs;
}

Map<String, dynamic> _page(String item) => {
      'results': [item],
      'additionalParams': '&ctoken=null&continuation=null',
    };

void main() {
  late FakeMusicServices music;
  late _Artist c;

  setUp(() {
    music = FakeMusicServices();
    Get.put<MusicServices>(music);
    // Not put: onInit would read route arguments and fetch the artist.
    c = _Artist();
    c.artistData.addAll({
      'Songs': {'params': 's', 'content': []},
      'Albums': {'params': 'a', 'content': []},
    });
  });

  tearDown(Get.reset);

  test('opening a tab again while it loads sends one request', () async {
    final first = c.onDestinationSelected(1);
    final again = c.onDestinationSelected(1);
    expect(music.artistTabs['Songs'], hasLength(1));
    music.artistTabs['Songs']!.single.complete(_page('song'));
    await Future.wait([first, again]);
    expect(c.sepataredContent['Songs']['results'], ['song']);
    expect(c.isSeparatedArtistContentFetced.value, isTrue);
    // One load, one load-more listener (two used to stack up).
    expect(c.songs.added, 1);
    await c.onDestinationSelected(1);
    expect(c.songs.added, 1);
  });

  test("a loaded tab is not left behind another tab's shimmer", () async {
    final songs = c.onDestinationSelected(1);
    music.artistTabs['Songs']!.single.complete(_page('song'));
    await songs;

    // Albums starts loading, then the user goes back to the loaded Songs.
    final albums = c.onDestinationSelected(3);
    expect(c.isSeparatedArtistContentFetced.value, isFalse);
    await c.onDestinationSelected(1);
    // Was still false here until the Albums request finished.
    expect(c.isSeparatedArtistContentFetced.value, isTrue);

    // Albums answering later leaves the Songs page as it is.
    music.artistTabs['Albums']!.single.complete(_page('album'));
    await albums;
    expect(c.navigationRailCurrentIndex.value, 1);
    expect(c.isSeparatedArtistContentFetced.value, isTrue);
    expect(c.sepataredContent['Albums']['results'], ['album']);
  });

  test('a failed tab load falls back to the overview shelf', () async {
    c.artistData['Songs'] = {
      'params': 's',
      'content': ['overview song']
    };
    music.error = Exception('offline');
    await c.onDestinationSelected(1);
    expect(c.isSeparatedArtistContentFetced.value, isTrue);
    expect(c.sepataredContent['Songs']['results'], ['overview song']);
  });
}
