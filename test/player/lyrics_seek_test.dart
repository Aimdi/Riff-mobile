import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/services/playback_hardening.dart';
import 'package:harmonymusic/ui/player/components/lyric_seek_line.dart';
import 'package:harmonymusic/ui/player/components/word_synced_lyrics.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero, current: Duration.zero, total: Duration.zero)
      .obs;

  final seeks = <Duration>[];

  @override
  void seek(Duration position,
          {PlaybackCommandSource source = PlaybackCommandSource.user}) =>
      seeks.add(position);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('lyricTimeLabel', () {
    expect(lyricTimeLabel(0), '0:00');
    expect(lyricTimeLabel(-500), '0:00');
    expect(lyricTimeLabel(83000), '1:23');
    expect(lyricTimeLabel(3723000), '1:02:03');
  });

  testWidgets('LyricSeekLine shows the time and plays from the line',
      (tester) async {
    var seeked = 0;
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: Center(
            child: LyricSeekLine(positionMs: 83000, onSeek: () => seeked++)),
      ),
    ));
    expect(find.text('1:23'), findsOneWidget);
    await tester.tap(find.byTooltip('playFromHere'));
    expect(seeked, 1);
  });

  testWidgets(
      'dragging word-synced lyrics offers ▶ for the line in the middle, '
      'which plays from it', (tester) async {
    final player = _FakePlayer();
    Get.put<PlayerController>(player);
    addTearDown(Get.reset);
    // 30 lines, one every 5 s.
    final ttml = [
      for (var i = 0; i < 30; i++)
        '<p begin="${i * 5}.0" end="${i * 5 + 4}.0">Line $i</p>',
    ].join('\n');

    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: WordSyncedLyricsWidget(ttml: ttml, padding: EdgeInsets.zero),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // Following the song: no seek line.
    expect(find.byType(LyricSeekLine), findsNothing);

    await tester.drag(find.text('Line 2'), const Offset(0, -300));
    await tester.pump();
    expect(find.byType(LyricSeekLine), findsOneWidget);

    await tester.tap(find.byTooltip('playFromHere'));
    await tester.pump();
    expect(player.seeks, hasLength(1));
    // From the start of a line (every 5 s here), further into the song.
    expect(player.seeks.single.inMilliseconds % 5000, 0);
    expect(player.seeks.single, greaterThan(Duration.zero));
    // Back to following the song.
    expect(find.byType(LyricSeekLine), findsNothing);
    await tester.pumpAndSettle();
  });
}
