import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/ui/player/components/lyrics_widget.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  final sought = <Duration>[];

  @override
  final isLyricsLoading = false.obs;
  @override
  final lyricsMode = 0.obs; // synced
  @override
  RxMap<String, dynamic> lyrics = <String, dynamic>{
    'synced': '[00:01.00]First line\n[00:05.50]Second line',
    'plainLyrics': 'NA',
  }.obs;
  @override
  final lyricUi = UINetease();
  @override
  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero, current: Duration.zero, total: Duration.zero)
      .obs;
  @override
  final currentSong = Rxn<MediaItem>(const MediaItem(id: 's', title: 'S'));
  @override
  void seek(Duration position, {Object? source}) => sought.add(position);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePlayer player;

  setUp(() async {
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  Future<void> pumpLyrics(WidgetTester tester, {required bool screenReader}) =>
      tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(accessibleNavigation: screenReader),
            child: const Scaffold(body: LyricsWidget(padding: EdgeInsets.zero)),
          ),
        ),
      ));

  testWidgets('drawn as before without a screen reader', (tester) async {
    await pumpLyrics(tester, screenReader: false);
    expect(find.byType(ReadableSyncedLyrics), findsNothing);
    expect(find.text('First line'), findsNothing);
  });

  testWidgets(
      'with TalkBack, synced lyrics are text a line at a time; a double-tap '
      'plays from that line', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLyrics(tester, screenReader: true);
    expect(find.text('First line'), findsOneWidget);
    expect(find.text('Second line'), findsOneWidget);
    expect(
        tester.getSemantics(find.text('Second line')),
        containsSemantics(
            label: 'Second line',
            hasTapAction: true,
            onTapHint: 'playFromHere'));

    tester.semantics.performAction(
        find.semantics.byLabel('Second line'), SemanticsAction.tap);
    expect(player.sought, [const Duration(milliseconds: 5500)]);
    semantics.dispose();
  });
}
