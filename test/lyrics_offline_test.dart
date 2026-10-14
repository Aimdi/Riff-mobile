import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/ui/player/components/lyrics_widget.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final isLyricsLoading = false.obs;
  @override
  final lyricsMode = 1.obs;
  @override
  RxMap<String, dynamic> lyrics = <String, dynamic>{}.obs;
  @override
  final lyricUi = UINetease();
  @override
  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero, current: Duration.zero, total: Duration.zero)
      .obs;
  @override
  final currentSong = Rxn();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('missing lyrics: none of any kind', () {
    expect(lyricsMissing({'synced': '', 'plainLyrics': 'NA'}), isTrue);
    expect(lyricsMissing({'synced': null, 'plainLyrics': 'NA'}), isTrue);
    expect(lyricsMissing({'synced': '[00:01.00] la', 'plainLyrics': 'NA'}),
        isFalse);
    expect(lyricsMissing({'synced': '', 'plainLyrics': 'la la'}), isFalse);
    expect(
        lyricsMissing(
            {'synced': '', 'plainLyrics': 'NA', 'ttml': '<tt>la</tt>'}),
        isFalse);
  });

  group('the lyrics', () {
    late _FakePlayer player;

    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
      player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    });
    tearDown(() async {
      Get.reset();
      await Hive.close();
    });

    Future<void> pumpLyrics(WidgetTester tester) =>
        tester.pumpWidget(MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: const Scaffold(body: LyricsWidget(padding: EdgeInsets.zero)),
        ));

    testWidgets(
        'none for want of a connection says so, plain and synced; none at all '
        'as before', (tester) async {
      player.lyrics.value = {
        'synced': '',
        'plainLyrics': 'NA',
        'offline': true
      };
      await pumpLyrics(tester);
      // Labels show their keys: no translations loaded here.
      expect(find.text('lyricsOffline'), findsOneWidget);

      player.lyricsMode.value = 0;
      await tester.pump();
      expect(find.text('lyricsOffline'), findsOneWidget);

      player.lyrics.value = {'synced': '', 'plainLyrics': 'NA'};
      await tester.pump();
      expect(find.text('syncedLyricsNotAvailable'), findsOneWidget);
      player.lyricsMode.value = 1;
      await tester.pump();
      expect(find.text('lyricsNotAvailable'), findsOneWidget);
    });
  });
}
