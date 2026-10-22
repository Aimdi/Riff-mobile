import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/ui/player/components/lyric_line_preview.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>(const MediaItem(id: 'a', title: 'A'));
  @override
  RxMap<String, dynamic> lyrics = <String, dynamic>{
    'synced': '[00:01.00]One\n[00:03.00]Two',
    'plainLyrics': '',
    'source': 'lrclib',
  }.obs;
  @override
  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero,
          current: const Duration(milliseconds: 3200),
          total: const Duration(minutes: 3))
      .obs;
  @override
  bool get usesLongFormTransport => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// What the player does on a skip: the new song, its lyrics not in yet.
  void skipTo(String id) {
    currentSong.value = MediaItem(id: id, title: id);
    lyrics.value = {'synced': '', 'plainLyrics': '', 'ttml': ''};
  }
}

void main() {
  late _FakePlayer player;
  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
  });
  tearDown(() async {
    Get.reset();
    await Hive.box('AppPrefs').close();
  });

  Future<double> pumpPreview(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(
          body: Align(
              alignment: Alignment.topCenter, child: LyricLinePreview())),
    ));
    await tester.pumpAndSettle();
    return tester.getSize(find.byType(LyricLinePreview)).height;
  }

  double height(WidgetTester tester) =>
      tester.getSize(find.byType(LyricLinePreview)).height;

  double rowOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.descendant(
          of: find.byType(LyricLinePreview),
          matching: find.byType(AnimatedOpacity)))
      .opacity;

  testWidgets('a skip keeps the line\'s room while the next lyrics load',
      (tester) async {
    final shown = await pumpPreview(tester);
    expect(shown, greaterThan(0));
    expect(find.text('Two'), findsOneWidget);

    player.skipTo('b');
    await tester.pumpAndSettle();
    // Same room, the old line faded out (no drop now, rise in a moment).
    expect(height(tester), shown);
    expect(rowOpacity(tester), 0);

    // The new song's lyrics: its line fades in where the old one was.
    player.lyrics.value = {
      'synced': '[00:01.00]Uno\n[00:03.00]Dos',
      'plainLyrics': '',
      'source': 'lrclib',
    };
    await tester.pumpAndSettle();
    expect(height(tester), shown);
    expect(rowOpacity(tester), 1);
    expect(find.text('Dos'), findsOneWidget);
    expect(find.text('Two'), findsNothing);
  });

  testWidgets('a song known to have no synced lyrics closes it up, as before',
      (tester) async {
    await pumpPreview(tester);
    player.skipTo('b');
    await tester.pumpAndSettle();
    player.lyrics.value = {'synced': '', 'plainLyrics': 'NA'};
    await tester.pumpAndSettle();
    expect(height(tester), 0);
    expect(find.text('Two'), findsNothing);
  });

  testWidgets('no line before the skip: nothing is held', (tester) async {
    player.lyrics.value = {'synced': '', 'plainLyrics': 'NA'};
    expect(await pumpPreview(tester), 0);
    player.skipTo('b');
    await tester.pumpAndSettle();
    expect(height(tester), 0);
  });
}
