import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';

import '../fakes/fake_music_services.dart';

void main() {
  late FakeMusicServices music;

  setUp(() {
    music = FakeMusicServices();
    Get.put<MusicServices>(music);
  });

  tearDown(Get.reset);

  // Settings → Home content → "Quick picks" calls this without awaiting
  // or catching it.
  test('switching back to Quick picks while offline does not throw', () async {
    music.error = Exception('offline');
    // Not put: onInit would start loading the whole feed.
    final home = HomeScreenController();
    await home.changeDiscoverContent('QP');
    expect(music.homeCalls, 1);
    expect(home.quickPicks.value.songList, isEmpty);
  });

  test('an empty home feed keeps the current Quick picks', () async {
    final home = HomeScreenController();
    // Was a RangeError on homeContentListMap[0].
    await home.changeDiscoverContent('QP');
    expect(music.homeCalls, 1);
    expect(home.quickPicks.value.songList, isEmpty);
  });
}
