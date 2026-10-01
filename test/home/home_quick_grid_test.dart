import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Home/home_quick_grid.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  bool initFlagForPlayer = true;
  @override
  final showContinueListening = false.obs;
  @override
  final continueListeningTitle = ''.obs;
  @override
  final continueListeningItem = Rxn<MediaItem>();

  @override
  void dismissContinueListening() => showContinueListening.value = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;
  late _FakePlayer player;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('riff_quick_grid_');
    Hive.init(tmp.path);
    await Hive.openBox('PodcastProgress');
  });

  tearDownAll(() async {
    await Hive.close();
    tmp.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box('PodcastProgress').clear();
    player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
  });

  tearDown(Get.reset);

  Future<void> pumpGrid(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(411, 914));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const GetMaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: HomeQuickGrid())),
    ));
  }

  testWidgets(
      'nothing to resume: builds without the empty-Obx error that painted '
      'a full-height grey box over Home', (tester) async {
    await pumpGrid(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('favorites'), findsOneWidget);
    expect(find.text('downloads'), findsOneWidget);
    expect(find.text('continueListening'), findsNothing);
  });

  testWidgets('saved queue: one full-width tile that can be dismissed',
      (tester) async {
    player.continueListeningItem.value = const MediaItem(
      id: 'song1',
      title: 'Retrograde',
      artist: 'James Blake',
    );
    player.showContinueListening.value = true;
    await pumpGrid(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('continueListening'), findsOneWidget);
    expect(find.text('Retrograde · James Blake'), findsOneWidget);

    await tester.tap(find.byTooltip('dismiss'));
    await tester.pump();
    expect(find.text('Retrograde · James Blake'), findsNothing);
  });

  group('with an in-progress podcast', () {
    setUp(() async {
      await Hive.box('PodcastProgress').put('podcast_ep1', {
        'id': 'podcast_ep1',
        'title': 'Episode one',
        'artist': 'Some Show',
        'positionMs': 600000,
        'durationMs': 2400000,
        'updatedAt': 1,
      });
    });

    testWidgets('alone: full-width tile with its label', (tester) async {
      await pumpGrid(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('continuePodcast'), findsOneWidget);
      expect(find.text('Episode one'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('with a saved queue: both share one row', (tester) async {
      player.continueListeningItem.value =
          const MediaItem(id: 'song1', title: 'Retrograde');
      player.showContinueListening.value = true;
      await pumpGrid(tester);

      expect(tester.takeException(), isNull);
      final session = tester.getRect(find.text('Retrograde'));
      final episode = tester.getRect(find.text('Episode one'));
      expect(session.top, episode.top);
      // Half-width tiles drop the labels and the close button.
      expect(find.text('continueListening'), findsNothing);
      expect(find.byTooltip('dismiss'), findsNothing);
    });

    testWidgets('hidden while that episode is already playing', (tester) async {
      player.currentSong.value =
          const MediaItem(id: 'podcast_ep1', title: 'Episode one');
      player.initFlagForPlayer = false;
      await pumpGrid(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Episode one'), findsNothing);
    });
  });
}
