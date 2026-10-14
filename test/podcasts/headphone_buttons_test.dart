import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/headphone_controls.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/podcast_bookmarks.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_settings_screen.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

class _FakeMusic extends GetxService implements MusicServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records the player's seeks.
class _Handler extends BaseAudioHandler {
  final seeks = <Duration>[];

  @override
  Future<void> seek(Duration position) async => seeks.add(position);
}

const _episode = MediaItem(
  id: 'podcast_1',
  title: 'Episode 12',
  artist: 'The Show',
  duration: Duration(hours: 1),
  extras: {'isPodcast': true},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    await Hive.openBox(PodcastBookmarkStore.box, bytes: Uint8List(0));
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  test('skip until set otherwise, and kept', () async {
    expect(HeadphoneControls.next, HeadphoneAction.skip);
    expect(HeadphoneControls.previous, HeadphoneAction.skip);

    await HeadphoneControls.set(HeadphoneAction.chapter, next: true);
    await HeadphoneControls.set(HeadphoneAction.bookmark, next: false);
    expect(HeadphoneControls.next, HeadphoneAction.chapter);
    expect(HeadphoneControls.previous, HeadphoneAction.bookmark);
    expect(Hive.box('AppPrefs').get(HeadphoneControls.nextKey), 'chapter');

    await Hive.box('AppPrefs').put(HeadphoneControls.nextKey, 'nonsense');
    expect(HeadphoneControls.next, HeadphoneAction.skip);
  });

  group('the player', () {
    late PlayerController player;
    late _Handler handler;

    setUp(() {
      Get.put<MusicServices>(_FakeMusic());
      player = Get.put(PlayerController());
      handler = _Handler();
    });
    tearDown(() async {
      Get.delete<PlayerController>();
      // End the controller's wait for the audio handler.
      Get.put<AudioHandler>(_Handler());
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    /// Runs [body] with [handler] there, all at once: the player's own
    /// start, which would find it at its next look, needs AudioService.
    void withHandler(void Function() body) {
      Get.put<AudioHandler>(handler);
      try {
        body();
      } finally {
        Get.delete<AudioHandler>();
      }
    }

    void playAt(MediaItem item, Duration at) {
      player.currentSong.value = item;
      player.progressBarStatus.update((s) {
        s!.current = at;
        s.total = item.duration ?? Duration.zero;
      });
    }

    test("an episode's next and previous chapter", () {
      late bool forward, back;
      withHandler(() {
        playAt(_episode, const Duration(seconds: 90));
        player.chapters.assignAll([
          PodcastChapter(startSec: 0, title: 'Intro'),
          PodcastChapter(startSec: 60, title: 'One'),
          PodcastChapter(startSec: 600, title: 'Two'),
        ]);
        forward = player.skipChapter(forward: true);
        back = player.skipChapter(forward: false);
      });
      expect(forward && back, isTrue);
      // On to Two; back to the start of One (30 s into it).
      expect(handler.seeks,
          [const Duration(seconds: 600), const Duration(seconds: 60)]);
    });

    test('none to go to: false (the handler skips instead)', () {
      late bool none, music;
      withHandler(() {
        playAt(_episode, const Duration(seconds: 90));
        none = player.skipChapter(forward: true);
        playAt(const MediaItem(id: 'song', title: 'Song'),
            const Duration(seconds: 90));
        player.chapters.assignAll([PodcastChapter(startSec: 0, title: 'x')]);
        music = player.skipChapter(forward: true);
      });
      expect(none, isFalse);
      expect(music, isFalse);
      expect(handler.seeks, isEmpty);
    });

    test('a bookmark where the episode is', () async {
      playAt(_episode, const Duration(minutes: 12, seconds: 34));
      final bookmark = await player.bookmarkHere();
      expect(bookmark!.positionMs, (12 * 60 + 34) * 1000);
      expect(PodcastBookmarkStore.forEpisode('podcast_1').single.showTitle,
          'The Show');

      playAt(const MediaItem(id: 'song', title: 'Song'), Duration.zero);
      expect(await player.bookmarkHere(), isNull);
    });
  });

  testWidgets('Podcast settings set them', (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(
          body: SingleChildScrollView(child: HeadphoneButtonsSetting())),
    ));
    expect(find.text('headphoneButtons'), findsOneWidget);
    expect(find.text('skipForward'), findsOneWidget);
    expect(find.text('skipBack'), findsOneWidget);

    await tester.tap(find.text('skipForward'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('nextChapter').last);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(HeadphoneControls.next, HeadphoneAction.chapter);
    expect(find.text('nextChapter'), findsOneWidget);
    expect(HeadphoneControls.previous, HeadphoneAction.skip);
  });
}
