import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/offline_playback.dart';
import 'package:harmonymusic/ui/screens/Search/search_result_screen.dart'
    show Body;
import 'package:harmonymusic/ui/screens/Search/search_result_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

import '../fakes/fake_music_services.dart';

void main() {
  late FakeMusicServices music;
  late SearchResultScreenController c;

  setUp(() {
    music = FakeMusicServices();
    Get.put<MusicServices>(music);
    // Not put: no onReady, so no search until asked.
    c = SearchResultScreenController();
    c.queryString.value = 'daft punk';
  });
  tearDown(() async {
    Get.reset();
    await OfflinePlayback.resetForTest();
  });

  test('a search that fails is told apart from one that finds nothing',
      () async {
    music.error = Exception('offline');
    await c.retrySearch();
    expect(c.searchFailed.value, isTrue);
    expect(c.isResultContentFetced.value, isTrue);
    expect(c.railItems, isEmpty);

    // Tried again: loading, then the results.
    music.error = null;
    final again = c.retrySearch();
    expect(c.searchFailed.value, isFalse);
    expect(c.isResultContentFetced.value, isFalse);
    music.searches[null]!.single.complete({
      'Songs': ['song']
    });
    await again;
    expect(c.searchFailed.value, isFalse);
    expect(c.railItems, ['Songs']);
    expect(music.searches[null], hasLength(1));
  });

  group('the page', () {
    Future<void> pumpBody(WidgetTester tester) => tester.pumpWidget(MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: Scaffold(body: Body(searchResScrController: c)),
        ));

    testWidgets('a failed search says so and tries again; no match as before',
        (tester) async {
      c.searchFailed.value = true;
      c.isResultContentFetced.value = true;
      await pumpBody(tester);
      // Labels show their keys: no translations loaded here.
      expect(find.text('searchFailed'), findsOneWidget);
      expect(find.text('nomatch\n\'daft punk\''), findsNothing);

      await tester.tap(find.text('retry'));
      await tester.pump();
      music.searches[null]!.single.complete({});
      await tester.pump();
      expect(find.text('searchFailed'), findsNothing);
      expect(find.text('nomatch\n\'daft punk\''), findsOneWidget);
    });

    testWidgets('offline, it says you are', (tester) async {
      OfflinePlayback.offline.value = true;
      c.searchFailed.value = true;
      c.isResultContentFetced.value = true;
      await pumpBody(tester);
      expect(find.text('searchOffline'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });
  });
}
