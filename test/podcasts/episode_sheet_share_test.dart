import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/components/show_notes_text.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_screen.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

const _episode = MediaItem(
  id: 'podcast_ep1',
  title: 'Episode 1',
  artist: 'Show',
  duration: Duration(minutes: 40),
  extras: {
    'isPodcast': true,
    'url': 'https://cdn.example/ep1.mp3',
    'description': '12:34 The interview. More at https://show.example',
  },
);

class _FakePlayer extends GetxController implements PlayerController {
  final played = <(String, Duration)>[];

  @override
  Future<bool> playPodcastAt(MediaItem item, Duration position,
      {String? from}) async {
    played.add((item.id, position));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePlayer player;

  setUp(() async {
    await Hive.openBox('PodcastQueue', bytes: Uint8List(0));
    Get.put(PodcastQueueController());
    player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
  });
  tearDown(() async {
    Get.reset();
    await Hive.box('PodcastQueue').close();
  });

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddToQueueSheet(context, _episode),
            child: const Text('episode'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('episode'));
    await tester.pumpAndSettle();
  }

  testWidgets('the episode menu shares the episode', (tester) async {
    await openSheet(tester);
    expect(find.text('shareEpisode'), findsOneWidget);
  });

  testWidgets('a timestamp in its notes plays the episode from there',
      (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('shownotes'));
    await tester.pumpAndSettle();
    expect(find.byType(ShowNotesText), findsOneWidget);

    final text = tester
        .widget<RichText>(find.descendant(
            of: find.byType(ShowNotesText), matching: find.byType(RichText)))
        .text;
    TapGestureRecognizer? tap;
    text.visitChildren((span) {
      if (span is TextSpan && span.text == '12:34') {
        tap = span.recognizer as TapGestureRecognizer?;
      }
      return true;
    });
    tap!.onTap!();
    await tester.pumpAndSettle();
    expect(player.played,
        [('podcast_ep1', const Duration(minutes: 12, seconds: 34))]);
  });
}
