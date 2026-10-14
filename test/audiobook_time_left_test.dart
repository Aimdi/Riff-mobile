import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/services/audiobook_playback.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/player/components/long_form_player.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:hive/hive.dart';

MediaItem _track(int n, {int? minutes}) => MediaItem(
      id: 'lv_$n',
      title: 'Chapter $n',
      album: 'The Book',
      duration: minutes == null ? null : Duration(minutes: minutes),
    );

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final chapters = <PodcastChapter>[].obs;
  @override
  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero,
          current: const Duration(minutes: 5),
          total: const Duration(minutes: 20))
      .obs;
  @override
  final currentSong = Rxn<MediaItem>(_track(2, minutes: 20));
  @override
  final currentQueue = <MediaItem>[
    _track(1, minutes: 10),
    _track(2, minutes: 20),
    _track(3, minutes: 30),
  ].obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('time left in a book', () {
    final book = [
      _track(1, minutes: 10),
      _track(2, minutes: 20),
      _track(3, minutes: 30),
    ];

    test('the rest of the track and every one after it', () {
      expect(bookTimeLeft(book, 1, const Duration(minutes: 5)),
          const Duration(minutes: 45));
      // The player's own length for the track playing wins.
      expect(
          bookTimeLeft(book, 1, const Duration(minutes: 5),
              trackLength: const Duration(minutes: 25)),
          const Duration(minutes: 50));
      expect(bookTimeLeft(book, 2, const Duration(minutes: 31)), Duration.zero);
    });

    test('at the speed it plays at', () {
      expect(bookTimeLeft(book, 1, const Duration(minutes: 5), speed: 1.5),
          const Duration(minutes: 30));
      expect(bookTimeLeft(book, 1, const Duration(minutes: 5), speed: 0),
          const Duration(minutes: 45));
    });

    test("unknown when a length isn't known, or no such track", () {
      expect(
          bookTimeLeft([_track(1, minutes: 10), _track(2)], 0, Duration.zero),
          isNull);
      expect(bookTimeLeft([_track(1)], 0, Duration.zero), isNull);
      expect(bookTimeLeft(book, 3, Duration.zero), isNull);
      expect(bookTimeLeft(book, -1, Duration.zero), isNull);
    });
  });

  group('the chapter line', () {
    late _FakePlayer player;

    setUp(
        () => player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer);
    tearDown(Get.reset);

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(GetMaterialApp(
          translations: Languages(),
          locale: const Locale('en'),
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: const Scaffold(body: LongFormChapterLine()),
        ));

    testWidgets('says how long is left in the book', (tester) async {
      await pump(tester);
      expect(find.text('Chapter 2 of 3 · 45 min left'), findsOneWidget);

      player.progressBarStatus.value = ProgressBarState(
          buffered: Duration.zero,
          current: const Duration(minutes: 29, seconds: 40),
          total: const Duration(minutes: 30));
      player.currentSong.value = _track(3, minutes: 30);
      await tester.pump();
      // Under a minute: just the chapter.
      expect(find.text('Chapter 3 of 3'), findsOneWidget);
    });

    testWidgets('at the book speed', (tester) async {
      await tester.runAsync(() async {
        await Hive.openBox('AppPrefs', bytes: Uint8List(0));
        await AudiobookPlayback.setSpeed(1.5);
      });
      addTearDown(() => tester.runAsync(Hive.close));
      await pump(tester);
      expect(find.text('Chapter 2 of 3 · 30 min left'), findsOneWidget);
    });

    testWidgets("not when a chapter's length is unknown", (tester) async {
      player.currentQueue.assignAll(
          [_track(1, minutes: 10), _track(2, minutes: 20), _track(3)]);
      await pump(tester);
      expect(find.text('Chapter 2 of 3'), findsOneWidget);
    });
  });
}
