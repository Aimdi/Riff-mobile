import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/play_queue_order.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/up_next_queue.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentQueue = <MediaItem>[].obs;
  @override
  final currentSongIndex = 0.obs;
  @override
  final isShuffleModeEnabled = false.obs;
  @override
  final buttonState = PlayButtonState.paused.obs;
  @override
  ScrollController scrollController = ScrollController();
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _song(String id, String artist) =>
    MediaItem(id: id, title: 'Song $id', artist: artist);

void main() {
  tearDown(Get.reset);

  testWidgets('Up Next marks the songs you queued that are still to come',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    player.currentQueue.assignAll([
      // Played already, and the one playing: no mark.
      queuedByYou(_song('played0000a', 'Earlier')),
      queuedByYou(_song('now0000000a', 'Playing')),
      queuedByYou(_song('mine000000a', 'Mine')),
      _song('album00000a', 'From the album'),
    ]);
    player.currentSongIndex.value = 1;
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(body: UpNextQueue(isQueueInSlidePanel: false)),
    ));
    await tester.pump();

    final marks = find.byIcon(Icons.queue_music_rounded);
    expect(marks, findsOneWidget);
    // On the row of the one still to come, before its artist.
    final row = find.ancestor(of: marks, matching: find.byType(Row)).first;
    expect(
        find.descendant(of: row, matching: find.text('Mine')), findsOneWidget);
    // Read out with the row (`.tr` gives the key in tests).
    expect(find.bySemanticsLabel(RegExp('queuedByYou')), findsOneWidget);
    semantics.dispose();

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
