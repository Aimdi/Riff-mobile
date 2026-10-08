import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/podcast_playback_profile.dart';
import 'package:harmonymusic/ui/player/components/long_form_player.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final isSleepTimerActive = false.obs;
  @override
  final timerDurationLeft = 0.obs;
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();
  @override
  bool get isCurrentSongPodcast =>
      currentSong.value?.extras?['isPodcast'] == true;
  @override
  PodcastPlaybackProfile get currentPodcastProfile =>
      const PodcastPlaybackProfile(
          speed: 1.25, skipBackSec: 15, skipForwardSec: 30);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final podcastContinuousPlaybackEnabled = false.obs;
  @override
  final playbackSpeed = 1.0.obs;
  @override
  final podcastVideoEnabled = false.obs;

  @override
  void togglePodcastContinuousPlayback(bool val) =>
      podcastContinuousPlaybackEnabled.value = val;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePlayer player;
  late _FakeSettings settings;

  setUp(() {
    Get.reset();
    player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    settings =
        Get.put<SettingsScreenController>(_FakeSettings()) as _FakeSettings;
  });
  tearDown(Get.reset);

  Future<void> pumpTiles(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(
          body: SingleChildScrollView(child: LongFormToolTiles())),
    ));
  }

  // No translations loaded here, so labels show their keys.
  testWidgets('an audiobook gets speed, sleep timer and chapters',
      (tester) async {
    player.currentSong.value =
        const MediaItem(id: 'lv_book_3', title: 'Chapter 3');
    await pumpTiles(tester);

    expect(find.text('speed'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    expect(find.text('sleepTimer'), findsOneWidget);
    expect(find.text('chapters'), findsOneWidget);
    expect(find.text('shownotes'), findsNothing);
    expect(find.text('autoplayEpisodes'), findsNothing);
  });

  testWidgets('a podcast gets shownotes and an autoplay switch',
      (tester) async {
    player.currentSong.value = const MediaItem(
        id: 'podcast_ep1', title: 'Episode', extras: {'isPodcast': true});
    await pumpTiles(tester);

    expect(find.text('1.25×'), findsOneWidget);
    expect(find.text('shownotes'), findsOneWidget);
    expect(find.text('chapters'), findsNothing);

    await tester.tap(find.text('autoplayEpisodes'));
    await tester.pump();
    expect(settings.podcastContinuousPlaybackEnabled.value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('the sleep timer shows the time left', (tester) async {
    player.currentSong.value =
        const MediaItem(id: 'lv_book_3', title: 'Chapter 3');
    player.isSleepTimerActive.value = true;
    player.timerDurationLeft.value = 600;
    await pumpTiles(tester);
    expect(find.text('10m left'), findsOneWidget);
  });
}
